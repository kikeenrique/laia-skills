import Foundation

/// Where an installed copy stands relative to its pin.
public enum InstallStatus: Sendable, Equatable {
    case notInstalled
    /// In the hub, but not installed by laiaskills.
    case foreign
    case upToDate
    /// The copy differs from the pin (the pin moved, or the skill moved inside its source).
    case notSynced
    /// The installed files were edited in place.
    case modified([String])
    /// Installed from uncommitted first-party edits.
    case workingTree
    case error(String)

    public var label: String {
        switch self {
        case .notInstalled: return "not installed"
        case .foreign: return "installed by another tool"
        case .upToDate: return "up to date"
        case .notSynced: return "not synced"
        case .modified: return "modified"
        case .workingTree: return "working tree"
        case let .error(message): return "error: \(message)"
        }
    }
}

/// One step of a sync.
public enum SyncAction: Sendable, Equatable {
    case install
    case replaceForeign
    case reinstall
    /// The copy is up to date but a mirror link is missing, or present where the skill skips that mirror.
    case relink
    case keep
    case skipModified([String])
    case remove
    case failed(String)
}

public struct SyncStep: Sendable {
    public let name: String
    public let action: SyncAction
}

/// Copies skills into the hub, links mirrors, keeps backups, and records state.
public struct Installer {
    public let repo: Repository
    public let environment: Environment
    public let hub: URL
    public let mirrors: [(name: String, url: URL)]
    public private(set) var state: InstallState
    /// Previous copies, newest kept per skill: `~/.agents/.laiaskills/backups/<name>-<timestamp>`.
    public var backups: URL { environment.backups }
    static let backupsKept = 3

    public init(repo: Repository, environment: Environment) {
        self.repo = repo
        self.environment = environment
        hub = repo.agents.hub.url(home: environment.home)
        mirrors = repo.agents.mirrors.keys.sorted().map { ($0, repo.agents.mirrors[$0]!.url(home: environment.home)) }
        state = InstallState.load(environment) ?? InstallState()
    }

    // MARK: Status

    public func status(of skill: ResolvedSkill) -> InstallStatus {
        let folder = hub.appendingPathComponent(skill.name)
        guard FileManager.default.fileExists(atPath: folder.path) else { return .notInstalled }
        guard let record = state.skills[skill.name] else { return .foreign }
        if let changed = editedFiles(folder: folder, record: record), !changed.isEmpty { return .modified(changed) }
        if record.workingTree == true { return .workingTree }
        guard skill.problem == nil else { return .error(skill.problem!) }
        // Installed before plugin manifests and nested skills were left out of copies.
        if let files = record.files, Exporter.installablePaths(Array(files.keys)).count != files.count { return .notSynced }
        do {
            let pin = try Pins.pin(for: skill, repo: repo.root)
            return pin.tree == record.tree && record.source == skill.entry.source ? .upToDate : .notSynced
        } catch {
            return .error("\(error)")
        }
    }

    /// Files whose content no longer matches the recorded fingerprint; nil if it can't be computed.
    func editedFiles(folder: URL, record: InstallState.Record) -> [String]? {
        guard let recorded = record.files, let current = try? Exporter.fingerprint(folder) else { return nil }
        return Set(recorded.keys).union(current.keys).filter { recorded[$0] != current[$0] }.sorted()
    }

    // MARK: Plan

    /// What `sync` would do: every skill in skills.json, plus removal of recorded skills no longer listed.
    public func plan(_ skills: [ResolvedSkill], force: Bool) -> [SyncStep] {
        var steps = skills.map { skill -> SyncStep in
            let action: SyncAction
            switch status(of: skill) {
            case .notInstalled: action = .install
            case .foreign: action = .replaceForeign
            case .notSynced, .workingTree: action = .reinstall
            case let .modified(files): action = force ? .reinstall : .skipModified(files)
            case .upToDate: action = mirrorsLinked(skill) ? .keep : .relink
            case let .error(message): action = .failed(message)
            }
            return SyncStep(name: skill.name, action: action)
        }
        let listed = Set(skills.map(\.name))
        for name in state.skills.keys.sorted() where !listed.contains(name) {
            steps.append(SyncStep(name: name, action: .remove))
        }
        return steps
    }

    // MARK: Install / remove

    /// Exports the skill at its pin (or copies its working tree) into the hub, atomically, and links mirrors.
    @discardableResult
    public mutating func install(_ skill: ResolvedSkill, workingTree: Bool = false) throws -> InstallState.Record {
        try FileManager.default.createDirectory(at: hub, withIntermediateDirectories: true)
        let staging = hub.appendingPathComponent(".laiaskills-staging-\(skill.name)-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: staging) }

        let record: InstallState.Record
        if workingTree {
            guard skill.entry.source == SkillEntry.firstParty, let folder = skill.folder else {
                throw PinError.unresolved(skill.name, "--working-tree only applies to first-party skills")
            }
            try Exporter.copyWorkingTree(from: folder, to: staging)
            record = InstallState.Record(source: skill.entry.source, path: relativePath(of: folder, to: repo.root),
                                         commit: nil, tag: nil, tree: nil, files: try Exporter.fingerprint(staging),
                                         installedAt: Self.timestamp(), workingTree: true)
        } else {
            let pin = try Pins.pin(for: skill, repo: repo.root)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            let files = try Exporter.export(pin, to: staging)
            record = InstallState.Record(source: skill.entry.source, path: pin.path, commit: pin.commit, tag: pin.tag,
                                         tree: pin.tree, files: files, installedAt: Self.timestamp(), workingTree: false)
        }

        let target = hub.appendingPathComponent(skill.name)
        if entryExists(target) { try backUp(target, name: skill.name) }
        try FileManager.default.moveItem(at: staging, to: target)
        try linkMirrors(skill)

        state.skills[skill.name] = record
        try state.save(environment)
        return record
    }

    /// Moves the hub copy to backups, removes the mirror links to it, and forgets the skill. Links to
    /// anything else (e.g. in a mirror the skill skips) stay.
    public mutating func uninstall(_ name: String) throws {
        let target = hub.appendingPathComponent(name)
        if entryExists(target) { try backUp(target, name: name) }
        for mirror in mirrors {
            let link = mirror.url.appendingPathComponent(name)
            let ours = relativeLink(from: mirror.url, to: target)
            if isSymlink(link), (try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) == ours {
                try FileManager.default.removeItem(at: link)
            }
        }
        state.skills[name] = nil
        try state.save(environment)
    }

    /// Makes `<mirror>/<name>` a relative symlink to the hub copy. Real folders there are backed up first.
    /// In mirrors the skill skips, removes a link to the hub copy and leaves anything else alone.
    public func linkMirrors(_ skill: ResolvedSkill) throws {
        let name = skill.name
        let target = hub.appendingPathComponent(name)
        for mirror in mirrors {
            let link = mirror.url.appendingPathComponent(name)
            let destination = relativeLink(from: mirror.url, to: target)
            if skill.entry.skips(mirror: mirror.name) {
                if linksToHub(link, name: name) { try FileManager.default.removeItem(at: link) }
                continue
            }
            try FileManager.default.createDirectory(at: mirror.url, withIntermediateDirectories: true)
            if isSymlink(link) {
                if (try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) == destination { continue }
                try FileManager.default.removeItem(at: link)
            } else if entryExists(link) {
                try backUp(link, name: "\(mirror.name)-\(name)")
            }
            try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: destination)
        }
    }

    /// Whether every mirror has exactly the link `linkMirrors` would leave: the hub link in mirrors the
    /// skill uses, none in the mirrors it skips.
    public func mirrorsLinked(_ skill: ResolvedSkill) -> Bool {
        mirrors.allSatisfy { mirror in
            let link = mirror.url.appendingPathComponent(skill.name)
            if skill.entry.skips(mirror: mirror.name) { return !linksToHub(link, name: skill.name) }
            let destination = relativeLink(from: mirror.url, to: hub.appendingPathComponent(skill.name))
            return (try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) == destination
        }
    }

    func linksToHub(_ link: URL, name: String) -> Bool {
        isSymlink(link) && FileManager.default.fileExists(atPath: link.path)
            && link.resolvingSymlinksInPath().path == hub.appendingPathComponent(name).resolvingSymlinksInPath().path
    }

    // MARK: Backups

    func backUp(_ item: URL, name: String) throws {
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        var destination = backups.appendingPathComponent("\(name)-\(Self.timestamp(compact: true))")
        var counter = 1
        while entryExists(destination) {
            counter += 1
            destination = backups.appendingPathComponent("\(name)-\(Self.timestamp(compact: true))-\(counter)")
        }
        try FileManager.default.moveItem(at: item, to: destination)
        pruneBackups(name)
    }

    /// Keeps the newest few backups per skill.
    func pruneBackups(_ name: String) {
        let all = ((try? FileManager.default.contentsOfDirectory(atPath: backups.path)) ?? [])
            .filter { $0.hasPrefix(name + "-") && $0.dropFirst(name.count + 1).first?.isNumber == true }
            .sorted(by: >)
        for old in all.dropFirst(Self.backupsKept) {
            try? FileManager.default.removeItem(at: backups.appendingPathComponent(old))
        }
    }

    // MARK: Helpers

    static func timestamp(compact: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = compact ? "yyyyMMdd-HHmmss" : "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return formatter.string(from: Date())
    }

    func entryExists(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    func isSymlink(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType == .typeSymbolicLink
    }
}

/// Relative path from folder `from` to `to`, e.g. `~/.claude/skills` → `~/.agents/skills/x` = `../../.agents/skills/x`.
public func relativeLink(from folder: URL, to target: URL) -> String {
    let base = folder.standardizedFileURL.pathComponents
    let destination = target.standardizedFileURL.pathComponents
    var common = 0
    while common < min(base.count, destination.count), base[common] == destination[common] { common += 1 }
    return (Array(repeating: "..", count: base.count - common) + destination[common...]).joined(separator: "/")
}
