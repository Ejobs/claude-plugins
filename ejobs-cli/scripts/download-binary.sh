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

set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set by Claude Code}"

VERSION_FILE="$PLUGIN_ROOT/VERSION"
INSTALL_ROOT="$HOME/.cache/ejobs-plugin"
BIN_DIR="$INSTALL_ROOT/bin"
BIN_PATH="$BIN_DIR/ejobs-cli"
MARKER="$BIN_DIR/installed-version"

# Append a PATH export to $CLAUDE_ENV_FILE so Claude's Bash tool can
# invoke `ejobs-cli` as a bare command. No-op when not running inside
# a SessionStart hook (e.g. manual smoke-tests).
export_path_to_env_file() {
  if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
    echo 'export PATH="$HOME/.cache/ejobs-plugin/bin:$PATH"' >> "$CLAUDE_ENV_FILE"
  fi
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

# All binaries + manifest.json are released as assets of this plugin repo.
# Unified versioning: release tag matches plugin version exactly (v<X.Y.Z>).
RELEASE_TAG="v${TARGET_VERSION}"
BASE_URL="https://github.com/Ejobs/claude-plugins/releases/download/${RELEASE_TAG}"

MANIFEST_URL="${BASE_URL}/manifest.json"
BINARY_URL="${BASE_URL}/${FILENAME}"

echo "ejobs plugin: downloading ejobs-cli ${TARGET_VERSION} for ${OS}/${ARCH}" >&2

mkdir -p "$BIN_DIR"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

curl --fail --silent --show-error --location "$MANIFEST_URL" -o "$TMP_DIR/manifest.json" \
  || { echo "ejobs plugin: failed to fetch $MANIFEST_URL" >&2; exit 1; }

EXPECTED_SHA="$(
  python3 -c "
import json, sys
m = json.load(open('$TMP_DIR/manifest.json'))
for b in m['binaries']:
    if b['os'] == '$OS' and b['arch'] == '$ARCH':
        print(b['sha256'])
        sys.exit(0)
sys.exit('no matching binary in manifest for $OS/$ARCH')
" 2>&1
)" || { echo "ejobs plugin: $EXPECTED_SHA" >&2; exit 1; }

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
