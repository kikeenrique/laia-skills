import Foundation
import Noora
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// Every terminal rendering call goes through here, so a breaking Noora release touches one file.
protocol UI {
    func table(headers: [String], rows: [[String]])
    func success(_ message: String)
    func info(_ message: String)
    func warning(_ messages: [String])
    func error(_ message: String)
    func line(_ message: String)
    /// Asks a yes/no question. Only valid when `isInteractive`.
    func confirm(_ question: String, default answer: Bool) -> Bool
    /// Lets the user pick several options. Only valid when `isInteractive`.
    func choose(_ question: String, options: [String]) -> [String]
    /// Lets the user pick one option ("/" filters long lists). `enter` says what picking does, in the key
    /// hints ("enter preview"). Only valid when `isInteractive`.
    func pick(_ question: String, options: [String], enter: String) -> String
    /// Starts a new screen: clears what's visible (scrollback stays). Only valid when `isInteractive`.
    func clearScreen()
    /// A short block: a highlighted title, a muted subtitle, body lines, and an optional warning.
    func summary(title: String, subtitle: String, body: [String], warning: String?)
    /// Shows a file in the user's pager ($PAGER, else less) and returns when they leave it.
    /// Only valid when `isInteractive`.
    func page(_ file: URL)
    /// Asks for a line of text, trimmed; empty when nothing was typed. Only valid when `isInteractive`.
    func ask(_ prompt: String, description: String) -> String
    /// True when both stdin and stdout are a terminal, so prompts can be shown.
    var isInteractive: Bool { get }
}

struct NooraUI: UI {
    private let noora = Noora()

    var isInteractive: Bool { isatty(STDIN_FILENO) == 1 && isatty(STDOUT_FILENO) == 1 }

    func line(_ message: String) {
        print(message)
    }

    func confirm(_ question: String, default answer: Bool) -> Bool {
        noora.yesOrNoChoicePrompt(question: "\(question)", defaultAnswer: answer)
    }

    func choose(_ question: String, options: [String]) -> [String] {
        noora.multipleChoicePrompt(question: "\(question)", options: options)
    }

    func clearScreen() {
        // Noora has no call for this; it's the standard sequence `clear` sends: cursor home, erase screen.
        print("\u{1B}[H\u{1B}[2J", terminator: "")
    }

    func summary(title: String, subtitle: String, body: [String], warning: String?) {
        print("\n" + noora.format("\(.primary(title))"))
        print(noora.format("\(.muted(subtitle))"))
        for line in body { print("\n" + line) }
        if let warning { print("\n" + noora.format("\(.danger("! \(warning)"))")) }
        print("")
    }

    func page(_ file: URL) {
        let pager = ProcessInfo.processInfo.environment["PAGER"].flatMap { $0.isEmpty ? nil : $0 } ?? "less"
        // The file is passed as an argument, never spliced into the command.
        let arguments = ["/bin/sh", "-c", "\(pager) \"$1\"", "sh", file.path]
        var argv = arguments.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        // posix_spawn, not Process: Process puts the child in its own process group, and a pager outside
        // the terminal's foreground group is stopped as soon as it reads the keyboard. Ctrl-C belongs to
        // the pager while it runs.
        let interrupt = signal(SIGINT, SIG_IGN)
        defer { signal(SIGINT, interrupt) }
        var pid = pid_t()
        guard posix_spawn(&pid, "/bin/sh", nil, nil, &argv, environ) == 0 else {
            return self.error("Couldn't start the pager `\(pager)`.")
        }
        var status: Int32 = 0
        waitpid(pid, &status, 0)
    }

    func ask(_ prompt: String, description: String) -> String {
        noora.textPrompt(prompt: "\(prompt)", description: "\(description)")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func pick(_ question: String, options: [String], enter: String) -> String {
        // Noora's key hints end in a generic "enter confirm" and leave out ctrl+c, its only way out.
        Noora(content: Self.content(enter: enter))
            .singleChoicePrompt(question: "\(question)", options: options, filterMode: .toggleable,
                                autoselectSingleChoice: false)
    }

    private static func content(enter action: String) -> Content {
        let base = Content.default
        return Content(
            errorAlertTitle: base.errorAlertTitle,
            errorAlertRecommendedTitle: base.errorAlertRecommendedTitle,
            warningAlertTitle: base.warningAlertTitle,
            warningAlertRecommendedTitle: base.warningAlertRecommendedTitle,
            successAlertTitle: base.successAlertTitle,
            successAlertRecommendedTitle: base.successAlertRecommendedTitle,
            infoAlertTitle: base.infoAlertTitle,
            infoAlertRecommendedTitle: base.infoAlertRecommendedTitle,
            choicePromptFilterTitle: base.choicePromptFilterTitle,
            choicePromptInstructionWithoutFilter: "↑↓ move • enter \(action) • ctrl+c quit",
            choicePromptInstructionWithFilter: "↑↓ move • / filter • enter \(action) • ctrl+c quit",
            choicePromptInstructionIsFiltering: "↑↓ move • esc clear filter • enter \(action) • ctrl+c quit",
            multipleChoicePromptFilterTitle: base.multipleChoicePromptFilterTitle,
            multipleChoicePromptErrorTitle: base.multipleChoicePromptErrorTitle,
            multipleChoicePromptInstructionWithoutFilter: base.multipleChoicePromptInstructionWithoutFilter,
            multipleChoicePromptInstructionWithFilter: base.multipleChoicePromptInstructionWithFilter,
            multipleChoicePromptInstructionIsFiltering: base.multipleChoicePromptInstructionIsFiltering,
            textPromptValidationErrorsTitle: base.textPromptValidationErrorsTitle,
            yesOrNoChoicePromptInstruction: base.yesOrNoChoicePromptInstruction,
            yesOrNoChoicePromptPositiveText: base.yesOrNoChoicePromptPositiveText,
            yesOrNoChoicePromptNegativeText: base.yesOrNoChoicePromptNegativeText
        )
    }

    func table(headers: [String], rows: [[String]]) {
        // Noora fits tables to the terminal width; when piped there is no terminal, so cells get
        // truncated. Print plain aligned columns instead.
        guard isatty(STDOUT_FILENO) == 1 else {
            return print(plainTable(headers: headers, rows: rows))
        }
        noora.table(headers: headers, rows: rows)
    }

    func success(_ message: String) {
        noora.success(.alert("\(message)"))
    }

    func info(_ message: String) {
        noora.info(.alert("\(message)"))
    }

    func warning(_ messages: [String]) {
        guard !messages.isEmpty else { return }
        noora.warning(messages.map { WarningAlert.alert("\($0)") })
    }

    func error(_ message: String) {
        noora.error(.alert("\(message)"))
    }
}

/// Space-aligned columns, no truncation.
func plainTable(headers: [String], rows: [[String]]) -> String {
    alignedColumns([headers] + rows).joined(separator: "\n")
}

/// A count with thousands separators (657,823). Not locale-aware, so output is the same everywhere.
func grouped(_ number: Int) -> String {
    let digits = String(number.magnitude)
    let groups = stride(from: digits.count, to: 0, by: -3).reversed().map { end in
        digits[digits.index(digits.startIndex, offsetBy: max(0, end - 3))..<digits.index(digits.startIndex, offsetBy: end)]
    }
    return (number < 0 ? "-" : "") + groups.joined(separator: ",")
}

/// One line per row, cells padded into columns (also for picker options, which are plain strings).
/// Columns in `rightAligned`, such as counts, are padded on the left.
func alignedColumns(_ rows: [[String]], rightAligned: Set<Int> = []) -> [String] {
    let count = rows.map(\.count).max() ?? 0
    let widths = (0..<count).map { column in rows.map { column < $0.count ? $0[column].count : 0 }.max() ?? 0 }
    return rows.map { row in
        row.enumerated().map { column, cell in
            let pad = String(repeating: " ", count: widths[column] - cell.count)
            if rightAligned.contains(column) { return pad + cell }
            return column == row.count - 1 ? cell : cell + pad
        }.joined(separator: "  ")
    }
}

/// Prints an Encodable report as stable, pretty JSON.
func printJSON<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    print(String(decoding: try encoder.encode(value), as: UTF8.self))
}
