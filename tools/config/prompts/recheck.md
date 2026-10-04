You are re-checking the `{{plugin}}` agent skill in this repository after its upstream project,
{{upstream}}, moved from {{from}} to {{to}}. The upstream source is checked out at `{{upstreamPath}}`
(already at {{to}}); the skill lives in `{{skillsPath}}/`.

Read `AGENTS.md` first and follow its conventions.

1. Find what changed upstream between the two versions, for example
   `git -C {{upstreamPath}} log --oneline {{from}}..{{to}}` and
   `git -C {{upstreamPath}} diff --stat {{from}} {{to}}`, plus the upstream changelog and docs.
2. Compare that with what the skill says: commands, flags, options, defaults, file formats, versions,
   deprecations, and any "verified against" version.
3. Update the skill where it is now wrong or missing something that matters to its users. Keep the
   skill's existing structure and tone; don't rewrite parts that are still correct.
   - Fix everything that is now wrong: removed or renamed commands, flags, settings, and backends,
     changed defaults, deprecations with their removal version.
   - Cover new user-facing features (commands, flags, settings, config keys, backend and task options),
     each in a sentence or a short example in the reference file for its area. Reference files are
     only read when a task needs them, so they may grow. Skip internal changes, fixes without a
     visible effect, registry additions, and platform-specific details unless the skill already
     covers that platform.
   - Keep the main skill file compact: it loads whenever the skill triggers. Only touch it to route to
     new material or to fix something it gets wrong.
4. If nothing needs to change, change nothing.

Rules:
- Only edit files under `{{skillsPath}}/`. Changes anywhere else are reverted automatically.
- Don't create scratch or notes files anywhere; keep working notes in your reply.
- Do not run git commands that change anything (no add, commit, checkout, reset, push).
- Do not edit `plugin.json` or `marketplace.json`; the plugin version is bumped automatically.
- Quote long `description` frontmatter values with double quotes.
- No machine-specific paths, account ids, or other local values in the skill.

When done, reply with a short summary of what you changed and why, or "No changes needed."
