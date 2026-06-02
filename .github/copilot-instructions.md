# Copilot Instructions for antigravity-nix

## Project Overview

**antigravity-nix** is an auto-updating Nix Flake that packages Google Antigravity (a proprietary agentic IDE) for NixOS and macOS systems. It uses direct API requests to detect new versions and automatically creates PRs with updates daily at 07:00 UTC.

**Key Challenge**: Antigravity is a binary distribution that requires a standard Linux filesystem layout, which conflicts with NixOS's unique filesystem structure. This is solved using `buildFHSEnv` to create an isolated FHS (Filesystem Hierarchy Standard) environment via bubblewrap.

---

## Repository Structure

```
.
├── flake.nix                    # Flake entry point – defines all packages, devShell, and overlay
├── flake.lock                   # Locked input revisions for reproducibility
├── artifacts/
│   └── versions.json            # Source-of-truth: resolved download URLs and SRI hashes per component and platform
├── pkgs/
│   ├── package.nix              # Shared GUI packaging logic (supports Base App and IDE via `appType` parameter)
│   ├── google-antigravity2.nix  # Entry point for Antigravity 2.0 (Base App); passes appType = "Antigravity 2.0"
│   ├── google-antigravity-ide.nix # Entry point for Antigravity IDE (IDE-only)
│   ├── google-antigravity-ide-with-cli.nix # Optional bundle entry point (IDE + CLI)
│   └── cli.nix                  # CLI tool (`agy`) derivation
├── scripts/
│   ├── check-version.sh         # Queries Google Cloud Run endpoints to check if a new version is available
│   └── update-version.sh        # Full update: fetches latest URLs, downloads, computes SRI hashes, updates versions.json
└── .github/
    └── workflows/
        ├── update.yml           # Daily auto-update workflow: runs update-version.sh and opens a PR
        ├── release.yml          # Triggers on versions.json changes to main; creates GitHub releases
        └── cleanup-branches.yml # Deletes merged auto-update/* branches
```

---

## Three Packaged Components

| Flake output | Description | Binary |
|---|---|---|
| `default` / `google-antigravity` | Antigravity 2.0 Base App | `antigravity` |
| `google-antigravity-ide` | Full IDE (IDE only) | `antigravity-ide` |
| `google-antigravity-cli` | CLI tool | `agy` |
| `google-antigravity-ide-with-cli` | IDE + CLI bundle | `antigravity-ide`, `agy` |

Each component supports `x86_64-linux`, `aarch64-linux`, `x86_64-darwin`, and `aarch64-darwin`.

---

## Build Architecture

### Two-Stage GUI Build

1. **`antigravity-unwrapped`** (`stdenv.mkDerivation`): Extracts the upstream tarball into `/nix/store` without modification. Patches `@vscode/sudo-prompt` paths using `asar`.
2. **FHS wrapper** (`buildFHSEnv`): Creates an isolated bubblewrap container with all required libraries, sets `CHROME_BIN`/`CHROME_PATH` to a wrapper script, and launches the binary.

A **no-FHS variant** (`useFHS = false`) uses `autoPatchelfHook` instead of `buildFHSEnv`. This avoids the bubblewrap `no_new_privileges` restriction, allowing `sudo` to work inside the integrated terminal.

### Darwin Package

On macOS, a simpler `stdenv.mkDerivation` using `undmg` extracts the `.dmg` and copies the `.app` to `$out/Applications/`.

---

## Version Management

- **`artifacts/versions.json`**: The single source of truth. Holds download URLs and SRI hashes for every component × platform combination.
- **`scripts/check-version.sh`**: Quick API query (curl + jq) against Google Cloud Run endpoints to detect if any component has a new version.
- **`scripts/update-version.sh`**: Downloads the new release, computes SRI hashes via `nix-prefetch-url` + `nix hash to-sri`, and writes the updated URLs/hashes back to `versions.json`.

**Hash format**: Always use SRI format (`sha256-...` or `sha512-...`). Never use bare hex hashes or placeholder values.

---

## Coding Conventions

### Nix Style
- Use `lib.optionalString` for conditional string fragments.
- Use `lib.optional` for conditional list items.
- Prefer `let … in` blocks for named intermediate values.
- Use `pkgs.callPackage ./pkgs/foo.nix {}` for package instantiation in `flake.nix`.
- Keep `meta` attributes complete: `description`, `homepage`, `license`, `platforms`, `mainProgram`.
- Attribute names use camelCase (e.g., `appType`, `useFHS`, `srcOverride`).
- Parameters with defaults use `? value` syntax (e.g., `useFHS ? true`).

### Shell Scripts
- All scripts use `#!/usr/bin/env bash` and `set -euo pipefail`.
- Use `nix-shell -p <tools>` shebangs when tools (jq, curl) are not guaranteed in PATH.
- API communication uses `curl` + `jq`; no Playwright or browser automation.

### versions.json
- Top-level keys are human-readable component names: `"Antigravity 2.0"`, `"Antigravity IDE"`, `"Antigravity CLI"`.
- Platform keys match Nix system strings: `"x86_64-linux"`, `"aarch64-linux"`, `"x86_64-darwin"`, `"aarch64-darwin"`.
- Each entry has exactly two fields: `"url"` and `"hash"`.

---

## How to Build and Run

### Prerequisites
- Nix with flakes enabled (`experimental-features = nix-command flakes` in `~/.config/nix/nix.conf` or `/etc/nix/nix.conf`)
- `nixpkgs.config.allowUnfree = true` (Antigravity is proprietary)
- `google-chrome-stable` installed system-wide (on `x86_64-linux`; `aarch64-linux` uses Chromium automatically)

### Build Commands

```bash
# Build the default package (Antigravity 2.0 Base App)
nix build .#default

# Build the IDE
nix build .#google-antigravity-ide

# Build the CLI
nix build .#google-antigravity-cli

# Build the no-FHS variant
nix build .#google-antigravity-no-fhs

# Check flake for evaluation errors
nix flake check

# Run without installing
nix run .#default
nix run .#google-antigravity-ide
nix run .#google-antigravity-cli
```

### Development Shell

```bash
# Enter the dev shell (provides nix, git, curl, jq, gh)
nix develop
```

Inside the dev shell:

```bash
./scripts/check-version.sh   # Check if a new upstream version is available
./scripts/update-version.sh  # Download new version, compute hashes, update versions.json
```

### Testing Checklist

Before committing packaging changes:

1. `nix build .#default --rebuild` — verify the build succeeds from scratch
2. `./result/bin/antigravity --version` — confirm the binary runs
3. `nix flake check` — check for evaluation errors across all packages
4. `nix build .#google-antigravity-cli` — verify CLI builds
5. `nix flake metadata` — verify flake metadata is well-formed

There is no automated test suite. Validation is done by building and running the resulting binaries.

---

## GitHub Actions Workflows

| Workflow | Trigger | Purpose |
|---|---|---|
| `update.yml` | Daily 07:00 UTC + manual | Runs `update-version.sh`, opens auto-merge PR |
| `release.yml` | Push to `main` modifying `versions.json` | Creates a tagged GitHub release |
| `cleanup-branches.yml` | PR merge | Deletes merged `auto-update/*` branches |

Manually trigger a workflow:

```bash
gh workflow run update.yml
gh run list --workflow=update.yml
```

---

## Common Pitfalls

- **Never use fake/placeholder hashes** in `versions.json` — builds will fail silently or produce broken outputs.
- **`buildFHSEnv` sets `no_new_privileges`** — this prevents `sudo` inside the integrated terminal. Use the `no-fhs` variant if sudo support is needed.
- **Chrome is required on `x86_64-linux`** — the package throws at evaluation time if `google-chrome` is not passed and the system is not `aarch64-linux`.
- **`targetPkgs` in the FHS env** must include all transitive library dependencies. If adding a new library, include both it and its runtime dependencies.
