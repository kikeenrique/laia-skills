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
    /// Lets the user pick one option ("/" filters long lists). Only valid when `isInteractive`.
    func pick(_ question: String, options: [String]) -> String
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

    func pick(_ question: String, options: [String]) -> String {
        noora.singleChoicePrompt(question: "\(question)", options: options, filterMode: .toggleable,
                                 autoselectSingleChoice: false)
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
    let all = [headers] + rows
    let widths = headers.indices.map { column in all.map { $0[column].count }.max() ?? 0 }
    return all.map { row in
        row.enumerated().map { column, cell in
            column == row.count - 1 ? cell : cell.padding(toLength: widths[column], withPad: " ", startingAt: 0)
        }.joined(separator: "  ")
    }.joined(separator: "\n")
}

/// Prints an Encodable report as stable, pretty JSON.
func printJSON<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    print(String(decoding: try encoder.encode(value), as: UTF8.self))
}
