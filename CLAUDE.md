# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**antigravity-nix** is an auto-updating Nix Flake that packages Google Antigravity (a proprietary agentic IDE) for NixOS systems. It uses direct API requests to detect new versions and automatically creates PRs with updates daily at 07:00 UTC.

**Key Challenge**: Antigravity is a binary distribution that requires a standard Linux filesystem layout, which conflicts with NixOS's unique structure. This is solved using `buildFHSEnv` to create an isolated FHS environment.

## Architecture

### Four Components

This flake packages four components, matching the four downloads listed on
`antigravity.google/download` (Desktop app, CLI, IDE, SDK):

1. **Antigravity 2.0 / Desktop app** (`google-antigravity` / `default` / `google-antigravity-desktop`): the standalone, agent-orchestration desktop app — no IDE required. `google-antigravity-desktop` is a pure alias of `google-antigravity`/`default` (same derivation), added for discoverability against Google's own branding.
2. **Antigravity IDE** (`google-antigravity-ide`): The full IDE (IDE-only package)
3. **Antigravity CLI** (`google-antigravity-cli`): The `agy` CLI tool
4. **IDE + CLI Bundle** (`google-antigravity-ide-with-cli`): Installs both together
5. **Antigravity SDK** (`google-antigravity-sdk`, optional): Python library (`pip install google-antigravity`, imported as `google.antigravity`) for building custom Antigravity/Gemini agents. Architecturally distinct from the other three — see below.

**These are four genuinely separate upstream sources**, not variations of one
artifact:

| Component | Upstream source |
|---|---|
| Desktop (`google-antigravity` / `default` / `google-antigravity-desktop`) | `storage.googleapis.com/antigravity-public/antigravity-hub` |
| IDE (`google-antigravity-ide`) | `edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable` |
| CLI (`google-antigravity-cli`) | `antigravity-cli-auto-updater-*.run.app` Cloud Run manifest — same endpoint as Google's official `curl \| bash` installer at `antigravity.google/cli/install.sh` |
| SDK (`google-antigravity-sdk`, optional) | PyPI `google-antigravity` — same project as `github.com/google-antigravity/antigravity-sdk-python` |

## The version source of truth is the download page

**`https://antigravity.google/download` is authoritative. Check it every time
this repo is touched, and always before updating a pin.**

The Cloud Run `/releases` endpoints are convenient but not trustworthy. The
Desktop one served a **2026-05-19** build for months while the page linked
2.3.1 (2026-07-16) and then 2.8.1 (2026-08-13). Trusting it once downgraded
this flake's Desktop pin by two releases. `scripts/update-version.sh` therefore
resolves the Desktop version by scraping the page, not by querying that
endpoint.

Read the page correctly — it carries two different kinds of number, and only
one of them is evidence:

| On the page | Meaning | Trust for pinning? |
|---|---|---|
| A `storage.googleapis.com/...` or `edgedl...` **artifact URL** | the file users actually download | **Yes** |
| A `v1.2.3` label linking to `/changelog?tab=...` | marketing/changelog copy, can lag the shipped artifact by a day or more | **No** |

The CLI is exactly that trap: the page shows `v1.1.14` as a changelog link and
links **no CLI artifact at all**, while the CLI manifest endpoint serves a real
1.1.15 URL. Checked against `Last-Modified`, 1.1.15 (2026-08-19) is genuinely
newer than 1.1.14 (2026-08-18), so for the CLI the endpoint is right and the
page's number is not a download reference. Per-component sources stay as the
table above says.

**`Last-Modified` on the artifact settles any disagreement.** It is the only
signal here that actually orders builds:

```sh
curl -sI "https://storage.googleapis.com/antigravity-public/antigravity-hub/<ver>/linux-x64/Antigravity.tar.gz" \
  | grep -i '^last-modified'
```

**The execution id is NOT a recency signal.** It looks like a monotonic build
counter and is not one. Counter-example from this repo's own history: Desktop
`2.0.0-6324554176528384` has a *higher* id than `2.3.1-5358163105546240` and
was built two months *earlier*. Compare semver, or compare `Last-Modified` —
never the id.

Fetching the page needs `curl --compressed`: it is served brotli/gzip, and
without that flag the body is binary and every `grep` silently finds nothing.

Verified directly: the URLs on `antigravity.google/download` for Desktop and
IDE share the exact same bucket/host as the URLs already pinned in
`artifacts/versions.json` — only the version number differs (the pinned one
is simply older, refreshed by the daily auto-update workflow). This is not two
different packagings of the same thing; each of the four is its own download
surface, always has been, and this flake packages all four independently.

**No output installs all four together.** Each component is a separate package
with no bundling beyond `google-antigravity-ide-with-cli` (IDE + CLI only, via
`symlinkJoin` — see `pkgs/google-antigravity-ide-with-cli.nix`). A consumer must
list every package they want explicitly in `environment.systemPackages` /
`home.packages` / wherever the overlay is consumed. The SDK in particular is
enabled/disabled purely by whether `google-antigravity-sdk` appears in that
list — there is no internal flag or option gating it.

### Package Layout

- `artifacts/versions.json`: Source-of-truth JSON holding resolved URLs and SRI hashes for every component and platform
- `pkgs/package.nix`: Shared GUI packaging logic (supports both Desktop app and IDE via `appType` parameter)
- `pkgs/google-antigravity2.nix`: Entry point for the Desktop app (`appType = "Antigravity 2.0"`)
- `pkgs/google-antigravity-ide.nix`: Entry point for the IDE (IDE-only)
- `pkgs/google-antigravity-ide-with-cli.nix`: Entry point for IDE + CLI bundle
- `pkgs/cli.nix`: CLI package derivation
- `pkgs/sdk.nix`: SDK package derivation — a `python3Packages.buildPythonPackage` (`format = "wheel"`) wrapping a prebuilt PyPI wheel, **not** built from `pkgs/package.nix`'s GUI logic. Its `callPackage` must go through `pkgs.python3Packages.callPackage`, not `pkgs.callPackage`, since `buildPythonPackage` lives in that scope.

### Two-Stage GUI Build Process

For each GUI app (Base App and IDE):

1. **`antigravity-unwrapped`**: Extracts the upstream tarball into `/nix/store` without modification
2. **FHS Environment** (or autoPatchelf): Wraps the binary in a container with standard Linux paths and all required libraries

### Chrome Integration Strategy

Antigravity GUI apps require Chrome to be available. The `pkgs/package.nix` wrapper:
- Forces use of the user's existing Chrome profile (`~/.config/google-chrome`)
- Ensures any Chrome extensions the user has installed are available to Antigravity
- Sets `CHROME_BIN` and `CHROME_PATH` environment variables

### Version Detection Architecture

The update workflow uses API requests (via `curl` and `jq`) to Google Cloud Run endpoints to fetch the latest builds:

- `scripts/check-version.sh`: Quick API queries to determine if any component has an update
- `scripts/update-version.sh`: Full update process (version + hash verification via `nix-prefetch-url`)
- `artifacts/versions.json`: The source-of-truth JSON dictionary holding resolved URLs and SRI hashes for every component and platform

**Important**: Web scraping via Playwright has been completely removed in favor of direct API interaction.

**SDK is the exception**: the Antigravity SDK ships only via PyPI, not one of Google's
Cloud Run auto-updater endpoints, so both scripts query `https://pypi.org/pypi/google-antigravity/json`
directly for it instead — a separate, bespoke block in each script (same reasoning
that already gives Antigravity CLI its own bespoke block in `update-version.sh`,
since its manifest shape also differs from the Base App/IDE "releases" JSON).
PyPI exposes each wheel's `sha256` digest directly, so no `nix-prefetch-url` step
is needed for it, just a hex→SRI conversion via `nix hash convert`. There is
currently no `x86_64-darwin` (Intel Mac) wheel published upstream at all, so that
platform is simply absent from `versions.json`'s `"Antigravity SDK"` entry and
`pkgs/sdk.nix` throws a clear error for it.

## Common Commands

### Building and Testing

```bash
# Build the default package (Base App)
nix build .#default

# Test run without installing
nix run .#default

# Build and check flake
nix flake check

# Build the CLI
nix build .#google-antigravity-cli

# Build the optional SDK (Python package, x86_64-linux / aarch64-linux / aarch64-darwin only)
nix build .#google-antigravity-sdk
```

### Version Management

```bash
# Enter the dev shell with necessary tools (jq, curl, gh)
nix develop

# Check for new version (no changes)
./scripts/check-version.sh

# Update to latest version (modifies versions.json, builds, commits)
./scripts/update-version.sh
```

### GitHub Workflows

**Manual triggers via `gh` CLI**:

```bash
# Manually trigger update workflow
gh workflow run update.yml

# View workflow runs
gh run list --workflow=update.yml
gh run view <run-id>
```

## Important Implementation Details

### Hash Updates

When updating versions in `artifacts/versions.json`, hashes must be converted to SRI format:

1. Download with `nix-prefetch-url` to get the base hash
2. Convert to SRI format with `nix hash to-sri`
3. Update `artifacts/versions.json` with the SRI hash (`sha256-...` or `sha512-...`)

**Never** use fake/placeholder hashes - the build will fail and CI won't catch it until runtime.

### FHS Environment Dependencies

The `targetPkgs` list in `pkgs/package.nix` includes all libraries the GUI apps need. If adding new dependencies:

- Include both the library and its transitive dependencies
- Add X11 libraries with `xorg.` prefix
- Include `stdenv.cc.cc.lib` for C++ standard library
- Test on a minimal NixOS system, not just your development machine

### Workflow Integration

The three workflows work together:

1. **update.yml**: Runs daily at 07:00 UTC, creates PRs, enables auto-merge
2. **release.yml**: Triggers on `artifacts/versions.json` changes to main, creates GitHub releases
3. **cleanup-branches.yml**: Deletes merged `auto-update/*` branches

**Release workflow** (release.yml) only runs when:
- `artifacts/versions.json` is modified
- Release tag doesn't already exist

## Testing Checklist

Before committing changes to packaging:

```bash
# 1. Verify build succeeds
nix build .#default --rebuild

# 2. Test the binary runs
./result/bin/antigravity --version

# 3. Verify flake metadata
nix flake metadata

# 4. Check for evaluation errors
nix flake check

# 5. Test CLI
nix run .#google-antigravity-cli -- --version
```

## Common Issues

### "Could not find Chrome" errors

The FHS wrapper sets `CHROME_BIN`/`CHROME_PATH` to a wrapper script, not the actual Chrome binary. If Antigravity can't find Chrome:

1. Verify `google-chrome` is in system packages
2. Check the wrapper script path in `pkgs/package.nix`
3. Test: `CHROME_BIN=/path/to/wrapper /path/to/wrapper --version`

### Workflow doesn't create PR

Check GitHub Actions logs. Common causes:

1. Version hasn't changed (intentional - exits cleanly)
2. Build failed (hash mismatch or missing dependencies)
3. Permissions issue (workflow needs `contents: write`)

## Updating This Package

### For New Antigravity Versions

The automated workflow handles this. To manually update:

```bash
./scripts/update-version.sh
# Review output, commit if successful
git push
```

The SDK (pre-1.0, currently `0.1.7`) is auto-updated the same as the other
components, but since it's higher-risk than the stable GUI/CLI/IDE products,
`nix build .#google-antigravity-sdk` must succeed before its update PR is
created/auto-merged — verify this build-gate is wired into `update.yml` when
touching that workflow.

### For Packaging Changes

When modifying `pkgs/*.nix` or `flake.nix`:

1. Test locally with multiple build approaches (FHS and no-FHS)
2. Verify the FHS environment includes all necessary libraries
3. Test with `nix run .#default` on a clean NixOS VM if possible
4. Check that the desktop entry works (`antigravity-ide` or `antigravity` command)

### For Workflow Changes

When modifying `.github/workflows/*.yml`:

1. Test with `gh workflow run <workflow>.yml`
2. Check workflow syntax: `gh workflow view <workflow>.yml`
3. Monitor with `gh run list --workflow=<workflow>.yml`
4. Validate secrets/permissions are correct
