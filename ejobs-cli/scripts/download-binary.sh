#!/usr/bin/env bash
# download-binary.sh — fires on SessionStart. Fetches the ejobs-cli binary
# matching the host OS/arch and the version pinned in ejobs-cli/VERSION,
# caches under $HOME/.cache/ejobs-plugin/bin, and adds it to Claude's
# Bash-tool PATH via $CLAUDE_ENV_FILE.
#
# Why $HOME/.cache and not $CLAUDE_PLUGIN_DATA: plugin-scoped env vars
# are only set inside hooks. Claude's Bash tool calls don't see them,
# so we install to a $HOME-rooted path and export it via CLAUDE_ENV_FILE
# (a documented SessionStart mechanism that persists env changes into
# every subsequent Bash tool call).
#
# Environment overrides:
#   EJOBS_CLI_RELEASE_BASE_URL   override the GitHub release base URL
#                                (useful for testing against a fork).
#                                Default: https://github.com/Ejobs/claude-plugins

set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set by Claude Code}"

VERSION_FILE="$PLUGIN_ROOT/VERSION"
INSTALL_ROOT="$HOME/.cache/ejobs-plugin"
BIN_DIR="$INSTALL_ROOT/bin"
BIN_PATH="$BIN_DIR/ejobs-cli"
MARKER="$BIN_DIR/installed-version"
PATH_EXPORT_LINE='export PATH="$HOME/.cache/ejobs-plugin/bin:$PATH"'

RELEASE_BASE_URL="${EJOBS_CLI_RELEASE_BASE_URL:-https://github.com/Ejobs/claude-plugins}"

# Append a PATH export to $CLAUDE_ENV_FILE so Claude's Bash tool can
# invoke `ejobs-cli` as a bare command. Skipped when not running inside
# a SessionStart hook (e.g. manual smoke-tests). Guarded against
# duplicate entries in case the hook fires more than once against the
# same env file.
export_path_to_env_file() {
  if [ -z "${CLAUDE_ENV_FILE:-}" ]; then
    return 0
  fi
  if [ -f "$CLAUDE_ENV_FILE" ] && grep -qF "$PATH_EXPORT_LINE" "$CLAUDE_ENV_FILE"; then
    return 0
  fi
  echo "$PATH_EXPORT_LINE" >> "$CLAUDE_ENV_FILE"
}

# Portable SHA256 — prefer sha256sum (GNU coreutils, ubiquitous on Linux)
# then fall back to shasum -a 256 (macOS default).
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

if [ ! -f "$VERSION_FILE" ]; then
  echo "ejobs plugin: VERSION file missing at $VERSION_FILE" >&2
  exit 1
fi

TARGET_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"

# Sanity-check the version string before weaving it into URLs. A typo
# like "latest" or "foo" would otherwise produce a cryptic 404.
if ! [[ "$TARGET_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?(\+[A-Za-z0-9.-]+)?$ ]]; then
  echo "ejobs plugin: invalid version in $VERSION_FILE: '$TARGET_VERSION' (expected SemVer X.Y.Z)" >&2
  exit 1
fi

# Fast path: cached binary already matches the pinned version.
if [ -x "$BIN_PATH" ] && [ -f "$MARKER" ] && [ "$(cat "$MARKER")" = "$TARGET_VERSION" ]; then
  echo "ejobs plugin: using cached binary $BIN_PATH (version $TARGET_VERSION)" >&2
  export_path_to_env_file
  exit 0
fi

# Detect OS/arch.
case "$(uname -s)" in
  Darwin) OS="darwin" ;;
  Linux)  OS="linux" ;;
  *) echo "ejobs plugin: unsupported OS $(uname -s) — macOS and Linux only for now" >&2; exit 1 ;;
esac

case "$(uname -m)" in
  x86_64|amd64) ARCH="amd64" ;;
  arm64|aarch64) ARCH="arm64" ;;
  *) echo "ejobs plugin: unsupported arch $(uname -m)" >&2; exit 1 ;;
esac

FILENAME="ejobs-cli-${OS}-${ARCH}"

# Release tag is namespaced by plugin name (ejobs-cli/v<X.Y.Z>) so the
# plugin-hosting repo can accommodate sibling plugins later without a
# tag-naming collision. GitHub handles slashes in release tag URLs.
RELEASE_TAG="ejobs-cli/v${TARGET_VERSION}"
BASE_URL="${RELEASE_BASE_URL}/releases/download/${RELEASE_TAG}"

MANIFEST_URL="${BASE_URL}/manifest.json"
BINARY_URL="${BASE_URL}/${FILENAME}"

echo "ejobs plugin: downloading ejobs-cli ${TARGET_VERSION} for ${OS}/${ARCH}" >&2

mkdir -p "$BIN_DIR"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

curl --fail --silent --show-error --location "$MANIFEST_URL" -o "$TMP_DIR/manifest.json" \
  || { echo "ejobs plugin: failed to fetch $MANIFEST_URL" >&2; exit 1; }

# Extract expected sha256 for our (os, arch) — keep stdout (the hash)
# separate from stderr (the error message) so we can report both cleanly.
if ! EXPECTED_SHA="$(
  python3 - "$OS" "$ARCH" "$TMP_DIR/manifest.json" <<'PY' 2>"$TMP_DIR/py-err"
import json, sys
os_name, arch, manifest_path = sys.argv[1], sys.argv[2], sys.argv[3]
with open(manifest_path) as f:
    m = json.load(f)
for b in m["binaries"]:
    if b["os"] == os_name and b["arch"] == arch:
        print(b["sha256"])
        sys.exit(0)
print(f"no matching binary in manifest for {os_name}/{arch}", file=sys.stderr)
sys.exit(1)
PY
)"; then
  echo "ejobs plugin: manifest lookup failed: $(cat "$TMP_DIR/py-err")" >&2
  exit 1
fi

curl --fail --silent --show-error --location "$BINARY_URL" -o "$TMP_DIR/$FILENAME" \
  || { echo "ejobs plugin: failed to fetch $BINARY_URL" >&2; exit 1; }

ACTUAL_SHA="$(sha256_of "$TMP_DIR/$FILENAME")"
if [ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]; then
  echo "ejobs plugin: sha256 mismatch for $FILENAME" >&2
  echo "  expected: $EXPECTED_SHA" >&2
  echo "  got:      $ACTUAL_SHA" >&2
  exit 1
fi

chmod +x "$TMP_DIR/$FILENAME"
mv "$TMP_DIR/$FILENAME" "$BIN_PATH"
echo "$TARGET_VERSION" > "$MARKER"

echo "ejobs plugin: installed ejobs-cli $TARGET_VERSION to $BIN_PATH" >&2
export_path_to_env_file
