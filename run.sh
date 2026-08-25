#!/bin/bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BREW_BIN="/opt/homebrew/bin/brew"

MODE="install"
UPGRADE=0
CONFIGURE_DEFAULTS=1
CONFIGURE_DOTFILES=1
INSTALL_APPS=1

usage() {
  cat <<'EOF'
Usage: ./run.sh [options]

Bootstrap an Apple Silicon Mac from this repository.

Options:
  --check                 Check the machine without changing it
  --upgrade               Upgrade outdated Brewfile packages
  --skip-macos-defaults   Do not change Dock or Finder preferences
  --skip-dotfiles         Do not add the managed zsh blocks or install .vimrc
  --skip-apps             Skip casks and VS Code extensions (useful while migrating)
  -h, --help              Show this help
EOF
}

log() {
  printf '\n\033[1;34m==>\033[0m %s\n' "$*"
}

warn() {
  printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2
}

die() {
  printf '\033[1;31merror:\033[0m %s\n' "$*" >&2
  exit 1
}

while (($#)); do
  case "$1" in
    --check)
      MODE="check"
      ;;
    --upgrade)
      UPGRADE=1
      ;;
    --skip-macos-defaults)
      CONFIGURE_DEFAULTS=0
      ;;
    --skip-dotfiles)
      CONFIGURE_DOTFILES=0
      ;;
    --skip-apps)
      INSTALL_APPS=0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "unknown option: $1"
      ;;
  esac
  shift
done

require_apple_silicon() {
  [[ "$(uname -s)" == "Darwin" ]] || die "this bootstrap supports macOS only"
  [[ "$(uname -m)" == "arm64" ]] || die "this bootstrap requires a native Apple Silicon shell (arm64)"
}

ensure_command_line_tools() {
  if xcode-select -p >/dev/null 2>&1; then
    return
  fi

  log "Requesting Xcode Command Line Tools"
  xcode-select --install
  cat <<'EOF'
Complete the installer window, then run ./run.sh again.
EOF
  exit 0
}

ensure_homebrew() {
  if [[ ! -x "$BREW_BIN" ]]; then
    log "Installing native Homebrew in /opt/homebrew"
    NONINTERACTIVE=1 /bin/bash -c \
      "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi

  # shellcheck disable=SC1090
  eval "$("$BREW_BIN" shellenv)"
  [[ "$(brew --prefix)" == "/opt/homebrew" ]] || die "Homebrew did not resolve to /opt/homebrew"
}

install_brew_bundle() {
  local bundle_file="$SCRIPT_DIR/Brewfile"
  local filtered_bundle=""

  log "Installing the Apple Silicon Brewfile"

  if ((!INSTALL_APPS)); then
    filtered_bundle="$(mktemp "${TMPDIR:-/tmp}/mac-init-brewfile.XXXXXX")"
    awk '!/^(cask|vscode) / { print }' "$bundle_file" >"$filtered_bundle"
    bundle_file="$filtered_bundle"
  fi

  if ((UPGRADE)); then
    brew bundle --file="$bundle_file" --upgrade
  else
    brew bundle --file="$bundle_file" --no-upgrade
  fi

  if [[ -n "$filtered_bundle" ]]; then
    rm -f "$filtered_bundle"
  fi
}

update_managed_block() {
  local target="$1"
  local source_file="$2"
  local start_marker="# >>> mac-init managed block >>>"
  local end_marker="# <<< mac-init managed block <<<"
  local temporary
  local backup

  temporary="$(mktemp "${TMPDIR:-/tmp}/mac-init.XXXXXX")"

  if [[ -f "$target" ]]; then
    awk -v start="$start_marker" -v end="$end_marker" '
      $0 == start { skipping = 1; next }
      $0 == end   { skipping = 0; next }
      !skipping   { print }
    ' "$target" >"$temporary"
  else
    : >"$temporary"
  fi

  if [[ -s "$temporary" ]] && [[ "$(tail -c 1 "$temporary" | wc -l | tr -d ' ')" == "0" ]]; then
    printf '\n' >>"$temporary"
  fi

  {
    printf '%s\n' "$start_marker"
    cat "$source_file"
    printf '%s\n' "$end_marker"
  } >>"$temporary"

  if [[ -f "$target" ]] && cmp -s "$temporary" "$target"; then
    rm -f "$temporary"
    return
  fi

  if [[ -f "$target" ]]; then
    backup="${target}.mac-init-backup.$(date +%Y%m%d%H%M%S)"
    cp -p "$target" "$backup"
    log "Backed up $target to $backup"
  fi

  mv "$temporary" "$target"
}

configure_shell() {
  log "Updating managed zsh configuration"
  update_managed_block "$HOME/.zprofile" "$SCRIPT_DIR/config/zprofile"
  update_managed_block "$HOME/.zshrc" "$SCRIPT_DIR/config/zshrc"
}

configure_vim() {
  local target="$HOME/.vimrc"

  if [[ ! -e "$target" ]]; then
    install -m 0644 "$SCRIPT_DIR/.vimrc" "$target"
  elif ! cmp -s "$SCRIPT_DIR/.vimrc" "$target"; then
    warn "$target already exists and differs; leaving it unchanged"
  fi

  if [[ ! -f "$HOME/.vim/autoload/plug.vim" ]]; then
    log "Installing vim-plug"
    curl -fLo "$HOME/.vim/autoload/plug.vim" --create-dirs \
      https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
  fi
}

configure_git() {
  if ! git config --global --get core.editor >/dev/null; then
    git config --global core.editor vim
  fi

  if [[ -n "${GIT_USER_NAME:-}" ]]; then
    git config --global user.name "$GIT_USER_NAME"
  fi
  if [[ -n "${GIT_USER_EMAIL:-}" ]]; then
    git config --global user.email "$GIT_USER_EMAIL"
  fi

  if ! git config --global --get user.name >/dev/null || \
     ! git config --global --get user.email >/dev/null; then
    warn "Git identity is incomplete; set GIT_USER_NAME and GIT_USER_EMAIL before rerunning"
  fi
}

configure_runtimes() {
  local rustup_bin

  log "Ensuring current Node.js LTS and Rust stable toolchains"
  eval "$(fnm env --shell bash)"
  fnm install --lts
  fnm default lts-latest

  rustup_bin="$(brew --prefix rustup)/bin/rustup"
  "$rustup_bin" set default-host aarch64-apple-darwin
  if ! "$rustup_bin" toolchain list | grep -q '^stable-aarch64-apple-darwin'; then
    "$rustup_bin" toolchain install stable --profile default
  fi
  "$rustup_bin" default stable-aarch64-apple-darwin
}

configure_macos() {
  log "Applying macOS preferences"
  defaults write com.apple.dock autohide -bool true
  defaults write com.apple.finder AppleShowAllFiles -bool true
  killall Dock >/dev/null 2>&1 || true
  killall Finder >/dev/null 2>&1 || true
}

prepare_folders() {
  mkdir -p "$HOME/code/github" "$HOME/code/github-self" "$HOME/go/bin"
}

warn_about_intel_homebrew() {
  if [[ -x /usr/local/bin/brew ]]; then
    warn "Intel Homebrew still exists at /usr/local; it was not modified or removed"
  fi
}

main() {
  require_apple_silicon

  if [[ "$MODE" == "check" ]]; then
    exec "$SCRIPT_DIR/scripts/doctor.sh"
  fi

  ensure_command_line_tools
  ensure_homebrew
  warn_about_intel_homebrew
  prepare_folders
  install_brew_bundle
  configure_runtimes
  configure_git

  if ((CONFIGURE_DOTFILES)); then
    configure_shell
    configure_vim
  fi

  if ((CONFIGURE_DEFAULTS)); then
    configure_macos
  fi

  log "Bootstrap complete"
  printf '%s\n' "Open a new terminal, then run: ./run.sh --check"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main
fi
