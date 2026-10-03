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

        if options.json {
            try printJSON(Report(sources: statuses, installs: drifted))
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

    struct Report: Codable {
        let sources: [SourceStatus]
        let installs: [Drift]
    }
}
