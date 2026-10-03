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
   skill's existing structure, tone, and length; don't rewrite parts that are still correct.
4. If nothing needs to change, change nothing.

Rules:
- Only edit files under `{{skillsPath}}/`. Changes anywhere else are reverted automatically.
- Do not run git commands that change anything (no add, commit, checkout, reset, push).
- Do not edit `plugin.json` or `marketplace.json`; the plugin version is bumped automatically.
- Quote long `description` frontmatter values with double quotes.
- No machine-specific paths, account ids, or other local values in the skill.

When done, reply with a short summary of what you changed and why, or "No changes needed."
