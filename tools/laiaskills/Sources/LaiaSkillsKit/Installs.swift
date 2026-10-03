import Foundation

/// What sits at `~/.agents/skills/<name>`.
public enum HubState: String, Codable, Sendable {
    case missing
    /// Installed and recorded by laiaskills.
    case managed
    /// A folder laiaskills did not install (another tool, or a manual copy).
    case foreign
    /// A symlink, which laiaskills never creates in the hub.
    case foreignLink = "foreign link"
    case brokenLink = "broken link"
}

/// What sits at `<mirror>/<name>`, e.g. `~/.claude/skills/<name>`.
public enum MirrorState: String, Codable, Sendable {
    case missing
    /// A symlink to the hub entry.
    case linked
    /// A symlink whose target does not exist.
    case broken
    /// A real folder or a link pointing somewhere other than the hub.
    case bypass
}

public struct InstallInspector: Sendable {
    public let hub: URL
    public let mirrors: [(name: String, url: URL)]
    public let state: InstallState?

    public init(agents: AgentsConfig, environment: Environment) {
        hub = agents.hub.url(home: environment.home)
        mirrors = agents.mirrors.keys.sorted().map { ($0, agents.mirrors[$0]!.url(home: environment.home)) }
        state = InstallState.load(environment)
    }

    public func hubState(_ name: String) -> HubState {
        let entry = hub.appendingPathComponent(name)
        switch kind(of: entry) {
        case .none: return .missing
        case .link: return FileManager.default.fileExists(atPath: entry.path) ? .foreignLink : .brokenLink
        case .other: return state?.skills[name] != nil ? .managed : .foreign
        }
    }

    public func mirrorState(_ name: String, in mirror: URL) -> MirrorState {
        let entry = mirror.appendingPathComponent(name)
        switch kind(of: entry) {
        case .none: return .missing
        case .other: return .bypass
        case .link:
            guard FileManager.default.fileExists(atPath: entry.path) else { return .broken }
            return entry.resolvingSymlinksInPath().path == hub.appendingPathComponent(name).resolvingSymlinksInPath().path
                ? .linked : .bypass
        }
    }

    /// Names of all entries in a folder (hidden entries skipped), including broken links.
    public func entries(in folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { !$0.hasPrefix(".") }
            .sorted()
    }

    enum EntryKind { case link, other }

    /// Uses lstat semantics, so broken symlinks are still seen.
    func kind(of url: URL) -> EntryKind? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return attributes[.type] as? FileAttributeType == .typeSymbolicLink ? .link : .other
    }
}
