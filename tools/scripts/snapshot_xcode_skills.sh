#!/usr/bin/env bash
# Snapshot the agent skills bundled with the selected Xcode into the xcode-skills mirror
# (third-party/kikeenrique__xcode-skills), one commit per Xcode build.
#
# Usage: tools/scripts/snapshot_xcode_skills.sh [--release] [--label <text>]
#   --release       The selected Xcode is a final release: tag the snapshot v<X.Y.Z>.
#   --label <text>  Pre-release label for the commit subject (default: "beta" or "RC", see below).
#
# The Xcode is the one `xcode-select -p` reports; set DEVELOPER_DIR to snapshot another one.
# Pre-release detection: Xcode's Contents/Resources/LicenseInfo.plist has licenseType "GM" for
# release candidates and final releases alike, and a different value for betas. So a non-GM license
# is always a beta; a GM one is only treated as final when --release is given (RC by default).
# Commits inside the mirror only; never pushes, and never touches laia-skills' own index.
set -euo pipefail

die() { echo "snapshot: $*" >&2; exit 1; }

release=false
label=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --release) release=true; shift ;;
    --label) [[ $# -ge 2 ]] || die "--label needs a value"; label="$2"; shift 2 ;;
    -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ "$(uname -s)" == "Darwin" ]] || die "needs macOS (Xcode)"
command -v xcode-select >/dev/null || die "xcode-select not found"
xcrun --find mcpbridge >/dev/null 2>&1 || die "xcrun mcpbridge not found in the selected Xcode"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
repo="$root/third-party/kikeenrique__xcode-skills"
git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 \
  || die "the mirror is not checked out: git submodule update --init third-party/kikeenrique__xcode-skills"
[[ -n "$(git -C "$repo" symbolic-ref -q HEAD)" ]] \
  || die "the mirror is on a detached HEAD; check out main first: git -C $repo checkout main"
if [[ -n "$(git -C "$repo" status --porcelain --untracked-files=all)" ]]; then
  git -C "$repo" status --short >&2
  die "the mirror's working tree is dirty; commit or discard the changes above first"
fi

# --- Xcode version ---------------------------------------------------------------------------
developer_dir="$(xcode-select -p)"
app="${developer_dir%/Contents/Developer}"
[[ -f "$app/Contents/version.plist" ]] || die "no version.plist in the selected Xcode ($app)"
plist() { plutil -extract "$2" raw -o - "$1" 2>/dev/null || true; }
marketing="$(plist "$app/Contents/version.plist" CFBundleShortVersionString)"
build="$(plist "$app/Contents/version.plist" ProductBuildVersion)"
license_type="$(plist "$app/Contents/Resources/LicenseInfo.plist" licenseType)"
[[ -n "$marketing" && -n "$build" ]] || die "could not read Xcode version from $app/Contents/version.plist"

# Cross-check with xcodebuild, which reads the same selected Xcode.
xb_build="$(xcodebuild -version 2>/dev/null | sed -n 's/^Build version //p')"
[[ -z "$xb_build" || "$xb_build" == "$build" ]] || die "xcodebuild reports build $xb_build, version.plist says $build"

if [[ "$license_type" != "GM" ]]; then
  $release && die "Xcode $marketing ($build) has a beta license (licenseType=${license_type:-missing}); refusing --release"
  prerelease=true
  label="${label:-beta}"
elif $release; then
  prerelease=false
  [[ -z "$label" ]] || die "--label is for pre-releases only"
else
  prerelease=true
  label="${label:-RC}"
fi

IFS=. read -r v1 v2 v3 _ <<<"$marketing"
[[ "$v1" =~ ^[0-9]+$ ]] || die "unexpected marketing version: $marketing"
tag="v${v1}.${v2:-0}.${v3:-0}"

if $prerelease; then
  subject="Xcode $marketing $label ($build)"
else
  subject="Xcode $marketing ($build)"
  if git -C "$repo" rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    die "tag $tag already exists"
  fi
fi

# --- Export --------------------------------------------------------------------------------
echo "Exporting skills from Xcode $marketing ($build)..."
plugin="$(xcrun mcpbridge run-agent plugin path --plugin-format claude | tail -n 1)"
[[ -d "$plugin/skills" ]] || die "plugin export has no skills/ folder: $plugin"
[[ -f "$plugin/.claude-plugin/plugin.json" ]] || die "plugin export has no .claude-plugin/plugin.json: $plugin"

rm -rf "$repo/skills" "$repo/xcode-plugin"
mkdir -p "$repo/xcode-plugin"
cp -RX "$plugin/skills" "$repo/skills"
cp -X "$plugin/.claude-plugin/plugin.json" "$repo/xcode-plugin/plugin.json"
[[ ! -f "$plugin/.mcp.json" ]] || cp -X "$plugin/.mcp.json" "$repo/xcode-plugin/mcp.json"
find "$repo/skills" -name .DS_Store -delete
# Xcode exports the files read-only; make them writable so the next snapshot can replace them.
chmod -R u+w "$repo/skills" "$repo/xcode-plugin"

skills=()
for dir in "$repo/skills"/*/; do
  [[ -f "$dir/SKILL.md" ]] && skills+=("$(basename "$dir")")
done
[[ ${#skills[@]} -gt 0 ]] || die "no skills found in the export"

{
  echo "{"
  echo "  \"xcode\": {"
  echo "    \"version\": \"$marketing\","
  echo "    \"build\": \"$build\","
  echo "    \"prerelease\": $prerelease,"
  echo "    \"licenseType\": \"$license_type\""
  echo "  },"
  echo "  \"exportCommand\": \"xcrun mcpbridge run-agent plugin path --plugin-format claude\","
  echo "  \"skills\": ["
  for i in "${!skills[@]}"; do
    sep=","; [[ $i -eq $((${#skills[@]} - 1)) ]] && sep=""
    echo "    \"${skills[$i]}\"$sep"
  done
  echo "  ]"
  echo "}"
} >"$repo/snapshot.json"

# --- Commit and tag ------------------------------------------------------------------------
paths=(skills xcode-plugin snapshot.json)
git -C "$repo" add -A -- "${paths[@]}"
if git -C "$repo" diff --cached --quiet -- "${paths[@]}"; then
  echo "No changes: the mirror already holds the skills of Xcode $marketing ($build)."
  committed=false
else
  echo "Changes:"
  git -C "$repo" diff --cached --stat -- "${paths[@]}" | tail -n 1
  git -C "$repo" commit -q -m "$subject" -m "${#skills[@]} skills, exported with xcrun mcpbridge run-agent plugin path." -- "${paths[@]}"
  committed=true
  echo "Committed $(git -C "$repo" rev-parse --short HEAD): $subject"
fi

if ! $prerelease; then
  git -C "$repo" tag -a "$tag" -m "Xcode $marketing ($build)"
  echo "Tagged $tag"
fi

if $committed || ! $prerelease; then
  echo
  echo "Nothing was pushed. To publish the mirror:"
  echo "  git -C third-party/kikeenrique__xcode-skills push origin main"
  $prerelease || echo "  git -C third-party/kikeenrique__xcode-skills push origin $tag"
  echo "Then move laia-skills' pin with laiaskills upgrade (or git add the submodule) and commit."
fi
