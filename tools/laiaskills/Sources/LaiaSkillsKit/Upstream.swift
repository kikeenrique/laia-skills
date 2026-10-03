import Foundation

/// A release version parsed from a tag such as `v1.4.2`, `0.6.0`, or `v2026.9.4`.
public struct ReleaseVersion: Comparable, Sendable, CustomStringConvertible {
    public let components: [Int]
    public let tag: String

    /// Only stable releases count: digits separated by dots, optional leading `v`. Pre-releases are ignored.
    public init?(tag: String) {
        let body = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }
        components = parts.compactMap { Int($0) }
        self.tag = tag
    }

    public static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    public static func == (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }

    public var description: String { tag }
}

/// Pin vs. upstream for one submodule.
public struct SourceStatus: Codable, Sendable {
    public enum Mode: String, Codable, Sendable {
        /// Pinned to a release tag; newer releases are what matters.
        case tagged
        /// No release tags; compared against the tracked branch.
        case branch
    }

    public enum State: String, Codable, Sendable {
        case upToDate = "up to date"
        case outdated
        case unknown
    }

    public let path: String
    public let kind: String
    public let mode: Mode
    public let pinnedCommit: String
    public let pinnedTag: String?
    /// Newest stable tag (tagged mode) or branch name (branch mode).
    public let latest: String?
    /// Commits on the tracked branch after the pin (branch mode only).
    public let commitsBehind: Int?
    public let state: State
    public let note: String?

    /// Human-readable version of the pin.
    public var pinnedLabel: String { pinnedTag ?? String(pinnedCommit.prefix(7)) }
}

public enum UpstreamChecker {
    /// Compares a submodule's pinned commit with upstream.
    /// - Parameter fetch: fetch tags and branches first; when false, uses what was fetched last time (offline).
    public static func status(of submodule: Submodule, repo: URL, fetch: Bool) -> SourceStatus {
        let kind = submodule.isFirstPartyUpstream ? "first-party upstream" : "third-party"
        let git = Git(repo.appendingPathComponent(submodule.path))

        func unknown(_ note: String, commit: String = "") -> SourceStatus {
            SourceStatus(path: submodule.path, kind: kind, mode: .branch, pinnedCommit: commit, pinnedTag: nil,
                         latest: nil, commitsBehind: nil, state: .unknown, note: note)
        }

        guard FileManager.default.fileExists(atPath: git.directory.appendingPathComponent(".git").path) else {
            return unknown("not checked out")
        }
        guard let pinned = git.attempt("rev-parse", "HEAD") else { return unknown("cannot read pinned commit") }

        // Shallow sources: read the remote's tags and branch head without downloading history.
        if submodule.shallow && fetch {
            return shallowStatus(of: submodule, kind: kind, git: git, pinned: pinned)
        }

        var fetchNote: String?
        if fetch {
            do {
                try git.run("fetch", "--quiet", "--tags", "--force", "origin")
            } catch {
                fetchNote = "fetch failed; showing last fetched state"
            }
        }

        let pinnedTags = (git.attempt("tag", "--points-at", "HEAD") ?? "")
            .split(separator: "\n").map(String.init)
        let pinnedRelease = pinnedTags.compactMap(ReleaseVersion.init(tag:)).max()
        let releases = (git.attempt("tag", "--list") ?? "")
            .split(separator: "\n").compactMap { ReleaseVersion(tag: String($0)) }

        if let pinnedRelease, let newest = releases.max() {
            let outdated = pinnedRelease < newest
            return SourceStatus(path: submodule.path, kind: kind, mode: .tagged, pinnedCommit: pinned,
                                pinnedTag: pinnedRelease.tag, latest: newest.tag, commitsBehind: nil,
                                state: outdated ? .outdated : .upToDate, note: fetchNote)
        }

        // Untagged pin: compare with the tracked branch.
        let branch = submodule.branch ?? defaultBranch(git) ?? "main"
        guard let behindText = git.attempt("rev-list", "--count", "HEAD..origin/\(branch)"),
              let behind = Int(behindText) else {
            return unknown("cannot compare with origin/\(branch)", commit: pinned)
        }
        let note = [fetchNote, releases.isEmpty ? nil : "pin is not on a release tag"].compactMap { $0 }.joined(separator: "; ")
        return SourceStatus(path: submodule.path, kind: kind, mode: .branch, pinnedCommit: pinned,
                            pinnedTag: pinnedTags.first, latest: branch, commitsBehind: behind,
                            state: behind > 0 ? .outdated : .upToDate, note: note.isEmpty ? nil : note)
    }

    static func shallowStatus(of submodule: Submodule, kind: String, git: Git, pinned: String) -> SourceStatus {
        let pinnedRelease = (git.attempt("tag", "--points-at", "HEAD") ?? "")
            .split(separator: "\n").compactMap { ReleaseVersion(tag: String($0)) }.max()
        guard let releases = try? Adder.remoteReleaseTags(git) else {
            return SourceStatus(path: submodule.path, kind: kind, mode: .branch, pinnedCommit: pinned, pinnedTag: nil,
                                latest: nil, commitsBehind: nil, state: .unknown, note: "cannot reach origin")
        }
        if let pinnedRelease, let newest = releases.max() {
            return SourceStatus(path: submodule.path, kind: kind, mode: .tagged, pinnedCommit: pinned,
                                pinnedTag: pinnedRelease.tag, latest: newest.tag, commitsBehind: nil,
                                state: pinnedRelease < newest ? .outdated : .upToDate, note: nil)
        }
        let branch = submodule.branch ?? "main"
        let head = git.attempt("ls-remote", "origin", "refs/heads/\(branch)")?.split(separator: "\t").first.map(String.init)
        return SourceStatus(path: submodule.path, kind: kind, mode: .branch, pinnedCommit: pinned, pinnedTag: nil,
                            latest: branch, commitsBehind: nil,
                            state: head == nil ? .unknown : (head == pinned ? .upToDate : .outdated),
                            note: "shallow: newer commits exist but are not counted")
    }

    /// Checks many submodules in parallel (each is an independent git process).
    public static func statuses(of submodules: [Submodule], repo: URL, fetch: Bool) -> [SourceStatus] {
        let results = Results(count: submodules.count)
        DispatchQueue.concurrentPerform(iterations: submodules.count) { index in
            results.set(index, status(of: submodules[index], repo: repo, fetch: fetch))
        }
        return results.values
    }

    static func defaultBranch(_ git: Git) -> String? {
        guard let ref = git.attempt("symbolic-ref", "--short", "refs/remotes/origin/HEAD") else { return nil }
        return ref.hasPrefix("origin/") ? String(ref.dropFirst("origin/".count)) : ref
    }
}

private final class Results: @unchecked Sendable {
    private var storage: [SourceStatus?]
    private let lock = NSLock()

    init(count: Int) { storage = Array(repeating: nil, count: count) }

    func set(_ index: Int, _ value: SourceStatus) {
        lock.lock(); defer { lock.unlock() }
        storage[index] = value
    }

    var values: [SourceStatus] {
        lock.lock(); defer { lock.unlock() }
        return storage.compactMap { $0 }
    }
}
