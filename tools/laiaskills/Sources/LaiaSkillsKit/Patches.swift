import Foundation

/// A local fix to a pinned skill, kept in the repo at `patches/<skill>/NNNN-<slug>.patch` and applied to
/// the installed copy (never to the submodule). Paths in the diff are relative to the skill folder,
/// with `a/` and `b/` prefixes; text before the first `diff --git` line is a header git ignores.
public struct SkillPatch: Sendable, Equatable {
    /// File name, e.g. `0001-avoid-eval-on-user-input.patch`.
    public let name: String
    public let url: URL
    /// The `Reason:` header line, if any.
    public let reason: String?
}

/// How a patch fits a version of its skill.
public enum PatchFit: Sendable, Equatable {
    case applies
    /// The change is already there: fixed upstream.
    case alreadyApplied
    case conflicts(String)
}

public enum PatchError: Error, CustomStringConvertible {
    case firstParty(String)
    case notInstalled(String)
    case noEdits(String)
    case doesNotApply(String, String)

    public var description: String {
        switch self {
        case let .firstParty(name): return "\(name) is a first-party skill; edit it directly instead of patching it"
        case let .notInstalled(name): return "\(name) is not installed by laiaskills; run `laiaskills sync` first"
        case let .noEdits(name): return "the installed copy of \(name) has no edits to save as a patch"
        case let .doesNotApply(patch, detail): return "patch \(patch) does not apply: \(detail)"
        }
    }
}

public enum Patches {
    public static let folder = "patches"

    /// `patches/<skill>` relative to the repo root.
    public static func path(for skill: String) -> String { "\(folder)/\(skill)" }

    /// The skill's patches in the order they apply (by file name).
    public static func list(for skill: String, repo: URL) -> [SkillPatch] {
        let directory = repo.appendingPathComponent(path(for: skill))
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { $0.hasSuffix(".patch") }.sorted()
        return names.map { name in
            let url = directory.appendingPathComponent(name)
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            return SkillPatch(name: name, url: url, reason: header("Reason", in: text))
        }
    }

    /// Skills that have a patches folder, whether or not they are still in skills.json.
    public static func patchedSkills(repo: URL) -> [String] {
        let root = repo.appendingPathComponent(folder)
        return ((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? [])
            .filter { !$0.hasPrefix(".") && !list(for: $0, repo: repo).isEmpty }.sorted()
    }

    /// Patch file name → git blob id, recorded at install time so a changed patch set re-syncs.
    public static func fingerprint(_ patches: [SkillPatch]) throws -> [String: String] {
        guard let first = patches.first else { return [:] }
        let git = Git(first.url.deletingLastPathComponent())
        let ids = try git.run(["hash-object", "--no-filters", "--"] + patches.map(\.url.path)).split(separator: "\n")
        return Dictionary(uniqueKeysWithValues: zip(patches.map(\.name), ids.map(String.init)))
    }

    /// Applies the patches in order to a skill folder; stops at the first one that does not apply.
    public static func apply(_ patches: [SkillPatch], to folder: URL) throws {
        for patch in patches {
            let result = try gitApply(patch, in: folder, extra: [])
            guard result.succeeded else { throw PatchError.doesNotApply(patch.name, firstLine(result.stderr)) }
        }
    }

    /// How each patch fits the skill at `commit`, applying the ones that fit so later patches are tested
    /// on top of them. Works on a scratch export under `scratch`, which is removed afterwards.
    public static func fit(_ patches: [SkillPatch], gitDirectory: URL, commit: String, path: String,
                           scratch: URL) throws -> [(patch: SkillPatch, fit: PatchFit)] {
        let folder = scratch.appendingPathComponent(".laiaskills-patch-check-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = try Exporter.export(Pin(gitDirectory: gitDirectory, commit: commit, path: path, tree: "", tag: nil), to: folder)

        return try patches.map { patch in
            if try gitApply(patch, in: folder, extra: ["--check"]).succeeded {
                _ = try gitApply(patch, in: folder, extra: [])
                return (patch, .applies)
            }
            if try gitApply(patch, in: folder, extra: ["--check", "--reverse"]).succeeded {
                return (patch, .alreadyApplied)
            }
            return (patch, .conflicts(firstLine(try gitApply(patch, in: folder, extra: ["--check"]).stderr)))
        }
    }

    /// What happened to a skill's patches after its pin moved.
    public struct Review: Sendable, Equatable {
        /// Repo-relative paths of patches removed (staged) because the pin already contains them.
        public var dropped: [String] = []
        /// `<patch>: <git apply error>` for patches that no longer apply.
        public var conflicts: [String] = []
    }

    /// Tests the skill's patches against its current pin (after an upgrade moved it). Patches the new
    /// version already contains are deleted and the deletion staged; conflicts are only reported.
    public static func review(_ skill: ResolvedSkill, repo: URL, scratch: URL) throws -> Review {
        let patches = list(for: skill.name, repo: repo)
        guard !patches.isEmpty else { return Review() }
        let pin = try Pins.pin(for: skill, repo: repo)
        var review = Review()
        for (patch, fit) in try fit(patches, gitDirectory: pin.gitDirectory, commit: pin.commit, path: pin.path, scratch: scratch) {
            let path = "\(path(for: skill.name))/\(patch.name)"
            switch fit {
            case .applies: break
            case .alreadyApplied:
                // Forced: the patch may be staged but not committed yet; its change is upstream either way.
                try Git(repo).run("rm", "--quiet", "--force", "--ignore-unmatch", "--", path)
                try? FileManager.default.removeItem(at: patch.url)
                review.dropped.append(path)
            case let .conflicts(detail):
                review.conflicts.append("\(patch.name): \(detail)")
            }
        }
        return review
    }

    /// Saves a new patch for an installed third-party skill: the diff between its installed copy (edited in
    /// place) and the pin with the existing patches, or the contents of `file`, which must apply on top of
    /// them. Returns the new patch file; staging and reinstalling are up to the caller.
    public static func save(skill: ResolvedSkill, reason: String, from file: URL?, repo: Repository,
                            hub: URL, date: String) throws -> URL {
        guard skill.entry.source != SkillEntry.firstParty else { throw PatchError.firstParty(skill.name) }
        let parent = hub.appendingPathComponent(".laiaskills-patch-\(skill.name)-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: parent) }
        let original = parent.appendingPathComponent("a")
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)
        _ = try Exporter.export(try Pins.pin(for: skill, repo: repo.root), to: original)
        try apply(list(for: skill.name, repo: repo.root), to: original)

        let body: String
        if let file {
            let candidate = SkillPatch(name: file.lastPathComponent, url: file, reason: nil)
            let check = try gitApply(candidate, in: original, extra: ["--check"])
            guard check.succeeded else { throw PatchError.doesNotApply(file.lastPathComponent, firstLine(check.stderr)) }
            body = try String(contentsOf: file, encoding: .utf8)
        } else {
            let installed = hub.appendingPathComponent(skill.name)
            guard FileManager.default.fileExists(atPath: installed.path) else { throw PatchError.notInstalled(skill.name) }
            try FileManager.default.copyItem(at: installed, to: parent.appendingPathComponent("b"))
            guard let changes = try diff(in: parent) else { throw PatchError.noEdits(skill.name) }
            body = changes
        }
        return try write(body: body, reason: reason, skill: skill.name, repo: repo.root, date: date)
    }

    /// Diff of `edited` against `original` as a patch body with `a/` and `b/` paths relative to the skill
    /// folder; nil when they are the same. Both folders must be siblings named `a` and `b`.
    static func diff(in parent: URL) throws -> String? {
        // The folder names are the prefixes: `--no-prefix` keeps git from adding its own on top.
        let result = try Shell.run(["git", "diff", "--no-index", "--no-prefix", "--no-color", "--binary", "--", "a", "b"],
                                   in: parent)
        switch result.status {
        case 0: return nil
        case 1: return result.stdout
        default: throw ShellError.failed(command: "git diff --no-index", status: result.status, stderr: result.stderr)
        }
    }

    /// Writes a new patch after the existing ones, e.g. `0002-avoid-eval.patch`. Returns its URL.
    public static func write(body: String, reason: String, skill: String, repo: URL, date: String) throws -> URL {
        let directory = repo.appendingPathComponent(path(for: skill))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let number = (list(for: skill, repo: repo).compactMap { Int($0.name.prefix(4)) }.max() ?? 0) + 1
        let padded = String(repeating: "0", count: max(0, 4 - String(number).count)) + String(number)
        let url = directory.appendingPathComponent("\(padded)-\(slug(reason)).patch")
        let text = "Reason: \(reason)\nDate: \(date)\n\n" + body
        try Data(text.utf8).write(to: url, options: .atomic)
        return url
    }

    /// `avoid eval on user input (audit 2026-06)` → `avoid-eval-on-user-input-audit-2026-06`.
    static func slug(_ text: String) -> String {
        let words = text.lowercased().split { !($0.isLetter || $0.isNumber) || !$0.isASCII }
        var slug = ""
        for word in words {
            guard slug.count + word.count < 48 else { break }
            slug += (slug.isEmpty ? "" : "-") + word
        }
        return slug.isEmpty ? "patch" : slug
    }

    static func header(_ key: String, in text: String) -> String? {
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("diff --git") { return nil }
            if line.hasPrefix("\(key): ") { return String(line.dropFirst(key.count + 2)) }
        }
        return nil
    }

    /// `git apply` in a plain folder. The ceiling stops git from finding an enclosing repository, which
    /// would make it read the patch paths relative to that repository instead of the folder.
    static func gitApply(_ patch: SkillPatch, in folder: URL, extra: [String]) throws -> CommandResult {
        try Shell.run(["GIT_CEILING_DIRECTORIES=\(folder.deletingLastPathComponent().path)", "git", "apply"]
            + extra + [patch.url.path], in: folder)
    }

    static func firstLine(_ text: String) -> String {
        text.split(separator: "\n").first.map(String.init) ?? "git apply failed"
    }
}
