import ArgumentParser
import Foundation
import LaiaSkillsKit

struct AddCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Add skills from a third-party repo: submodule, skills.json entries, and install.",
        discussion: """
        SOURCE is owner/repo (GitHub), owner/repo@skill, or a git URL (e.g. Codeberg). The submodule goes \
        to third-party/<owner>__<repo>, pinned to its newest release tag when it has one. Everything is \
        staged; commit with `laiaskills commit`.
        """
    )

    @OptionGroup var options: GlobalOptions

    @Argument(help: "owner/repo, owner/repo@skill, or a git URL.")
    var source: String

    @Option(name: .customLong("skill"), help: "Skill to add (repeatable). Without it, choose interactively.")
    var skills: [String] = []

    @Flag(help: "Download only the pinned snapshot (for large repos).")
    var shallow = false

    @Flag(name: .customLong("no-install"), help: "Only update skills.json; don't install.")
    var noInstall = false

    func run() throws {
        let spec = try SourceSpec(source)
        let repo = try options.repository()
        let ui = NooraUI()

        let tag = try Adder.addSource(spec, repo: repo.root, shallow: shallow)
        let available = Adder.skills(in: spec.submodulePath, repo: repo.root)
        guard !available.isEmpty else { throw EditError.noSkills(spec.submodulePath) }

        let requested = skills + (spec.skill.map { [$0] } ?? [])
        let chosen: [(name: String, path: String)]
        if !requested.isEmpty {
            chosen = try requested.map { name in
                guard let match = available.first(where: { $0.name == name }) else {
                    throw EditError.unknownSkillInSource(name, spec.submodulePath, available.map(\.name))
                }
                return match
            }
        } else if ui.isInteractive {
            let labels = available.map { "\($0.name)  (\($0.path))" }
            let picked = ui.choose("Which skills from \(spec.owner)/\(spec.repository)?", options: labels)
            chosen = picked.compactMap { label in labels.firstIndex(of: label).map { available[$0] } }
        } else {
            throw ValidationError("Pass --skill. Available: \(available.map(\.name).joined(separator: ", "))")
        }
        guard !chosen.isEmpty else { throw ValidationError("No skills chosen.") }

        try SourceEditor.addSkills(Adder.entries(for: chosen, all: available, source: spec.submodulePath), repo: repo)
        try PendingChanges.record(PendingChange(kind: .add, skills: chosen.map(\.name), source: spec.submodulePath, to: tag),
                                  repo: repo.root)

        if !noInstall {
            let context = try Context(options)
            var installer = Installer(repo: context.repo, environment: context.environment)
            for skill in try select(chosen.map(\.name), from: context.skills) {
                try installer.install(skill)
            }
        }

        if options.json {
            return try printJSON(["source": spec.submodulePath, "tag": tag ?? "", "skills": chosen.map(\.name).joined(separator: ",")])
        }
        ui.success("Added \(chosen.map(\.name).joined(separator: ", ")) from \(spec.submodulePath)"
            + (tag.map { " at \($0)" } ?? "") + (noInstall ? "" : " and installed")
            + ". Staged; commit with `laiaskills commit`.")
    }
}

struct SourcesCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sources",
        abstract: "List pinned sources: version, branch, and how many of their skills are used.",
        discussion: "Uses what was fetched last time; run `laiaskills check` to fetch."
    )

    @OptionGroup var options: GlobalOptions

    struct Row: Codable {
        let path: String
        let kind: String
        let pinned: String
        let branch: String
        let shallow: Bool
        let skillsUsed: Int
        let skillsAvailable: Int
    }

    func run() throws {
        let context = try Context(options)
        let statuses = Dictionary(uniqueKeysWithValues: UpstreamChecker.statuses(
            of: context.submodules, repo: context.repo.root, fetch: false
        ).map { ($0.path, $0) })
        let rows = context.submodules.map { submodule -> Row in
            let used = context.repo.manifest.skills.values.filter { $0.source == submodule.path }.count
            let status = statuses[submodule.path]
            let pinned = status?.note == "not checked out" ? "not checked out" : status?.pinnedLabel ?? "—"
            return Row(
                path: submodule.path,
                kind: submodule.isFirstPartyUpstream ? "first-party upstream" : "third-party",
                pinned: pinned,
                branch: submodule.branch ?? "default",
                shallow: submodule.shallow,
                skillsUsed: used,
                skillsAvailable: Adder.skills(in: submodule.path, repo: context.repo.root).count
            )
        }.sorted { ($0.kind, $0.path) < ($1.kind, $1.path) }

        if options.json { return try printJSON(rows) }
        NooraUI().table(
            headers: ["Source", "Kind", "Pinned", "Branch", "Shallow", "Skills used"],
            rows: rows.map { [$0.path, $0.kind, $0.pinned, $0.branch, $0.shallow ? "yes" : "no",
                              $0.pinned == "not checked out" ? "—" : "\($0.skillsUsed) of \($0.skillsAvailable)"] }
        )
    }
}

struct ShowCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Show a skill's source, version, install locations, and SKILL.md."
    )

    @OptionGroup var options: GlobalOptions

    @Argument(help: "Skill from skills.json.")
    var skill: String

    @Flag(help: "Reveal the installed copy (or the source folder) in the file manager.")
    var open = false

    struct Details: Codable {
        let name: String
        let description: String?
        let source: String
        let sourceFolder: String?
        let version: String?
        let status: String
        let hub: String
        let mirrors: [String: String]
    }

    func run() throws {
        let context = try Context(options)
        guard let resolved = try select([skill], from: context.skills).first else { return }
        let installer = Installer(repo: context.repo, environment: context.environment)
        let hubFolder = installer.hub.appendingPathComponent(skill)
        let installed = FileManager.default.fileExists(atPath: hubFolder.path)
        let skillFile = (installed ? hubFolder : resolved.folder)?.appendingPathComponent("SKILL.md")
        let text = skillFile.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        let pin = try? Pins.pin(for: resolved, repo: context.repo.root)

        let details = Details(
            name: skill,
            description: text.flatMap { SkillDiscovery.frontmatterValue("description", in: $0) },
            source: resolved.entry.source,
            sourceFolder: resolved.folder.map { relativePath(of: $0, to: context.repo.root) },
            version: pin.map { $0.tag ?? String($0.commit.prefix(7)) },
            status: installer.status(of: resolved).label,
            hub: hubFolder.path,
            mirrors: Dictionary(uniqueKeysWithValues: context.inspector.mirrors.map {
                ($0.name, "\($0.url.appendingPathComponent(skill).path) (\(context.inspector.mirrorState(skill, in: $0.url).rawValue))")
            })
        )

        if open {
            let folder = installed ? hubFolder : resolved.folder
            if let folder { try reveal(folder) }
        }
        if options.json { return try printJSON(details) }

        let ui = NooraUI()
        let source = details.source + (details.sourceFolder.map { " → \($0)" } ?? "")
        var rows: [[String]] = [
            ["Name", details.name],
            ["Description", details.description ?? "—"],
            ["Source", source],
            ["Version", details.version ?? "—"],
            ["Status", details.status],
            ["Hub", details.hub],
        ]
        for mirror in details.mirrors.keys.sorted() {
            rows.append(["Mirror \(mirror)", details.mirrors[mirror] ?? "—"])
        }
        ui.table(headers: ["Field", "Value"], rows: rows)
        if let text { ui.line("\n" + text) }
    }

    private func reveal(_ folder: URL) throws {
        #if os(macOS)
        let command = ["open", "-R", folder.path]
        #else
        let command = ["xdg-open", folder.path]
        #endif
        let result = try Shell.run(command)
        if !result.succeeded { throw ValidationError("Could not open \(folder.path): \(result.stderr)") }
    }
}
