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
}

struct NooraUI: UI {
    private let noora = Noora()

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
