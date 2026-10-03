import ArgumentParser
import Foundation
import LaiaSkillsKit

struct DoctorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Check skills.json, the agent folders, and other skill tools for problems.",
        discussion: "Read-only. Exits with status 1 when any error is found; warnings don't fail."
    )

    @OptionGroup var options: GlobalOptions

    func run() throws {
        let context = try Context(options)
        let findings = Doctor.run(
            repo: context.repo,
            submodules: context.submodules,
            skills: context.skills,
            inspector: context.inspector,
            environment: context.environment
        )

        if options.json {
            try printJSON(findings)
        } else {
            let ui = NooraUI()
            if findings.isEmpty {
                ui.success("No problems found.")
            } else {
                ui.table(
                    headers: ["Severity", "Check", "Finding"],
                    rows: findings.map { [$0.severity.rawValue, $0.check, $0.message] }
                )
                let counts = Dictionary(grouping: findings, by: \.severity).mapValues(\.count)
                ui.info("\(counts[.error] ?? 0) errors, \(counts[.warning] ?? 0) warnings, \(counts[.info] ?? 0) notes.")
            }
        }

        if findings.contains(where: { $0.severity == .error }) {
            throw ExitCode(1)
        }
    }
}
