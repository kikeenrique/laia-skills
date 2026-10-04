import Foundation

public struct Finding: Codable, Sendable {
    public enum Severity: String, Codable, Sendable, Comparable {
        case error, warning, info

        private var rank: Int { [.error: 0, .warning: 1, .info: 2][self]! }
        public static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rank < rhs.rank }
    }

    public let severity: Severity
    public let check: String
    public let message: String
}

/// Read-only health checks of the repo config, the agent folders, and other skill tools.
public enum Doctor {
    /// The mirror Claude Code reads. A skill that skips it may also come from a Claude plugin.
    static let claudeMirror = "claude"

    public static func run(
        repo: Repository,
        submodules: [Submodule],
        skills: [ResolvedSkill],
        inspector: InstallInspector,
        environment: Environment
    ) -> [Finding] {
        var findings: [Finding] = []
        func add(_ severity: Finding.Severity, _ check: String, _ message: String) {
            findings.append(Finding(severity: severity, check: check, message: message))
        }
        let managedNames = Set(repo.manifest.skills.keys)

        // skills.json entries that don't resolve to exactly one skill, or skip a mirror that doesn't exist.
        for skill in skills {
            if let problem = skill.problem { add(.error, "manifest", "\(skill.name): \(problem)") }
            for mirror in skill.entry.skipMirrors ?? [] where repo.agents.mirrors[mirror] == nil {
                add(.error, "manifest", "\(skill.name): skipMirrors names `\(mirror)`, which is not a mirror in agents.json")
            }
        }
        func skips(_ name: String, _ mirror: String) -> Bool {
            repo.manifest.skills[name]?.skips(mirror: mirror) == true
        }

        // Third-party sources no skill uses.
        let usedSources = Set(repo.manifest.skills.values.map(\.source))
        for submodule in submodules where !submodule.isFirstPartyUpstream && !usedSources.contains(submodule.path) {
            add(.warning, "sources", "\(submodule.path) is a submodule but no skill in skills.json uses it")
        }

        // Hub entries for managed skills that another tool put there.
        for name in managedNames.sorted() {
            switch inspector.hubState(name) {
            case .foreign:
                add(.info, "hub", "\(name): installed by another tool; `laiaskills sync` will replace it")
            case .foreignLink:
                add(.warning, "hub", "\(name): the hub entry is a symlink; laiaskills installs real copies")
            case .brokenLink:
                add(.warning, "hub", "\(name): broken symlink in \(inspector.hub.path)")
            case .missing, .managed:
                break
            }
        }

        // Recorded installs whose folder is gone.
        for name in (inspector.state?.skills.keys.sorted() ?? []) where inspector.hubState(name) == .missing {
            add(.error, "state", "\(name): recorded as installed but missing from \(inspector.hub.path)")
        }

        // Mirrors: broken links anywhere, managed skills that bypass the hub, links the skill opts out of,
        // and installed skills with no link.
        for mirror in inspector.mirrors {
            for name in inspector.entries(in: mirror.url) {
                switch inspector.mirrorState(name, in: mirror.url) {
                case .broken:
                    add(.warning, "mirror", "\(mirror.name): broken symlink `\(name)`")
                case .bypass where managedNames.contains(name) && !skips(name, mirror.name):
                    add(.warning, "mirror", "\(mirror.name): `\(name)` does not link to the hub copy")
                case .linked where skips(name, mirror.name):
                    add(.warning, "mirror", "\(mirror.name): `\(name)` links to the hub copy but skips this mirror; `laiaskills sync` removes the link")
                default:
                    break
                }
            }
            for name in managedNames.sorted() where inspector.hubState(name) == .managed && !skips(name, mirror.name)
                && inspector.mirrorState(name, in: mirror.url) == .missing {
                add(.warning, "mirror", "\(mirror.name): `\(name)` has no link to the hub copy; `laiaskills sync` adds it")
            }
        }

        findings += skillsCLIFindings(managedNames: managedNames, inspector: inspector, environment: environment)
        findings += claudePluginFindings(managedNames: managedNames.filter { !skips($0, claudeMirror) }, environment: environment)
        return findings.sorted { ($0.severity, $0.check, $0.message) < ($1.severity, $1.check, $1.message) }
    }

    /// `npx skills` lock entries that point at nothing, or that laiaskills now manages.
    static func skillsCLIFindings(managedNames: Set<String>, inspector: InstallInspector, environment: Environment) -> [Finding] {
        guard let skills = readJSON(environment.skillsCLILock)?["skills"] as? [String: Any] else { return [] }
        var findings: [Finding] = []
        for name in skills.keys.sorted() {
            if inspector.hubState(name) == .missing {
                findings.append(Finding(severity: .warning, check: "skills-cli",
                                        message: "\(name): listed in .skill-lock.json but not installed; `laiaskills import --prune` removes the entry"))
            } else if managedNames.contains(name) {
                findings.append(Finding(severity: .info, check: "skills-cli",
                                        message: "\(name): also tracked by .skill-lock.json; `laiaskills import --prune` removes the entry once laiaskills installed it"))
            }
        }
        return findings
    }

    /// Claude Code plugins that ship a skill laiaskills also installs: Claude would load it twice.
    static func claudePluginFindings(managedNames: Set<String>, environment: Environment) -> [Finding] {
        guard let plugins = readJSON(environment.claudePlugins)?["plugins"] as? [String: Any] else { return [] }
        let marketplaces = readJSON(environment.claudeMarketplaces) ?? [:]
        var findings: [Finding] = []
        for (plugin, value) in plugins.sorted(by: { $0.key < $1.key }) {
            let installs = value as? [[String: Any]] ?? []
            for install in installs {
                guard let path = install["installPath"] as? String else { continue }
                let names = claudePluginSkillNames(plugin: plugin, installPath: URL(fileURLWithPath: path),
                                                   marketplaces: marketplaces)
                let duplicates = Set(names.map { $0.lowercased() }).intersection(managedNames).sorted()
                guard !duplicates.isEmpty else { continue }
                findings.append(Finding(
                    severity: .warning, check: "claude-plugins",
                    message: "plugin \(plugin) also provides \(duplicates.joined(separator: ", ")); uninstall it once laiaskills installs them, or Claude loads them twice"
                ))
            }
        }
        return findings
    }

    /// Skills a Claude Code plugin activates, looked up in the order Claude Code uses: the marketplace
    /// entry's `skills` list, then the plugin's own `plugin.json`, then the default `skills/` folder.
    /// Paths in those lists are relative to the plugin root, which is `installPath`.
    static func claudePluginSkillNames(plugin: String, installPath: URL, marketplaces: [String: Any]) -> [String] {
        let parts = plugin.split(separator: "@", maxSplits: 1).map(String.init)
        if parts.count == 2,
           let location = (marketplaces[parts[1]] as? [String: Any])?["installLocation"] as? String,
           let entries = readJSON(URL(fileURLWithPath: location).appendingPathComponent(".claude-plugin/marketplace.json"))?["plugins"] as? [[String: Any]],
           let paths = entries.first(where: { $0["name"] as? String == parts[0] })?["skills"] as? [String] {
            return skillNames(at: paths, root: installPath)
        }
        if let paths = readJSON(installPath.appendingPathComponent(".claude-plugin/plugin.json"))?["skills"] as? [String] {
            return skillNames(at: paths, root: installPath)
        }
        return SkillDiscovery.allSkills(under: installPath.appendingPathComponent("skills")).map(\.name)
    }

    private static func skillNames(at paths: [String], root: URL) -> [String] {
        paths.compactMap { path in
            SkillDiscovery.frontmatterName(of: root.appendingPathComponent(path).appendingPathComponent("SKILL.md"))
        }
    }

    private static func readJSON(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
