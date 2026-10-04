import Foundation

/// `skills.json` at the repo root: which skills come from which source.
public struct SkillsManifest: Codable, Sendable {
    public var skills: [String: SkillEntry]

    public init(skills: [String: SkillEntry]) {
        self.skills = skills
    }
}

extension SkillsManifest {
    /// Writes skills.json in its hand-edited layout: one line per skill, sorted by name.
    public func write(to url: URL, schema: String = "./tools/config/schemas/skills.schema.json") throws {
        func quoted(_ text: String) -> String {
            let data = (try? JSONSerialization.data(withJSONObject: [text], options: [.withoutEscapingSlashes])) ?? Data()
            return String(String(decoding: data, as: UTF8.self).dropFirst().dropLast())
        }
        let lines = skills.keys.sorted().map { name -> String in
            let entry = skills[name]!
            var fields = ["\"source\": \(quoted(entry.source))"]
            if let path = entry.path { fields.append("\"path\": \(quoted(path))") }
            if let skip = entry.skipMirrors {
                fields.append("\"skipMirrors\": [\(skip.map(quoted).joined(separator: ", "))]")
            }
            return "    \(quoted(name)): { \(fields.joined(separator: ", ")) }"
        }
        let text = """
        {
          "$schema": \(quoted(schema)),
          "skills": {
        \(lines.joined(separator: ",\n"))
          }
        }

        """
        try Data(text.utf8).write(to: url, options: .atomic)
    }
}

public struct SkillEntry: Codable, Sendable, Equatable {
    /// `first-party`, or a submodule path such as `third-party/owner__repo` or `first-party/<plugin>/upstream`.
    public var source: String
    /// Folder of the skill inside the source; only needed when the name alone is ambiguous.
    public var path: String?
    /// Mirrors (keys of `mirrors` in agents.json) that get no link, e.g. `["claude"]` for a skill Claude
    /// already gets another way. The hub copy is installed as usual.
    public var skipMirrors: [String]?

    public init(source: String, path: String? = nil, skipMirrors: [String]? = nil) {
        self.source = source
        self.path = path
        self.skipMirrors = skipMirrors
    }

    public static let firstParty = "first-party"

    public func skips(mirror: String) -> Bool {
        skipMirrors?.contains(mirror) == true
    }
}

/// `tools/config/agents.json`: the hub every skill is copied into, and the mirror folders linking to it.
public struct AgentsConfig: Codable, Sendable {
    public var hub: AgentTarget
    public var mirrors: [String: AgentTarget]

    public init(hub: AgentTarget, mirrors: [String: AgentTarget]) {
        self.hub = hub
        self.mirrors = mirrors
    }
}

public struct AgentTarget: Codable, Sendable {
    public var path: String
    public var description: String?

    public init(path: String, description: String? = nil) {
        self.path = path
        self.description = description
    }

    /// The path with a leading `~` replaced by the home directory.
    public func url(home: URL) -> URL {
        expandTilde(path, home: home)
    }
}

public func expandTilde(_ path: String, home: URL) -> URL {
    if path == "~" { return home }
    if path.hasPrefix("~/") {
        return home.appendingPathComponent(String(path.dropFirst(2)))
    }
    return URL(fileURLWithPath: path)
}

public enum ConfigError: Error, CustomStringConvertible {
    case repoNotFound(URL)
    case unreadable(URL, Error)

    public var description: String {
        switch self {
        case let .repoNotFound(start):
            return "No skills.json found in \(start.path) or any parent folder. Run inside the skills repo or pass --repo."
        case let .unreadable(url, error):
            return "Cannot read \(url.lastPathComponent): \(error)"
        }
    }
}

/// The skills repo: its root folder and the configs inside it.
public struct Repository: Sendable {
    public let root: URL
    public let manifest: SkillsManifest
    public let agents: AgentsConfig

    public static let manifestFile = "skills.json"
    public static let agentsFile = "tools/config/agents.json"

    public init(root: URL) throws {
        self.root = root.standardizedFileURL
        manifest = try Self.decode(SkillsManifest.self, at: self.root.appendingPathComponent(Self.manifestFile))
        agents = try Self.decode(AgentsConfig.self, at: self.root.appendingPathComponent(Self.agentsFile))
    }

    /// Walks up from `start` until a folder containing `skills.json` is found.
    public static func locate(from start: URL) throws -> Repository {
        var current = start.standardizedFileURL
        while true {
            if FileManager.default.fileExists(atPath: current.appendingPathComponent(manifestFile).path) {
                return try Repository(root: current)
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { throw ConfigError.repoNotFound(start) }
            current = parent
        }
    }

    static func decode<T: Decodable>(_ type: T.Type, at url: URL) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: Data(contentsOf: url))
        } catch {
            throw ConfigError.unreadable(url, error)
        }
    }
}

/// Machine-specific locations, injectable for tests.
public struct Environment: Sendable {
    public let home: URL

    public init(home: URL) {
        self.home = home
    }

    public static var current: Environment {
        let home = ProcessInfo.processInfo.environment["HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser
        return Environment(home: home)
    }

    /// Install state written by `laiaskills install`/`sync` (phase 2).
    public var stateFile: URL { home.appendingPathComponent(".agents/.laiaskills.json") }
    /// Previous copies of skills and lock files that laiaskills replaced.
    public var backups: URL { home.appendingPathComponent(".agents/.laiaskills/backups") }
    /// Lock file of the `npx skills` CLI.
    public var skillsCLILock: URL { home.appendingPathComponent(".agents/.skill-lock.json") }
    /// Claude Code's record of installed plugins.
    public var claudePlugins: URL { home.appendingPathComponent(".claude/plugins/installed_plugins.json") }
    /// Claude Code's record of added marketplaces and where they are cloned.
    public var claudeMarketplaces: URL { home.appendingPathComponent(".claude/plugins/known_marketplaces.json") }
}
