import ArgumentParser
import Foundation
import LaiaSkillsKit

struct UpgradeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "upgrade",
        abstract: "Move source pins to newer releases (or commits), reinstall, and re-check first-party skills.",
        discussion: """
        TARGETS are skill names or submodule paths; with none, every outdated source is upgraded. Pinned \
        releases move to the newest release; untagged pins to the branch head. When a first-party plugin's \
        upstream/ pin moves, an AI agent (tools/config/recheck.json) re-checks the skill; only files under \
        first-party/<plugin>/skills/ may change, and the skill validator must pass. Changes are staged; \
        commit with `laiaskills commit` or --commit. Nothing is ever pushed.
        """
    )

    @OptionGroup var options: GlobalOptions

    @Argument(help: "Skill names or submodule paths. Default: all outdated sources.")
    var targets: [String] = []

    @Option(help: "Move to this tag or commit instead of the newest release (needs exactly one target).")
    var to: String?

    @Flag(help: "Don't ask for confirmation.")
    var yes = false

    @Flag(help: "Commit right after upgrading (see `laiaskills commit`).")
    var commit = false

    @Flag(name: .customLong("no-agent"), help: "Skip the automated re-check of first-party skills.")
    var noAgent = false

    func run() throws {
        if to != nil, targets.count != 1 { throw ValidationError("--to needs exactly one target.") }
        let context = try Context(options)
        let ui = NooraUI()
        let sources = targets.isEmpty
            ? context.submodules
            : try Upgrader.sources(for: targets, repo: context.repo, submodules: context.submodules, skills: context.skills)

        let plans = try sources.compactMap { try Upgrader.plan(source: $0, repo: context.repo, skills: context.skills, to: to) }
        guard !plans.isEmpty else { return ui.success("Everything is up to date.") }

        for plan in plans {
            ui.info("\(plan.source.path): \(plan.fromLabel) → \(plan.toLabel)"
                + (plan.skills.isEmpty ? "" : "  (skills: \(plan.skills.joined(separator: ", ")))"))
            if !plan.log.isEmpty { ui.line(plan.log.prefix(15).map { "    \($0)" }.joined(separator: "\n")) }
            if let diff = plan.diffSummary { ui.line("    \(diff)") }
        }
        guard try approve(ui, "Upgrade \(plans.count) source\(plans.count == 1 ? "" : "s")?", yes: yes) else { throw ExitCode(1) }

        var problems: [String] = []
        var conflicted: [String] = []
        for plan in plans {
            try Upgrader.apply(plan, repo: context.repo.root)

            // Re-test local patches on the new version, then reinstall skills whose files come from this pin.
            let refreshed = try Context(options)
            var installer = Installer(repo: refreshed.repo, environment: refreshed.environment)
            var dropped: [String] = []
            for skill in refreshed.skills where plan.skills.contains(skill.name) {
                if let problem = skill.problem {
                    problems.append("\(skill.name): \(problem) — fix skills.json before committing")
                    continue
                }
                let review = try Patches.review(skill, repo: refreshed.repo.root, scratch: installer.hub)
                dropped += review.dropped
                for path in review.dropped { ui.info("\(skill.name): dropped \(path); \(plan.toLabel) already contains it.") }
                if !review.conflicts.isEmpty {
                    conflicted.append(skill.name)
                    problems += review.conflicts.map { "\(skill.name): patch no longer applies — \($0)" }
                    continue
                }
                try installer.install(skill)
            }

            var recheck: PendingChange.Recheck?
            if plan.plugin != nil {
                if noAgent {
                    recheck = .skipped
                } else {
                    let config = try RecheckConfig.load(repo: context.repo.root)
                    ui.info("Re-checking \(plan.plugin!) against \(plan.upstreamName) \(plan.toLabel) with \(config.agent)…")
                    let result = try Rechecker.run(plan: plan, repo: context.repo.root, config: config)
                    recheck = result.outcome
                    if !result.reverted.isEmpty {
                        problems.append("put back changes outside the skill: \(result.reverted.joined(separator: ", "))")
                    }
                    ui.info(result.changed.isEmpty ? "No skill changes needed." : "Updated \(result.changed.count) skill files (staged).")
                }
            }
            try PendingChanges.record(
                PendingChange(kind: .upgrade, skills: plan.skills, source: plan.source.path, from: plan.fromLabel,
                              to: plan.toLabel, plugin: plan.plugin, recheck: recheck,
                              droppedPatches: dropped.isEmpty ? nil : dropped),
                repo: context.repo.root
            )
        }
        ui.warning(problems)
        if !conflicted.isEmpty {
            throw CommandError("""
                Stopped: patches for \(conflicted.joined(separator: ", ")) no longer apply. The new pin is staged and \
                those skills keep their old copies. Update or delete the patches under \(Patches.folder)/, run \
                `laiaskills sync`, then `laiaskills commit`.
                """)
        }

        if commit || (!yes && ui.isInteractive && ui.confirm("Commit now?", default: false)) {
            try CommitCommand.commitPending(options: options, ui: ui, yes: yes, bump: nil)
        } else {
            ui.success("Upgraded and staged. Review with `git diff --cached`, then run `laiaskills commit`.")
        }
    }
}

struct CommitCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "commit",
        abstract: "Commit staged laiaskills changes with generated Conventional Commit messages.",
        discussion: """
        skills.json additions and removals go in one commit, third-party bumps in another, and each \
        first-party plugin whose upstream moved in its own docs(<plugin>) commit with its version bumped. \
        Only the paths involved are committed. Never pushes.
        """
    )

    @OptionGroup var options: GlobalOptions

    @Flag(help: "Don't ask for confirmation.")
    var yes = false

    @Option(help: "Plugin version bump for re-pinned first-party plugins: patch, minor, or major. Default: ask, or patch with --yes.")
    var bump: String?

    func run() throws {
        let level = try bump.map { value -> VersionBump in
            guard let level = VersionBump(rawValue: value) else { throw ValidationError("--bump must be patch, minor, or major.") }
            return level
        }
        try Self.commitPending(options: options, ui: NooraUI(), yes: yes, bump: level)
    }

    static func commitPending(options: GlobalOptions, ui: UI, yes: Bool, bump: VersionBump?) throws {
        let repo = try options.repository()
        let pending = PendingChanges.load(repo: repo.root)
        let names = Dictionary(uniqueKeysWithValues: try Submodules.load(repo: repo.root).map { submodule in
            let last = submodule.url.split(separator: "/").last.map(String.init) ?? submodule.path
            return (submodule.path, last.hasSuffix(".git") ? String(last.dropLast(4)) : last)
        })
        let groups = Committer.plan(pending, upstreamNames: names)
        guard !groups.isEmpty else { throw CommitError.nothingPending }

        for group in groups { ui.line("\(group.subject)\n\(group.body.split(separator: "\n").map { "    \($0)" }.joined(separator: "\n"))\n") }
        guard try approve(ui, "Make \(groups.count) commit\(groups.count == 1 ? "" : "s")?", yes: yes) else { throw ExitCode(1) }

        var remaining = pending
        var made: [String] = []
        for group in groups {
            if let plugin = group.plugin {
                let level = bump ?? (yes || !ui.isInteractive ? .patch : chooseBump(ui, plugin: plugin))
                let (old, new) = try Committer.bumpVersion(plugin: plugin, bump: level, repo: repo.root)
                ui.info("\(plugin): version \(old) → \(new)")
            }
            made.append("\(try Committer.commit(group, repo: repo.root)) \(group.subject)")
            remaining.changes.removeAll { group.changes.contains($0) }
            try remaining.save(repo: repo.root)

            // First-party content installs from HEAD, so refresh it now that it's committed.
            let context = try Context(options)
            var installer = Installer(repo: context.repo, environment: context.environment)
            let refresh = context.skills.filter {
                group.skillsToSync.contains($0.name) || (group.plugin != nil && $0.plugin == group.plugin)
            }
            for skill in refresh {
                if case .notSynced = installer.status(of: skill) { try installer.install(skill) }
            }
        }
        if options.json { return try printJSON(made) }
        ui.success("Committed (not pushed):\n" + made.joined(separator: "\n"))
    }

    static func chooseBump(_ ui: UI, plugin: String) -> VersionBump {
        let picked = ui.choose("Version bump for \(plugin) (pick one; patch if none):", options: VersionBump.allCases.map(\.rawValue))
        return picked.first.flatMap(VersionBump.init(rawValue:)) ?? .patch
    }
}

struct ImportCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "import",
        abstract: "Plan (and optionally apply) moving skills installed by other tools under laiaskills.",
        discussion: """
        Reads ~/.agents/.skill-lock.json. Without --apply, only prints the plan. With --apply, adds each \
        third-party source as a submodule with its skills (staged, not installed); then run \
        `laiaskills sync` and `laiaskills commit`.

        After the sync, --prune removes the lock entries of skills laiaskills now installs, and of skills \
        that are no longer installed, so other tools stop updating them. The lock file is backed up first.
        """
    )

    @OptionGroup var options: GlobalOptions

    @Flag(help: "Add the planned sources and skills.")
    var apply = false

    @Option(name: .customLong("shallow"), help: "owner/repo to add as a shallow submodule (repeatable).")
    var shallowSources: [String] = []

    @Flag(help: "Remove lock entries for skills laiaskills installed, or that are no longer installed.")
    var prune = false

    @Flag(help: "With --prune: don't ask for confirmation.")
    var yes = false

    func validate() throws {
        if prune && apply { throw ValidationError("Use --apply and --prune in separate runs: sync in between.") }
    }

    func run() throws {
        let context = try Context(options)
        if prune { return try runPrune(context) }
        let items = Importer.plan(environment: context.environment, repo: context.repo)
        let ui = NooraUI()

        // Group third-party skills by source, treating owner/repo case-insensitively.
        var groups: [String: (source: String, skills: [String])] = [:]
        for item in items where item.disposition == .thirdParty {
            let key = item.source!.lowercased()
            groups[key, default: (item.source!, [])].skills.append(item.name)
        }

        if !apply {
            if options.json { return try printJSON(items) }
            ui.table(headers: ["Skill", "Plan", "Source", "Note"],
                     rows: items.map { [$0.name, $0.disposition.rawValue, $0.source ?? "—", $0.note ?? ""] })
            return ui.info("\(groups.count) third-party sources to add. Re-run with --apply (and --shallow owner/repo for large ones).")
        }

        let shallow = Set(shallowSources.map { $0.lowercased() })
        for key in groups.keys.sorted() {
            let group = groups[key]!
            let spec = try SourceSpec(group.source)
            ui.info("Adding \(group.source)…")
            let tag = try Adder.addSource(spec, repo: context.repo.root, shallow: shallow.contains(key))
            let available = Adder.skills(in: spec.submodulePath, repo: context.repo.root)
            let chosen = group.skills.compactMap { name in Adder.find(name, in: available) }
            let missing = Set(group.skills).subtracting(chosen.map { $0.name.lowercased() })
            if !missing.isEmpty { ui.warning(["\(group.source): not found upstream: \(missing.sorted().joined(separator: ", "))"]) }
            guard !chosen.isEmpty else { continue }
            let repo = try options.repository()
            try SourceEditor.addSkills(Adder.entries(for: chosen, all: available, source: spec.submodulePath), repo: repo)
            try PendingChanges.record(PendingChange(kind: .add, skills: chosen.map { $0.name.lowercased() },
                                                    source: spec.submodulePath, to: tag),
                                      repo: repo.root)
        }
        ui.success("Imported. Next: `laiaskills sync` to install, then `laiaskills commit`.")
    }

    private func runPrune(_ context: Context) throws {
        let items = LockPruner.plan(repo: context.repo, inspector: context.inspector, environment: context.environment)
        let ui = NooraUI()
        guard !items.isEmpty else {
            if options.json { return try printJSON([PruneItem]()) }
            return ui.success("Nothing to prune in \(context.environment.skillsCLILock.path).")
        }
        if !options.json {
            ui.table(headers: ["Skill", "Reason"], rows: items.map { [$0.name, $0.reason.rawValue] })
        }
        guard try approve(ui, "Remove these \(items.count) entries from .skill-lock.json? It is backed up first.", yes: yes) else {
            throw ExitCode(1)
        }
        let backup = try LockPruner.apply(items.map(\.name), environment: context.environment)
        if options.json { return try printJSON(items) }
        ui.success("Pruned \(items.count) entries. Backup: \(backup.path)")
    }
}
