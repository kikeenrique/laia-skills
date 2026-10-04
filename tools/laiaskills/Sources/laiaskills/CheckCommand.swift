import ArgumentParser
import Foundation
import LaiaSkillsKit

struct CheckCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "check",
        abstract: "Fetch every pinned source and report newer releases or commits.",
        discussion: """
        Covers third-party skill sources and the upstream/ pins of first-party plugins. Sources pinned to a \
        release tag are compared with the newest release; untagged ones with their tracked branch.
        """
    )

    @OptionGroup var options: GlobalOptions

    @Flag(help: "Don't fetch; compare with what was fetched last time.")
    var offline = false

    @Flag(name: .customLong("exit-code"), help: "Exit with status 1 when anything is outdated.")
    var exitCode = false

    func run() throws {
        let context = try Context(options)
        let statuses = UpstreamChecker.statuses(of: context.submodules, repo: context.repo.root, fetch: !offline)
            .sorted { ($0.kind, $0.path) < ($1.kind, $1.path) }

        // Installed copies that lag behind their pin or were edited in place (offline check).
        let installer = Installer(repo: context.repo, environment: context.environment)
        let drifted: [Drift] = context.skills.compactMap { skill in
            switch installer.status(of: skill) {
            case .notSynced: return Drift(skill: skill.name, state: "not synced", fix: "laiaskills sync")
            case let .modified(files):
                return Drift(skill: skill.name, state: "modified: \(files.joined(separator: ", "))", fix: "laiaskills sync --force")
            default: return nil
            }
        }

        let patchNotes = patchOutlook(statuses, context: context, scratch: installer.hub)

        if options.json {
            try printJSON(Report(sources: statuses, installs: drifted, patches: patchNotes))
        } else {
            let ui = NooraUI()
            ui.table(
                headers: ["Source", "Kind", "Pinned", "Latest", "Status"],
                rows: statuses.map { [$0.path, $0.kind, $0.pinnedLabel, $0.latest ?? "—", statusLabel($0)] }
            )
            ui.warning(statuses.compactMap { status in status.note.map { "\(status.path): \($0)" } })
            let outdated = statuses.filter { $0.state == .outdated }.count
            if outdated == 0 {
                ui.success("All \(statuses.count) sources are up to date.")
            } else {
                ui.info(outdated == 1
                    ? "1 of \(statuses.count) sources has a newer upstream version."
                    : "\(outdated) of \(statuses.count) sources have newer upstream versions.")
            }
            if !drifted.isEmpty {
                ui.table(headers: ["Installed skill", "State", "Fix"], rows: drifted.map { [$0.skill, $0.state, $0.fix] })
            }
            if !patchNotes.isEmpty {
                ui.table(headers: ["Patched skill", "Patch", "On the newest version"],
                         rows: patchNotes.map { [$0.skill, $0.patch, $0.outlook] })
            }
        }

        if exitCode, statuses.contains(where: { $0.state == .outdated }) || !drifted.isEmpty {
            throw ExitCode(1)
        }
    }

    struct Drift: Codable {
        let skill: String
        let state: String
        let fix: String
    }

    struct PatchNote: Codable {
        let skill: String
        let patch: String
        let outlook: String
    }

    struct Report: Codable {
        let sources: [SourceStatus]
        let installs: [Drift]
        let patches: [PatchNote]
    }

    /// How each patch of a skill from an outdated source would fare on the newest version, when that
    /// version is available locally (shallow sources only list it remotely). Patches that still apply
    /// are not listed.
    private func patchOutlook(_ statuses: [SourceStatus], context: Context, scratch: URL) -> [PatchNote] {
        var notes: [PatchNote] = []
        for status in statuses where status.state == .outdated {
            let patched = context.skills.filter {
                $0.submodulePath == status.path && !Patches.list(for: $0.name, repo: context.repo.root).isEmpty
            }
            guard !patched.isEmpty, let latest = status.latest else { continue }
            let git = Git(context.repo.root.appendingPathComponent(status.path))
            let commit = git.attempt("rev-parse", "--verify", "--quiet", "\(latest)^{commit}")
                ?? git.attempt("rev-parse", "--verify", "--quiet", "origin/\(latest)^{commit}")
            for skill in patched {
                let patches = Patches.list(for: skill.name, repo: context.repo.root)
                guard let commit, let pin = try? Pins.pin(for: skill, repo: context.repo.root),
                      let fits = try? Patches.fit(patches, gitDirectory: pin.gitDirectory, commit: commit,
                                                  path: pin.path, scratch: scratch) else {
                    notes += patches.map { PatchNote(skill: skill.name, patch: $0.name, outlook: "not checked: \(latest) not fetched") }
                    continue
                }
                for (patch, fit) in fits {
                    switch fit {
                    case .applies: break
                    case .alreadyApplied: notes.append(PatchNote(skill: skill.name, patch: patch.name, outlook: "already in \(latest); upgrade drops it"))
                    case let .conflicts(detail): notes.append(PatchNote(skill: skill.name, patch: patch.name, outlook: "conflicts: \(detail)"))
                    }
                }
            }
        }
        return notes
    }
}
