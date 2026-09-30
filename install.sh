#!/usr/bin/env bash
# Keep the command linked to this clone so edits do not require reinstalling.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${HOME}/.local/bin"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  echo "Usage: bash install.sh [target_bin_dir]"
  echo "Links record-it into target_bin_dir (default: ~/.local/bin)."
  echo "Run bash setup_mac.sh first to build and stage the macOS app."
  exit 0
fi
if [[ $# -gt 1 || "${1:-}" == -* ]]; then
  echo "Usage: bash install.sh [target_bin_dir]" >&2
  exit 2
fi
if [[ $# -eq 1 ]]; then
  TARGET_DIR="$1"
fi

mkdir -p "$TARGET_DIR"
# Refuse a directory here: ln would silently create a link inside it instead.
if [[ -d "$TARGET_DIR/record-it" ]]; then
  echo "ERROR: $TARGET_DIR/record-it is a directory." >&2
  exit 1
fi
chmod +x "$SCRIPT_DIR/record-it"
ln -sf "$SCRIPT_DIR/record-it" "$TARGET_DIR/record-it"
echo "Installed $TARGET_DIR/record-it -> $SCRIPT_DIR/record-it"

case ":$PATH:" in
  *":$TARGET_DIR:"*) ;;
  *)
    echo "Add this to ~/.zshrc or ~/.bashrc:"
    echo "  export PATH=\"$TARGET_DIR:\$PATH\""
    ;;
esac
echo "Build the app with: bash \"$SCRIPT_DIR/setup_mac.sh\""
echo "Then launch it with: record-it"
