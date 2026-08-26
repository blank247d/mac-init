# AGENTS.md

## Project Scope

This repository bootstraps the current Apple Silicon Mac. Keep changes focused on
the machine setup represented by `Brewfile`, `run.sh`, `config/`, and `scripts/`.

The supported baseline is macOS on native `arm64`, with Homebrew installed at
`/opt/homebrew`. Do not add Intel Homebrew paths, architecture shims, fixed legacy
download URLs, or GUI automation tied to a specific macOS language or layout.

## Safety and Compatibility

- Keep setup scripts idempotent and safe to run repeatedly.
- Prefer a read-only check before changing machine state. Preserve `./run.sh
  --check` as a non-mutating path.
- Do not automatically delete `/usr/local`, an old Homebrew installation, user
  data, existing applications, or toolchain directories.
- Back up an existing dotfile before changing its managed block. Do not replace
  unrelated user configuration.
- Preserve existing global Git identity. Only set `user.name` or `user.email`
  when the user supplies them explicitly.
- Prefer command-line interfaces such as `defaults` over GUI scripting for macOS
  configuration.
- Never commit credentials, tokens, private keys, machine identifiers, or other
  secrets collected from the local computer.

## Dependency Policy

- Treat `Brewfile` as a curated desired-state list, not a complete dump of the
  current machine.
- Do not overwrite `Brewfile` with `brew bundle dump`. Dump to a temporary file
  and review the diff first.
- Prefer current Homebrew packages and supported runtime managers over pinned
  legacy formulae or hand-installed versioned binaries.
- Keep MinIO packages, taps, services, and configuration out of the baseline
  unless the user explicitly requests their return.
- Keep desktop applications and VS Code extensions skippable through
  `./run.sh --skip-apps`.

## Implementation Conventions

- Shell scripts use Bash with strict error handling where appropriate.
- Quote variable expansions and use explicit, validated paths for operations that
  modify files.
- Put reusable shell configuration in `config/`; keep machine checks in
  `scripts/doctor.sh`.
- Update `README.md` whenever supported behavior, command-line options, runtime
  policy, or migration guidance changes.

## Validation

Run the relevant checks before handing off changes:

```sh
bash -n run.sh scripts/doctor.sh
zsh -n config/zprofile config/zshrc
./run.sh --check
```

When `Brewfile` changes, also run:

```sh
/opt/homebrew/bin/brew bundle check --no-upgrade --file=./Brewfile
```

`brew bundle check` may report intentionally missing packages on a partially
configured machine; distinguish that machine state from syntax or repository
errors in the handoff.

## Git Workflow

- The primary branch is `master`.
- Keep unrelated local changes intact.
- Do not commit or push unless the user explicitly requests it.
