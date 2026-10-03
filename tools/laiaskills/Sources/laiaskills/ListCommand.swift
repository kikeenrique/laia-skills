import ArgumentParser
import Foundation
import LaiaSkillsKit

struct ListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List skills in skills.json with their version and install state.",
        discussion: "The status column uses what was fetched last time; run `laiaskills check` to fetch."
    )

    @OptionGroup var options: GlobalOptions

    @Argument(help: "Only show skills whose name or source contains this text.")
    var filter: String?

    @Flag(help: "Also show skills in the hub that skills.json does not manage.")
    var all = false

    struct Row: Codable {
        let name: String
        let source: String
        let version: String
        let hub: String
        let mirrors: [String: String]
        let status: String
        let problem: String?
    }

    func run() throws {
        let context = try Context(options)
        let pinned = Dictionary(
            uniqueKeysWithValues: UpstreamChecker.statuses(
                of: context.submodules.filter { path in context.skills.contains { $0.submodulePath == path.path } },
                repo: context.repo.root,
                fetch: false
            ).map { ($0.path, $0) }
        )

        var rows = context.skills.map { skill -> Row in
            let status = skill.submodulePath.flatMap { pinned[$0] }
            let version = status?.pinnedLabel ?? skill.plugin.flatMap { context.pluginVersion($0) } ?? "—"
            return Row(
                name: skill.name,
                source: skill.entry.source,
                version: version,
                hub: context.inspector.hubState(skill.name).rawValue,
                mirrors: mirrorStates(skill.name, context),
                status: skill.problem != nil ? "error" : status.map(statusLabel) ?? "—",
                problem: skill.problem
            )
        }

        if all {
            let managed = Set(context.repo.manifest.skills.keys)
            for name in context.inspector.entries(in: context.inspector.hub) where !managed.contains(name) {
                rows.append(Row(name: name, source: "(not managed)", version: "—",
                                hub: context.inspector.hubState(name).rawValue,
                                mirrors: mirrorStates(name, context), status: "—", problem: nil))
            }
        }

        if let filter = filter?.lowercased() {
            rows = rows.filter { $0.name.lowercased().contains(filter) || $0.source.lowercased().contains(filter) }
        }

        if options.json { return try printJSON(rows) }

        let mirrorNames = context.inspector.mirrors.map(\.name)
        let ui = NooraUI()
        ui.table(
            headers: ["Skill", "Source", "Version", "Hub"] + mirrorNames + ["Status"],
            rows: rows.map { row in
                [row.name, row.source, row.version, row.hub] + mirrorNames.map { row.mirrors[$0] ?? "—" } + [row.status]
            }
        )
        ui.warning(rows.compactMap { row in row.problem.map { "\(row.name): \($0)" } })
    }

    private func mirrorStates(_ name: String, _ context: Context) -> [String: String] {
        Dictionary(uniqueKeysWithValues: context.inspector.mirrors.map {
            ($0.name, context.inspector.mirrorState(name, in: $0.url).rawValue)
        })
    }
}
