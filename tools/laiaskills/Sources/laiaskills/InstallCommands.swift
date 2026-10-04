import ArgumentParser
import Foundation
import LaiaSkillsKit

struct SyncCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sync",
        abstract: "Make every installed copy match its pin; run after git pull.",
        discussion: """
        Installs missing skills, re-copies skills whose pin moved, replaces copies installed by other tools \
        (backups kept), and removes skills no longer in skills.json. Copies edited in place are skipped \
        unless --force. Also repairs mirror links, including removing them from mirrors a skill skips \
        (`skipMirrors` in skills.json).
        """
    )

    @OptionGroup var options: GlobalOptions

    @Argument(help: "Only sync these skills (no removals).")
    var skills: [String] = []

    @Flag(help: "Overwrite copies that were edited in place.")
    var force = false

    @Flag(help: "Don't ask before replacing other tools' copies or removing skills.")
    var yes = false

    @Flag(name: .customLong("dry-run"), help: "Show what would change without changing anything.")
    var dryRun = false

    struct Step: Codable {
        let name: String
        let action: String
        let detail: String?
    }

    func run() throws {
        let context = try Context(options)
        var installer = Installer(repo: context.repo, environment: context.environment)
        let targets = skills.isEmpty ? context.skills : try select(skills, from: context.skills)
        var steps = installer.plan(targets, force: force)
        if !skills.isEmpty { steps.removeAll { $0.action == .remove } }
        let changes = steps.filter { $0.action != .keep }
        let ui = NooraUI()

        if options.json && dryRun { return try printJSON(changes.map(Self.describe)) }
        guard !changes.isEmpty else {
            if options.json { return try printJSON([Step]()) }
            return ui.success(steps.count == 1 ? "The skill is in sync." : "All \(steps.count) skills are in sync.")
        }
        if !options.json {
            ui.table(headers: ["Skill", "Action"], rows: changes.map { [$0.name, Self.describe($0).action] })
        }
        if dryRun { return }

        let risky = changes.filter { [.replaceForeign, .remove].contains($0.action) }
        if !risky.isEmpty, !(try approve(ui, "Replace or remove \(risky.count) skills? Previous copies go to backups.", yes: yes)) {
            throw ExitCode(1)
        }

        let byName = Dictionary(uniqueKeysWithValues: targets.map { ($0.name, $0) })
        var report: [Step] = []
        var failed = false
        for step in changes {
            do {
                switch step.action {
                case .install, .reinstall, .replaceForeign:
                    try installer.install(byName[step.name]!)
                    report.append(Step(name: step.name, action: Self.describe(step).action, detail: nil))
                case .relink:
                    try installer.linkMirrors(byName[step.name]!)
                    report.append(Step(name: step.name, action: Self.describe(step).action, detail: nil))
                case .remove:
                    try installer.uninstall(step.name)
                    report.append(Step(name: step.name, action: "removed", detail: nil))
                case let .skipModified(files):
                    report.append(Step(name: step.name, action: "skipped", detail: "edited in place: \(files.joined(separator: ", ")); use --force"))
                case let .failed(message):
                    failed = true
                    report.append(Step(name: step.name, action: "failed", detail: message))
                case .keep:
                    break
                }
            } catch {
                failed = true
                report.append(Step(name: step.name, action: "failed", detail: "\(error)"))
            }
        }

        if options.json {
            try printJSON(report)
        } else {
            ui.warning(report.compactMap { step in step.detail.map { "\(step.name): \($0)" } })
            let done = report.filter { !["skipped", "failed"].contains($0.action) }.count
            ui.success("Synced \(done) skill\(done == 1 ? "" : "s").")
        }
        if failed { throw ExitCode(1) }
    }

    static func describe(_ step: SyncStep) -> Step {
        switch step.action {
        case .install: return Step(name: step.name, action: "install", detail: nil)
        case .reinstall: return Step(name: step.name, action: "update", detail: nil)
        case .relink: return Step(name: step.name, action: "relink mirrors", detail: nil)
        case .replaceForeign: return Step(name: step.name, action: "replace other tool's copy", detail: nil)
        case .remove: return Step(name: step.name, action: "remove", detail: nil)
        case let .skipModified(files): return Step(name: step.name, action: "skip (edited in place)", detail: files.joined(separator: ", "))
        case let .failed(message): return Step(name: step.name, action: "error", detail: message)
        case .keep: return Step(name: step.name, action: "keep", detail: nil)
        }
    }
}

struct InstallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Copy skills at their pin into the hub and link the mirrors.",
        discussion: "Reinstalls even when up to date. Asks before replacing another tool's copy or an edited copy."
    )

    @OptionGroup var options: GlobalOptions

    @Argument(help: "Skills from skills.json to install.")
    var skills: [String]

    @Flag(name: .customLong("working-tree"), help: "Copy uncommitted first-party edits, for testing.")
    var workingTree = false

    @Flag(help: "Don't ask before replacing copies.")
    var yes = false

    func run() throws {
        let context = try Context(options)
        var installer = Installer(repo: context.repo, environment: context.environment)
        let targets = try select(skills, from: context.skills)
        let ui = NooraUI()

        let overwritten = targets.filter {
            switch installer.status(of: $0) {
            case .foreign, .modified: return true
            default: return false
            }
        }
        if !overwritten.isEmpty {
            let names = overwritten.map(\.name).joined(separator: ", ")
            guard try approve(ui, "Replace the current copies of \(names)? They go to backups.", yes: yes) else { throw ExitCode(1) }
        }

        var installed: [InstallState.Record] = []
        for skill in targets {
            installed.append(try installer.install(skill, workingTree: workingTree))
        }
        if options.json { return try printJSON(Dictionary(uniqueKeysWithValues: zip(skills, installed))) }
        ui.success("Installed \(targets.map(\.name).joined(separator: ", ")).")
    }
}

struct RemoveCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove",
        abstract: "Remove a skill from skills.json and uninstall it.",
        discussion: """
        The installed copy goes to backups. A third-party submodule no other skill uses is removed too \
        (staged, like the skills.json change); commit with `laiaskills commit`.
        """
    )

    @OptionGroup var options: GlobalOptions

    @Argument(help: "Skill to remove.")
    var skill: String

    @Flag(name: .customLong("keep-source"), help: "Keep the source submodule even if no skill uses it.")
    var keepSource = false

    @Flag(help: "Don't ask for confirmation.")
    var yes = false

    func run() throws {
        let context = try Context(options)
        guard let entry = context.repo.manifest.skills[skill] else { throw ValidationError("`\(skill)` is not in skills.json") }
        let ui = NooraUI()
        guard try approve(ui, "Remove \(skill) from skills.json and uninstall it?", yes: yes) else { throw ExitCode(1) }

        let dropped = try SourceEditor.removeSkill(skill, repo: context.repo, keepSource: keepSource)
        var installer = Installer(repo: context.repo, environment: context.environment)
        if installer.state.skills[skill] != nil { try installer.uninstall(skill) }
        try PendingChanges.record(PendingChange(kind: .remove, skills: [skill], source: dropped ?? entry.source),
                                  repo: context.repo.root)

        if options.json { return try printJSON(["skill": skill, "droppedSource": dropped ?? ""]) }
        ui.success("Removed \(skill)." + (dropped.map { " Also removed the unused submodule \($0)." } ?? "")
            + " Staged; commit with `laiaskills commit`.")
    }
}
