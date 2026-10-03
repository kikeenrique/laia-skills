import Foundation
@testable import LaiaSkillsKit

/// A scratch folder under the repo's `tmp/`, removed when the fixture is released.
final class Fixture {
    let root: URL

    init(_ name: String = #function) throws {
        // Tests/LaiaSkillsKitTests/Fixtures.swift → repo root is four levels above the package.
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let safeName = name.filter { $0.isLetter || $0.isNumber }
        root = repoRoot.appendingPathComponent("tmp/laiaskills-tests/\(safeName)-\(UUID().uuidString.prefix(8))")
            .standardizedFileURL
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func url(_ path: String) -> URL {
        root.appendingPathComponent(path)
    }

    @discardableResult
    func write(_ path: String, _ content: String) throws -> URL {
        let file = url(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    func skill(_ folder: String, name: String) throws {
        try write("\(folder)/SKILL.md", "---\nname: \(name)\ndescription: \"Test skill.\"\n---\n\n# \(name)\n")
    }

    func mkdir(_ path: String) throws {
        try FileManager.default.createDirectory(at: url(path), withIntermediateDirectories: true)
    }

    func symlink(_ path: String, to destination: String) throws {
        try FileManager.default.createDirectory(at: url(path).deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: url(path).path, withDestinationPath: destination)
    }

    /// Runs git with settings that don't depend on the developer's global config (signing, default branch).
    @discardableResult
    func git(_ arguments: String..., in path: String = "") throws -> String {
        let base = ["-c", "user.name=Test", "-c", "user.email=test@example.com", "-c", "commit.gpgsign=false",
                    "-c", "tag.gpgsign=false", "-c", "init.defaultBranch=main"]
        return try Git(path.isEmpty ? root : url(path)).run(base + arguments)
    }

    /// An "origin" repo with one commit per entry; entries with a tag get tagged.
    func originRepo(_ path: String, commits: [(file: String, tag: String?)]) throws {
        try mkdir(path)
        try git("init", "--quiet", in: path)
        for commit in commits {
            try write("\(path)/\(commit.file)", commit.file)
            try git("add", ".", in: path)
            try git("commit", "--quiet", "-m", commit.file, in: path)
            if let tag = commit.tag { try git("tag", tag, in: path) }
        }
    }
}
