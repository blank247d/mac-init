#!/bin/bash

set -uo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly BREW_BIN="/opt/homebrew/bin/brew"

errors=0
warnings=0
bundle_check_file=""

ok() {
  printf '\033[1;32mok:\033[0m %s\n' "$*"
}

error() {
  printf '\033[1;31merror:\033[0m %s\n' "$*" >&2
  errors=$((errors + 1))
}

warn() {
  printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2
  warnings=$((warnings + 1))
}

if [[ "$(uname -s)" != "Darwin" ]]; then
  error "not running on macOS"
elif [[ "$(uname -m)" != "arm64" ]]; then
  error "shell architecture is $(uname -m), expected arm64"
else
  ok "native Apple Silicon shell"
fi

if [[ ! -x "$BREW_BIN" ]]; then
  error "native Homebrew is missing from /opt/homebrew"
else
  # shellcheck disable=SC1090
  eval "$("$BREW_BIN" shellenv)"
  if "$BREW_BIN" list --formula rustup >/dev/null 2>&1; then
    export PATH="$("$BREW_BIN" --prefix rustup)/bin:$PATH"
  fi
  if [[ "$(command -v brew)" == "$BREW_BIN" ]]; then
    ok "Homebrew resolves to $BREW_BIN"
  else
    error "Homebrew resolves to $(command -v brew), expected $BREW_BIN"
  fi

  bundle_check_file="$(mktemp "${TMPDIR:-/tmp}/mac-init-doctor.XXXXXX")"
  awk '!/^(cask|vscode) / { print }' "$SCRIPT_DIR/Brewfile" >"$bundle_check_file"
  if brew bundle check --no-upgrade --file="$bundle_check_file" >/dev/null 2>&1; then
    ok "Brewfile command-line dependencies are installed"
  else
    warn "Brewfile has missing command-line dependencies; run ./run.sh --skip-apps"
  fi
  rm -f "$bundle_check_file"
fi

if [[ -x /usr/local/bin/brew ]]; then
  warn "legacy Intel Homebrew exists at /usr/local/bin/brew"
fi

legacy_pattern='/usr/local/(go|opt|share/zsh-autosuggestions)|jdk1\.8\.0|apache-maven-3\.6\.2|gcc-10|texlive/2019|Library/Python/3\.8'
for shell_file in "$HOME/.zprofile" "$HOME/.zshrc" "$HOME/.bash_profile"; do
  if [[ -f "$shell_file" ]] && grep -Eq "$legacy_pattern" "$shell_file"; then
    warn "$shell_file still contains Intel or obsolete toolchain paths"
  fi
done

for tool in brew git go node npm python3 java mvn rustc cargo; do
  if tool_path="$(command -v "$tool" 2>/dev/null)"; then
    if file "$tool_path" 2>/dev/null | grep -q 'x86_64' && \
       ! file "$tool_path" 2>/dev/null | grep -q 'arm64'; then
      warn "$tool resolves to an Intel-only executable: $tool_path"
    else
      ok "$tool -> $tool_path"
    fi
  else
    warn "$tool is not available"
  fi
done

printf '\nResult: %d error(s), %d warning(s).\n' "$errors" "$warnings"
((errors == 0))
