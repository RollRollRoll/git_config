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
  echo "'$DEST' is not in your PATH. Adding it now..."

  # Detect shell RC file based on user's login shell (not the script's interpreter)
  SHELL_RC=""
  LOGIN_SHELL="$(basename "${SHELL:-bash}")"
  case "$LOGIN_SHELL" in
    zsh)  SHELL_RC="${HOME}/.zshrc" ;;
    bash)
      # Prefer .bash_profile (CentOS) or .profile (Ubuntu) for login shells,
      # fall back to .bashrc
      if [[ -f "${HOME}/.bash_profile" ]]; then
        SHELL_RC="${HOME}/.bash_profile"
      elif [[ -f "${HOME}/.profile" ]]; then
        SHELL_RC="${HOME}/.profile"
      else
        SHELL_RC="${HOME}/.bashrc"
      fi
      ;;
    *)
      # Unknown shell — try .profile as POSIX fallback
      SHELL_RC="${HOME}/.profile"
      ;;
  esac

  PATH_LINE="export PATH=\"${DEST}:\$PATH\""

  if ! grep -qF "$PATH_LINE" "$SHELL_RC" 2>/dev/null; then
    echo "" >> "$SHELL_RC"
    echo "# Added by git-profile installer" >> "$SHELL_RC"
    echo "$PATH_LINE" >> "$SHELL_RC"
    echo "Added to $SHELL_RC: $PATH_LINE"
  else
    echo "$SHELL_RC already contains the PATH entry."
  fi
  export PATH="${DEST}:$PATH"
fi

echo ""
echo "Installation complete! Run 'git-profile --help' to get started."
