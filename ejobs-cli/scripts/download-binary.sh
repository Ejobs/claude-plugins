#!/usr/bin/env bash
# download-binary.sh — fires on SessionStart. Fetches the ejobs-cli binary
# matching the host OS/arch and the version pinned in ejobs-cli/VERSION,
# caches under $CLAUDE_PLUGIN_DATA/bin, and prepends it to PATH.
#
# No-op on fast path: if the cached marker already records the target version
# for this arch, we skip the network entirely.

set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set by Claude Code}"
PLUGIN_DATA="${CLAUDE_PLUGIN_DATA:?CLAUDE_PLUGIN_DATA must be set by Claude Code}"

VERSION_FILE="$PLUGIN_ROOT/VERSION"
BIN_DIR="$PLUGIN_DATA/bin"
BIN_PATH="$BIN_DIR/ejobs-cli"
MARKER="$BIN_DIR/installed-version"

if [ ! -f "$VERSION_FILE" ]; then
  echo "ejobs plugin: VERSION file missing at $VERSION_FILE" >&2
  exit 1
fi

TARGET_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"

# Fast path: cached binary already matches the pinned version.
if [ -x "$BIN_PATH" ] && [ -f "$MARKER" ] && [ "$(cat "$MARKER")" = "$TARGET_VERSION" ]; then
  echo "ejobs plugin: using cached binary $BIN_PATH (version $TARGET_VERSION)" >&2
  export PATH="$BIN_DIR:$PATH"
  exit 0
fi

# Detect OS/arch.
case "$(uname -s)" in
  Darwin) OS="darwin" ;;
  Linux)  OS="linux" ;;
  MINGW*|MSYS*|CYGWIN*) OS="windows" ;;
  *) echo "ejobs plugin: unsupported OS $(uname -s)" >&2; exit 1 ;;
esac

case "$(uname -m)" in
  x86_64|amd64) ARCH="amd64" ;;
  arm64|aarch64) ARCH="arm64" ;;
  *) echo "ejobs plugin: unsupported arch $(uname -m)" >&2; exit 1 ;;
esac

EXT=""
if [ "$OS" = "windows" ]; then
  EXT=".exe"
fi
FILENAME="ejobs-cli-${OS}-${ARCH}${EXT}"

# All binaries + manifest.json are released as assets of this plugin repo.
RELEASE_TAG="cli-v${TARGET_VERSION}"
BASE_URL="https://github.com/Ejobs/claude-plugins/releases/download/${RELEASE_TAG}"

MANIFEST_URL="${BASE_URL}/manifest.json"
BINARY_URL="${BASE_URL}/${FILENAME}"

echo "ejobs plugin: downloading ejobs-cli ${TARGET_VERSION} for ${OS}/${ARCH}" >&2

mkdir -p "$BIN_DIR"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# Fetch manifest + look up expected sha256 for our target.
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

# Fetch binary, verify sha256, install atomically.
curl --fail --silent --show-error --location "$BINARY_URL" -o "$TMP_DIR/$FILENAME" \
  || { echo "ejobs plugin: failed to fetch $BINARY_URL" >&2; exit 1; }

ACTUAL_SHA="$(shasum -a 256 "$TMP_DIR/$FILENAME" | awk '{print $1}')"
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
export PATH="$BIN_DIR:$PATH"
