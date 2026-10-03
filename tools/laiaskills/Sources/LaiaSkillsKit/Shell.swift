import Foundation

/// Output of a finished subprocess.
public struct CommandResult: Sendable {
    public let status: Int32
    public let stdoutData: Data
    public let stderr: String

    public var succeeded: Bool { status == 0 }
    public var stdout: String { String(decoding: stdoutData, as: UTF8.self) }
}

public enum ShellError: Error, CustomStringConvertible {
    case failed(command: String, status: Int32, stderr: String)
    case timedOut(command: String, minutes: Int)

    public var description: String {
        switch self {
        case let .failed(command, status, stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "`\(command)` exited with \(status)" + (detail.isEmpty ? "" : ": \(detail)")
        case let .timedOut(command, minutes):
            return "`\(command)` did not finish within \(minutes) minutes and was stopped"
        }
    }
}

/// Runs external commands through `/usr/bin/env`, so the same code works on macOS and Linux.
public enum Shell {
    /// Runs a command and captures its output.
    /// - Parameter input: bytes written to the command's stdin (stdin is empty otherwise).
    public static func run(_ arguments: [String], in directory: URL? = nil, input: Data? = nil) throws -> CommandResult {
        let process = makeProcess(arguments, in: directory)
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        let stdinPipe = input.map { _ in Pipe() }
        process.standardInput = stdinPipe ?? FileHandle.nullDevice

        try process.run()
        if let stdinPipe, let input {
            stdinPipe.fileHandleForWriting.write(input)
            try? stdinPipe.fileHandleForWriting.close()
        }
        // Drain stderr on another thread so a chatty command can't fill the pipe and deadlock.
        let stderrBox = DataBox()
        let stderrDone = onDedicatedThread {
            stderrBox.data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        }
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        stderrDone.wait()
        process.waitUntilExit()

        return CommandResult(
            status: process.terminationStatus,
            stdoutData: stdoutData,
            stderr: String(decoding: stderrBox.data, as: UTF8.self)
        )
    }

    /// Runs a command attached to this terminal, so its output streams live. Stops it after `timeout`.
    public static func runAttached(_ arguments: [String], in directory: URL? = nil, timeoutMinutes: Int) throws -> Int32 {
        let process = makeProcess(arguments, in: directory)
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let finished = onDedicatedThread { process.waitUntilExit() }
        if finished.wait(timeout: .now() + .seconds(timeoutMinutes * 60)) == .timedOut {
            process.terminate()
            process.waitUntilExit()
            throw ShellError.timedOut(command: arguments.first ?? "", minutes: timeoutMinutes)
        }
        return process.terminationStatus
    }

    private static func makeProcess(_ arguments: [String], in directory: URL?) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        if let directory {
            process.currentDirectoryURL = directory
        }
        return process
    }
}

/// Runs `work` on its own thread and returns a semaphore signalled when it finishes.
/// Deliberately not GCD: callers block while waiting, and when every thread of GCD's shared pool
/// (which Swift concurrency and parallel tests also use) is blocked that way, work queued on the
/// pool never starts and everything deadlocks.
private func onDedicatedThread(_ work: @escaping @Sendable () -> Void) -> DispatchSemaphore {
    let done = DispatchSemaphore(value: 0)
    Thread {
        work()
        done.signal()
    }.start()
    return done
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
    public func run(_ arguments: [String], input: Data? = nil) throws -> String {
        String(decoding: try data(arguments, input: input), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Runs git and returns raw stdout bytes, throwing on a non-zero exit.
    public func data(_ arguments: [String], input: Data? = nil) throws -> Data {
        let result = try Shell.run(["git"] + arguments, in: directory, input: input)
        guard result.succeeded else {
            throw ShellError.failed(
                command: (["git"] + arguments).joined(separator: " "),
                status: result.status,
                stderr: result.stderr
            )
        }
        return result.stdoutData
    }

    /// Runs git and returns trimmed stdout, or nil on a non-zero exit.
    public func attempt(_ arguments: String...) -> String? {
        try? run(arguments)
    }

    public func attempt(_ arguments: [String]) -> String? {
        try? run(arguments)
    }
}
