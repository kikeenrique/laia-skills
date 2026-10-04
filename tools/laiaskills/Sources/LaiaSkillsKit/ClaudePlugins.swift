import Foundation

/// An installed Claude Code plugin whose marketplace lists a newer version.
public struct ClaudePluginUpdate: Codable, Sendable, Equatable {
    public let plugin: String
    public let installed: String
    public let available: String
}

/// Claude Code plugins, read from Claude Code's own records. laiaskills never installs them (that stays
/// with `/plugin`); `skills.json` can declare which ones are expected (`claudePlugins`).
public enum ClaudePlugins {
    /// `<plugin>@<marketplace>` → installed version, from `~/.claude/plugins/installed_plugins.json`.
    public static func installed(_ environment: Environment) -> [String: String] {
        guard let plugins = readJSON(environment.claudePlugins)?["plugins"] as? [String: Any] else { return [:] }
        var versions: [String: String] = [:]
        for (id, value) in plugins {
            let installs = value as? [[String: Any]] ?? []
            versions[id] = installs.compactMap { $0["version"] as? String }.first ?? "?"
        }
        return versions
    }

    /// The version the marketplace lists, from its local clone (as fresh as the last
    /// `/plugin marketplace update`).
    static func marketplaceVersion(of id: String, environment: Environment) -> String? {
        let parts = id.split(separator: "@", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let location = (readJSON(environment.claudeMarketplaces)?[parts[1]] as? [String: Any])?["installLocation"] as? String,
              let entries = readJSON(URL(fileURLWithPath: location).appendingPathComponent(".claude-plugin/marketplace.json"))?["plugins"]
                as? [[String: Any]] else { return nil }
        return entries.first { $0["name"] as? String == parts[0] }?["version"] as? String
    }

    /// Installed plugins whose marketplace lists a newer version.
    public static func updates(environment: Environment) -> [ClaudePluginUpdate] {
        let versions = installed(environment)
        return versions.keys.sorted().compactMap { id in
            let current = versions[id] ?? "?"
            guard let available = marketplaceVersion(of: id, environment: environment), isNewer(available, than: current) else { return nil }
            return ClaudePluginUpdate(plugin: id, installed: current, available: available)
        }
    }

    /// Declared plugins that are missing, and installed ones that aren't declared. Nothing when
    /// `skills.json` declares no `claudePlugins` (tracking is opt-in).
    public static func findings(declared: [String]?, environment: Environment) -> [Finding] {
        guard let declared else { return [] }
        let present = Set(installed(environment).keys)
        var findings: [Finding] = []
        for id in declared.sorted() where !present.contains(id) {
            findings.append(Finding(severity: .warning, check: "claude-plugins",
                                    message: "\(id) is declared in skills.json but not installed; run `/plugin install \(id)` in Claude Code"))
        }
        for id in present.sorted() where !declared.contains(id) {
            findings.append(Finding(severity: .info, check: "claude-plugins",
                                    message: "\(id) is installed but not declared in skills.json `claudePlugins`; declare it or uninstall it"))
        }
        return findings
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        if let new = ReleaseVersion(tag: candidate), let old = ReleaseVersion(tag: current) { return old < new }
        return candidate != current
    }

    static func readJSON(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
