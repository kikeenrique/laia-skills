import ArgumentParser
import Foundation
import LaiaSkillsKit

struct BrowseCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "browse",
        abstract: "Look inside a source: its skills, their status and descriptions; preview and add them.",
        discussion: """
        SOURCE is a submodule path, owner/repo (owner/repo@skill opens that skill), or a git URL. A repo \
        that isn't a submodule yet is read from a throwaway clone under tmp/laiaskills-browse/, deleted \
        when browse exits. Without SOURCE, lists the sources to pick from. Adding goes through the same \
        steps as `add`: staged, then `laiaskills commit`.
        """
    )

    @OptionGroup var options: GlobalOptions

    @Argument(help: "Submodule path, owner/repo, owner/repo@skill, or a git URL.")
    var source: String?

    @Option(help: "Print this skill's SKILL.md and files instead of the list.")
    var skill: String?

    @Flag(help: "When adding a new source, download only the pinned snapshot (for large repos).")
    var shallow = false

    func run() async throws {
        let ui = NooraUI()
        let session = BrowseSession(options: options, ui: ui, shallow: shallow)
        if let source {
            try await session.run(source, focus: skill)
            return
        }

        let rows = SourcesCommand.rows(try Context(options))
        if options.json { return try printJSON(rows) }
        guard ui.isInteractive else {
            SourcesCommand.render(rows, ui: ui)
            return ui.info("Open one with `laiaskills browse <source>`.")
        }
        let picked = ui.pick("Sources in skills.json", options: rows.map(\.path), enter: "open")
        try await session.run(picked, focus: skill)
    }
}

struct FindCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "find",
        abstract: "Search skills.sh for skills, then browse a result.",
        discussion: """
        In a terminal, without a QUERY it asks for one, and after each preview it asks again (empty to \
        quit). Uses skills.sh's undocumented search API; this is the only command that calls an online catalog. \
        Results are in skills.sh's relevance order. Install counts are popularity, not a review: preview a \
        skill (and its scripts) before adding it.
        """
    )

    @OptionGroup var options: GlobalOptions

    @Argument(help: "What to search for. In a terminal, leave it out to be asked.")
    var query: [String] = []

    @Option(help: "Maximum number of results.")
    var limit = 20

    @Flag(help: "When adding a new source, download only the pinned snapshot (for large repos).")
    var shallow = false

    struct Row: Codable {
        let skill: String
        let source: String
        let installs: Int?
        let status: String
    }

    func run() async throws {
        let ui = NooraUI()
        let context = try Context(options)
        let given = query.joined(separator: " ")
        guard ui.isInteractive, !options.json else {
            guard !given.isEmpty else { throw ValidationError("Give something to search for (no terminal to ask in).") }
            let rows = try rows(for: given, context)
            if options.json { return try printJSON(rows) }
            guard !rows.isEmpty else { return ui.info("No skills found.") }
            ui.table(headers: ["Skill", "Source", "Installs", "Status"],
                     rows: rows.map { [$0.skill, $0.source, $0.installs.map(grouped) ?? "—", $0.status] })
            return ui.info("Look inside with `laiaskills browse owner/repo`, or `laiaskills add owner/repo@skill`.")
        }

        // Search, then pick results to browse; each browse comes back to the same results. "New search"
        // goes back to the search box, and an empty search ends it.
        var next = given
        var problem: String?
        while true {
            var phrase = next
            if phrase.isEmpty {
                ui.clearScreen()
                if let problem { ui.line(problem + "\n") }
                phrase = ui.ask(title: "Find skills on skills.sh", "Search",
                                description: "A skill name or topic, e.g. swiftui. Leave empty to quit.")
            }
            next = ""
            problem = nil
            guard !phrase.isEmpty else { return }
            let results: [CatalogResult]
            do {
                let (query, limit) = (phrase, limit)
                results = try await ui.progress("Searching skills.sh for \"\(query)\"") {
                    try Catalog.search(query, limit: limit)
                }
            } catch CatalogError.queryTooShort {
                problem = "Search for at least 2 characters."
                continue
            }
            guard !results.isEmpty else {
                problem = "No skills found for \"\(phrase)\"."
                continue
            }
            var context = context
            var notice: String?
            while true {
                let rows = rows(for: results, context)
                let labels = alignedColumns(rows.map { row in
                    [row.skill, row.source, row.installs.map { "\(grouped($0)) installs" } ?? "",
                     row.status == "—" ? "" : "[\(row.status)]"]
                }, rightAligned: [2])
                // First, so it's on screen however long the list is.
                let newSearch = "← New search"
                ui.clearScreen()
                if let notice { ui.line(notice + "\n") }
                notice = nil
                let picked = ui.pick("skills.sh results for \"\(phrase)\"", options: [newSearch] + labels, enter: "choose")
                guard let index = labels.firstIndex(of: picked) else { break }
                guard rows[index].status != Catalog.notARepo else {
                    notice = "\(rows[index].source) is a website, not a git repo; laiaskills only adds skills from git repos."
                    continue
                }
                let added = try await BrowseSession(options: options, ui: ui, shallow: shallow)
                    .run(rows[index].source, focus: rows[index].skill)
                if !added.isEmpty {
                    notice = "Added \(added.joined(separator: ", ")) from \(rows[index].source) and installed. "
                        + "Staged; commit with `laiaskills commit`."
                    // Statuses change once something is added.
                    context = try Context(options)
                }
            }
        }
    }

    private func rows(for phrase: String, _ context: Context) throws -> [Row] {
        rows(for: try Catalog.search(phrase, limit: limit), context)
    }

    private func rows(for results: [CatalogResult], _ context: Context) -> [Row] {
        results.map {
            Row(skill: $0.skillId, source: $0.source, installs: $0.installs,
                status: Catalog.status(of: $0, skills: context.repo.manifest.skills, submodules: context.submodules))
        }
    }
}

/// One `browse` of one source: resolve it (added submodule or preview clone), then list, preview, and add.
struct BrowseSession {
    let options: GlobalOptions
    let ui: UI
    let shallow: Bool

    /// What is being browsed.
    struct Target {
        /// How to add from it; nil when it can't be added from (e.g. a first-party `upstream/` pin).
        let spec: SourceSpec?
        /// The submodule path its skills are (or would be) listed under.
        let path: String
        let label: String
        let checkout: URL
        let version: String
        let preview: PreviewClone?
    }

    struct Report: Codable {
        let source: String
        let version: String
        let preview: Bool
        let skills: [BrowseRow]
    }

    struct Details: Codable {
        let source: String
        let skill: BrowseRow
        let text: String?
        let files: [SkillFile]
    }

    /// Returns the names of the skills added from the picker, if any.
    @discardableResult
    func run(_ argument: String, focus: String?) async throws -> [String] {
        let context = try Context(options)
        PreviewClone.cleanLeftovers(repo: context.repo.root)
        let (target, named) = try await resolve(argument, context)
        defer { target.preview?.remove() }

        let installer = Installer(repo: context.repo, environment: context.environment)
        let rows = Browser.rows(under: target.checkout, source: target.path, skills: context.skills,
                                installer: installer, inspector: context.inspector)
        guard !rows.isEmpty else { throw EditError.noSkills(target.label) }

        var focused: BrowseRow?
        if let wanted = focus ?? named {
            focused = rows.first { $0.name == wanted.lowercased() }
            if focused == nil, !ui.isInteractive || options.json {
                throw EditError.unknownSkillInSource(wanted, target.label, rows.map(\.name))
            }
            if focused == nil { ui.warning(["No skill `\(wanted)` in \(target.label); showing all of them."]) }
        }

        if options.json {
            if let focused {
                try printJSON(details(focused, target))
            } else {
                try printJSON(Report(source: target.label, version: target.version,
                                     preview: target.preview != nil, skills: rows))
            }
            return []
        }
        if let focused, !ui.isInteractive {
            try show(focused, target)
            return []
        }
        guard ui.isInteractive else {
            ui.line("\(target.label) \(target.version)")
            ui.table(headers: ["Skill", "Status", "Description", "Path"], rows: rows.map { row in
                [row.name, row.statusLabel, shorten(row.description ?? "—", to: 70),
                 row.path + (row.copies > 1 ? " (\(row.copies) copies)" : "")]
            })
            let addHint = target.spec.map { spec in
                let source = spec.url.hasPrefix("https://github.com/") ? "\(spec.owner)/\(spec.repository)" : spec.url
                return "; add with `laiaskills add \(source) --skill <name>`"
            } ?? ""
            ui.info("Preview one with `--skill <name>`\(addHint).")
            return []
        }
        return try loop(rows, target, focused: focused, context: context)
    }

    // MARK: Resolving the source

    /// Slow work behind a spinner, except with `--json`, whose output must stay plain JSON.
    private func slow<Value: Sendable>(_ message: String, _ work: @escaping @Sendable () throws -> Value) async throws -> Value {
        options.json ? try work() : try await ui.progress(message, work)
    }

    private func resolve(_ argument: String, _ context: Context) async throws -> (Target, String?) {
        let trimmed = argument.hasSuffix("/") ? String(argument.dropLast()) : argument
        if let submodule = context.submodules.first(where: { $0.path == trimmed }) {
            let spec = (try? SourceSpec(submodule.url)).flatMap { $0.submodulePath == submodule.path ? $0 : nil }
            return (try added(submodule, spec: spec, context), nil)
        }
        let typed = try SourceSpec(trimmed)
        if let submodule = context.submodules.first(where: { $0.path.lowercased() == typed.submodulePath.lowercased() }) {
            return (try added(submodule, spec: (try? SourceSpec(submodule.url)) ?? typed, context), typed.skill)
        }
        // Looking up the canonical name and cloning take a while: show a spinner.
        let added = Set(context.submodules.map { $0.path.lowercased() })
        let root = context.repo.root
        let (spec, clone) = try await slow("Downloading \(typed.owner)/\(typed.repository) to preview it") {
            let spec = Browser.canonical(typed)
            if added.contains(spec.submodulePath.lowercased()) { return (spec, nil as PreviewClone?) }
            return (spec, try PreviewClone.make(spec, repo: root))
        }
        guard let preview = clone else {
            let submodule = context.submodules.first { $0.path.lowercased() == spec.submodulePath.lowercased() }!
            return (try self.added(submodule, spec: spec, context), typed.skill)
        }
        let target = Target(spec: spec, path: spec.submodulePath, label: "\(spec.owner)/\(spec.repository)",
                            checkout: preview.folder, version: preview.versionLabel, preview: preview)
        return (target, typed.skill)
    }

    private func added(_ submodule: Submodule, spec: SourceSpec?, _ context: Context) throws -> Target {
        let checkout = context.repo.root.appendingPathComponent(submodule.path)
        guard FileManager.default.fileExists(atPath: checkout.appendingPathComponent(".git").path) else {
            throw ValidationError("`\(submodule.path)` is not checked out (git submodule update --init \(submodule.path)).")
        }
        let status = UpstreamChecker.statuses(of: [submodule], repo: context.repo.root, fetch: false).first
        return Target(spec: submodule.isFirstPartyUpstream ? nil : spec, path: submodule.path, label: submodule.path,
                      checkout: checkout, version: status?.pinnedLabel ?? "—", preview: nil)
    }

    // MARK: Showing a skill

    private func details(_ row: BrowseRow, _ target: Target) throws -> Details {
        let file = target.checkout.appendingPathComponent(row.path).appendingPathComponent("SKILL.md")
        return Details(source: target.label, skill: row, text: try? String(contentsOf: file, encoding: .utf8),
                       files: try Browser.files(of: row.path, in: target.checkout))
    }

    private func show(_ row: BrowseRow, _ target: Target) throws {
        let details = try details(row, target)
        ui.line("\n" + (details.text ?? "(no SKILL.md)"))
        ui.info("\(row.name): \(row.status == .available ? "available" : row.statusLabel), \(details.files.count) files at \(row.path)"
            + (row.copies > 1 ? " (one of \(row.copies) copies; add picks this one)" : ""))
        let audit = details.files.filter(\.needsAudit).map(\.path)
        if !audit.isEmpty { ui.warning(["Scripts to read before adding: \(audit.joined(separator: ", "))"]) }
    }

    // MARK: Interactive loop

    private func loop(_ rows: [BrowseRow], _ target: Target, focused: BrowseRow?, context: Context) throws -> [String] {
        let done = "Done"
        var marked: [String] = []
        var current = focused
        while true {
            if current == nil {
                let labels = alignedColumns(rows.map { row in
                    [(marked.contains(row.name) ? "✓ " : "  ") + row.name,
                     row.status == .available ? "" : "[\(row.statusLabel)]",
                     shorten(row.description ?? "", to: 60)]
                })
                ui.clearScreen()
                let picked = ui.pick("Skills in \(target.label) \(target.version)", options: labels + [done],
                                     enter: "preview")
                guard let index = labels.firstIndex(of: picked) else { break }
                current = rows[index]
            }
            guard let row = current else { break }
            current = nil
            let details = try details(row, target)
            ui.clearScreen()
            summarize(row, details, target)

            // Stay on this skill until the user moves on: reading or marking it comes back here.
            let read = "Read SKILL.md", others = "Other skills in \(target.label)"
            menu: while true {
                var actions = details.text == nil ? [] : [read]
                if target.spec != nil, row.status.canAdd {
                    actions.append(marked.contains(row.name) ? "Unmark" : "Mark to add")
                }
                actions += [others, done]
                switch ui.pick("What next with \(row.name)?", options: actions, enter: "choose") {
                case read: ui.page(target.checkout.appendingPathComponent(row.path).appendingPathComponent("SKILL.md"))
                case "Mark to add": marked.append(row.name)
                case "Unmark": marked.removeAll { $0 == row.name }
                case done: return try add(marked, target, context: context)
                default: break menu
                }
            }
        }
        return try add(marked, target, context: context)
    }

    /// The interactive preview: what the skill is and whether it can be added, without its full text.
    private func summarize(_ row: BrowseRow, _ details: Details, _ target: Target) {
        var facts = ["\(target.label) \(target.version)", row.status == .available ? "not added" : row.statusLabel]
        if row.copies > 1 { facts.append("one of \(row.copies) copies; add picks this one") }
        var body = [row.description ?? "(no description)"]
        let files = details.files.count == 1 ? "1 file" : "\(details.files.count) files"
        var notes = [row.path.isEmpty ? "\(files) at the repo root" : "\(files) in \(row.path)"]
        if target.spec == nil {
            notes.append("skills can't be added from \(target.label)")
        } else if row.status == .nameTaken {
            notes.append("can't be added: a managed skill from another source has this name")
        }
        body.append(notes.joined(separator: " · "))
        let audit = details.files.filter(\.needsAudit).map(\.path)
        ui.summary(title: row.name, subtitle: facts.joined(separator: " · "), body: body,
                   warning: audit.isEmpty ? nil : "Scripts to read before adding: \(audit.joined(separator: ", "))")
    }

    /// Adds the marked skills after a confirmation; returns the names added.
    private func add(_ names: [String], _ target: Target, context: Context) throws -> [String] {
        guard !names.isEmpty, let spec = target.spec else { return [] }
        guard ui.confirm("Add \(names.joined(separator: ", ")) from \(target.label)?", default: true) else { return [] }
        let tag = try Adder.addSource(spec, repo: context.repo.root, shallow: shallow)
        let available = Adder.skills(in: spec.submodulePath, repo: context.repo.root)
        let chosen = try names.map { name in
            guard let match = Adder.find(name, in: available) else {
                throw EditError.unknownSkillInSource(name, spec.submodulePath, available.map(\.name))
            }
            return match
        }
        let added = try addChosen(chosen, available: available, spec: spec, tag: tag, explicitPath: nil,
                                  install: true, options: options, repo: context.repo)
        ui.success("Added \(added.joined(separator: ", ")) from \(spec.submodulePath)" + (tag.map { " at \($0)" } ?? "")
            + " and installed. Staged; commit with `laiaskills commit`.")
        return added
    }
}

/// Cuts text to `length` characters on one line, with an ellipsis.
func shorten(_ text: String, to length: Int) -> String {
    let line = text.replacingOccurrences(of: "\n", with: " ")
    return line.count <= length ? line : String(line.prefix(length - 1)) + "…"
}
