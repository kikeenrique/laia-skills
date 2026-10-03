import Foundation

/// Output of a finished subprocess.
public struct CommandResult: Sendable {
    public let status: Int32
    public let stdout: String
    public let stderr: String

    public var succeeded: Bool { status == 0 }
}

public enum ShellError: Error, CustomStringConvertible {
    case failed(command: String, status: Int32, stderr: String)

    public var description: String {
        switch self {
        case let .failed(command, status, stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "`\(command)` exited with \(status)" + (detail.isEmpty ? "" : ": \(detail)")
        }
    }
}

/// Runs external commands through `/usr/bin/env`, so the same code works on macOS and Linux.
public enum Shell {
    public static func run(_ arguments: [String], in directory: URL? = nil) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        if let directory {
            process.currentDirectoryURL = directory
        }
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice

        try process.run()
        // Drain stderr on another thread so a chatty command can't fill the pipe and deadlock.
        let stderrBox = DataBox()
        let stderrDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            stderrBox.data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            stderrDone.signal()
        }
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        stderrDone.wait()
        process.waitUntilExit()

        return CommandResult(
            status: process.terminationStatus,
            stdout: String(decoding: stdoutData, as: UTF8.self),
            stderr: String(decoding: stderrBox.data, as: UTF8.self)
        )
    }
}

private final class DataBox: @unchecked Sendable {
    var data = Data()
}

/// Thin wrapper over the `git` CLI for one working directory.
public struct Git: Sendable {
    public let directory: URL

    public init(_ directory: URL) {
        self.directory = directory
    }

    /// Runs git and returns trimmed stdout, throwing on a non-zero exit.
    @discardableResult
    public func run(_ arguments: String...) throws -> String {
        try run(arguments)
    }

    @discardableResult
    public func run(_ arguments: [String]) throws -> String {
        let result = try Shell.run(["git"] + arguments, in: directory)
        guard result.succeeded else {
            throw ShellError.failed(
                command: (["git"] + arguments).joined(separator: " "),
                status: result.status,
                stderr: result.stderr
            )
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Runs git and returns trimmed stdout, or nil on a non-zero exit.
    public func attempt(_ arguments: String...) -> String? {
        try? run(arguments)
    }
}
