import Foundation

/// A staged change made by laiaskills, waiting for `laiaskills commit` to write its commit message.
public struct PendingChange: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case add, remove, upgrade, patch
    }

    /// Outcome of the automated re-check of a first-party skill after its upstream moved.
    public enum Recheck: String, Codable, Sendable {
        case changed, unchanged, skipped
    }

    public var kind: Kind
    public var skills: [String]
    /// Submodule path involved, if any.
    public var source: String?
    /// Previous and new pin labels (tag or short commit) for upgrades.
    public var from: String?
    public var to: String?
    /// First-party plugin whose `upstream/` pin moved.
    public var plugin: String?
    public var recheck: Recheck?
    /// For `patch`: the new patch file (repo-relative) and why it exists.
    public var patch: String?
    public var reason: String?
    /// For `upgrade`: patch files deleted because the new pin already contains their change.
    public var droppedPatches: [String]?

    public init(kind: Kind, skills: [String], source: String? = nil, from: String? = nil, to: String? = nil,
                plugin: String? = nil, recheck: Recheck? = nil, patch: String? = nil, reason: String? = nil,
                droppedPatches: [String]? = nil) {
        self.kind = kind
        self.skills = skills
        self.source = source
        self.from = from
        self.to = to
        self.plugin = plugin
        self.recheck = recheck
        self.patch = patch
        self.reason = reason
        self.droppedPatches = droppedPatches
    }
}

/// Pending changes are kept inside `.git/laiaskills/`, so they are never committed by accident.
public struct PendingChanges: Codable, Sendable {
    public var changes: [PendingChange] = []

    public init(changes: [PendingChange] = []) {
        self.changes = changes
    }

    static func file(repo: URL) throws -> URL {
        let gitDirectory = try Git(repo).run("rev-parse", "--absolute-git-dir")
        return URL(fileURLWithPath: gitDirectory).appendingPathComponent("laiaskills/pending.json")
    }

    public static func load(repo: URL) -> PendingChanges {
        guard let file = try? file(repo: repo), let data = try? Data(contentsOf: file),
              let pending = try? JSONDecoder().decode(PendingChanges.self, from: data) else { return PendingChanges() }
        return pending
    }

    public func save(repo: URL) throws {
        let file = try Self.file(repo: repo)
        if changes.isEmpty {
            try? FileManager.default.removeItem(at: file)
            return
        }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: file, options: .atomic)
    }

    /// Records a change, replacing an earlier upgrade of the same source so the log reflects the final pin.
    public static func record(_ change: PendingChange, repo: URL) throws {
        var pending = load(repo: repo)
        if change.kind == .upgrade, let index = pending.changes.firstIndex(where: { $0.kind == .upgrade && $0.source == change.source }) {
            var merged = change
            merged.from = pending.changes[index].from
            let dropped = (pending.changes[index].droppedPatches ?? []) + (change.droppedPatches ?? [])
            merged.droppedPatches = dropped.isEmpty ? nil : dropped
            pending.changes[index] = merged
        } else {
            pending.changes.append(change)
        }
        try pending.save(repo: repo)
    }
}
