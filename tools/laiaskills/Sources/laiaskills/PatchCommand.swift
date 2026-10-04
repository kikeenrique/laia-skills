import ArgumentParser
import Foundation
import LaiaSkillsKit

struct PatchCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "patch",
        abstract: "Save a local fix to a third-party skill as a patch applied on every install.",
        discussion: """
        Edit the installed copy in the hub (e.g. after a security audit), then run `laiaskills patch <skill> \
        -m "<reason>"`: the edits become patches/<skill>/NNNN-<reason>.patch, relative to the pin plus the \
        earlier patches. With --from, an existing patch file is used instead (paths relative to the skill \
        folder, a/ and b/ prefixes). The patch is staged and the skill reinstalled with it; commit with \
        `laiaskills commit`. On `upgrade`, patches the new version already contains are dropped, and ones \
        that no longer apply stop the upgrade.
        """
    )

    @OptionGroup var options: GlobalOptions

    @Argument(help: "Third-party skill from skills.json.")
    var skill: String

    @Option(name: [.customShort("m"), .customLong("reason")], help: "Why the patch exists (also names the file).")
    var reason: String

    @Option(help: "Use this patch file instead of the edits to the installed copy.")
    var from: String?

    func run() throws {
        let context = try Context(options)
        guard let resolved = try select([skill], from: context.skills).first else { return }
        var installer = Installer(repo: context.repo, environment: context.environment)
        if from == nil, installer.state.skills[skill] == nil { throw PatchError.notInstalled(skill) }

        let file = try Patches.save(skill: resolved, reason: reason, from: from.map { URL(fileURLWithPath: $0) },
                                    repo: context.repo, hub: installer.hub, date: String(Installer.timestampDay()))
        let path = relativePath(of: file, to: context.repo.root)
        try Git(context.repo.root).run("add", "--", path)
        let pin = try? Pins.pin(for: resolved, repo: context.repo.root)
        try PendingChanges.record(PendingChange(kind: .patch, skills: [skill], source: resolved.entry.source,
                                                to: pin.map { $0.tag ?? String($0.commit.prefix(7)) },
                                                patch: path, reason: reason),
                                  repo: context.repo.root)
        // Reinstall from the pin plus every patch; the edited copy goes to backups.
        try installer.install(resolved)

        if options.json { return try printJSON(["skill": skill, "patch": path]) }
        NooraUI().success("Saved \(path) and reinstalled \(skill) with it. Staged; commit with `laiaskills commit`.")
    }
}
