#!/usr/bin/env bash
# install.sh — install git-profile to local bin
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE="${SCRIPT_DIR}/git-profile"

if [[ ! -f "$SOURCE" ]]; then
  echo "Error: git-profile not found in $SCRIPT_DIR" >&2
  exit 1
fi

DEFAULT_DEST="${HOME}/.local/bin"

echo "=== Git Profile Installer ==="
echo ""

DEST="${1:-$DEFAULT_DEST}"
read -rp "Install to [$DEST]: " user_dest
DEST="${user_dest:-$DEST}"

mkdir -p "$DEST"

cp "$SOURCE" "$DEST/git-profile"
chmod +x "$DEST/git-profile"
echo "Installed: $DEST/git-profile"

if [[ ! -f "${HOME}/.git-profiles.conf" ]]; then
  touch "${HOME}/.git-profiles.conf"
  echo "Created: ~/.git-profiles.conf"
fi

mkdir -p "${HOME}/.gitconfig.d"
echo "Created: ~/.gitconfig.d/"

git config --global alias.profile '!git-profile'
echo "Git alias set: git profile -> git-profile"

if [[ ":$PATH:" != *":$DEST:"* ]]; then
  echo ""
  echo "Warning: '$DEST' is not in your PATH."
  echo "Add this to your shell profile (~/.bashrc or ~/.zshrc):"
  echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

echo ""
echo "Installation complete! Run 'git-profile --help' to get started."
