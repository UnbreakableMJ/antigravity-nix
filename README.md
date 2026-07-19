# antigravity-nix

Auto-updating Nix Flake for Google Antigravity -- zero configuration, multi-platform, version-pinned.

[![Update Antigravity](https://github.com/UnbreakableMJ/antigravity-nix/actions/workflows/update.yml/badge.svg)](https://github.com/UnbreakableMJ/antigravity-nix/actions/workflows/update.yml)
[![Flake Check](https://img.shields.io/badge/flake-check%20passing-success)](https://github.com/UnbreakableMJ/antigravity-nix)
[![NixOS](https://img.shields.io/badge/NixOS-ready-blue?logo=nixos)](https://nixos.org)

## What This Provides

- **Four Components**: Packages for Antigravity 2.0 (the standalone Desktop app, also available as `google-antigravity-desktop`), Antigravity CLI (`agy`), Antigravity IDE, and the optional Antigravity SDK (Python package).
- **FHS environment** wrapping the upstream GUI binaries with all required libraries.
- **Automated updates** via GitHub Actions (daily at 0700 UTC), with hash verification and build testing.
- **Multi-platform** support for x86_64-linux, aarch64-linux, x86_64-darwin, and aarch64-darwin.
- **Version pinning** through tagged releases for reproducible builds.

### Sourcing — where each component actually comes from

These are four genuinely separate upstream download sources, not variations of
the same artifact — each package fetches from a different Google-owned
endpoint, matching exactly what `antigravity.google/download` links to:

| Component | Flake output(s) | Upstream source |
|---|---|---|
| Desktop (agent-orchestration, standalone) | `google-antigravity` / `default` / `google-antigravity-desktop` | `storage.googleapis.com/antigravity-public/antigravity-hub` |
| IDE (VS Code-based fork) | `google-antigravity-ide` | `edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable` |
| CLI (`agy`) | `google-antigravity-cli` | `antigravity-cli-auto-updater-*.run.app` Cloud Run manifest — the same endpoint Google's own `curl -fsSL https://antigravity.google/cli/install.sh \| bash` installer uses |
| SDK (optional, Python library) | `google-antigravity-sdk` | PyPI package `google-antigravity` — same project as `github.com/google-antigravity/antigravity-sdk-python` |

## Quick Start

Run the Antigravity 2.0 Desktop app (default; `google-antigravity-desktop` is an alias for the same package):
```bash
nix run github:UnbreakableMJ/antigravity-nix
```

Run the Antigravity IDE:
```bash
nix run github:UnbreakableMJ/antigravity-nix#google-antigravity-ide
```

Run the CLI tool (`agy`):
```bash
nix run github:UnbreakableMJ/antigravity-nix#google-antigravity-cli
```

Run IDE + CLI together:
```bash
nix run github:UnbreakableMJ/antigravity-nix#google-antigravity-ide-with-cli
```

Build the optional SDK (a Python library for building custom Antigravity/Gemini agents, not a runnable app):
```bash
nix build github:UnbreakableMJ/antigravity-nix#google-antigravity-sdk
```

## Installation

**Each component is a separate, independent package.** There is no single output
that installs the Desktop app + IDE + CLI + SDK together automatically — not
even `google-antigravity-ide-with-cli`, which only bundles the IDE and CLI. To
install any combination, list each package explicitly in `environment.systemPackages`
(NixOS), `home.packages` (Home Manager), or wherever you consume the overlay, as
shown below. Installing the Desktop app (`default` / `google-antigravity`) does
**not** pull in the IDE, CLI, or SDK, and vice versa.

The **SDK is opt-in** the same way: it's just another package
(`google-antigravity-sdk` / `pkgs.google-antigravity-sdk` via the overlay). Add
it to your package list to install it; omit it (or remove the line) to skip it.
There's no separate flag or toggle inside the flake — Nix package lists are the
on/off switch.

### NixOS Configuration

Add to your `flake.nix`:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    antigravity-nix = {
      url = "github:UnbreakableMJ/antigravity-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, antigravity-nix, ... }: {
    nixosConfigurations.your-hostname = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        {
          environment.systemPackages = [
            antigravity-nix.packages.x86_64-linux.default # Desktop app (a.k.a. google-antigravity-desktop)
            antigravity-nix.packages.x86_64-linux.google-antigravity-ide # IDE only
            antigravity-nix.packages.x86_64-linux.google-antigravity-cli # CLI only (agy)
            antigravity-nix.packages.x86_64-linux.google-antigravity-ide-with-cli # IDE + CLI together
            antigravity-nix.packages.x86_64-linux.google-antigravity-sdk # SDK (optional, Python package)
          ];
        }
      ];
    };
  };
}
```

### Home Manager

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    antigravity-nix = {
      url = "github:UnbreakableMJ/antigravity-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, antigravity-nix, ... }: {
    homeConfigurations.your-user = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      modules = [
        {
          home.packages = [
            antigravity-nix.packages.x86_64-linux.default # Desktop app (a.k.a. google-antigravity-desktop)
            antigravity-nix.packages.x86_64-linux.google-antigravity-ide
            antigravity-nix.packages.x86_64-linux.google-antigravity-cli
            antigravity-nix.packages.x86_64-linux.google-antigravity-ide-with-cli
            antigravity-nix.packages.x86_64-linux.google-antigravity-sdk # SDK (optional, Python package)
          ];
        }
      ];
    };
  };
}
```

### Overlay

```nix
{
  nixpkgs.overlays = [
    inputs.antigravity-nix.overlays.default
  ];

  environment.systemPackages = with pkgs; [
    google-antigravity # a.k.a. google-antigravity-desktop
    google-antigravity-ide
    google-antigravity-cli
    google-antigravity-ide-with-cli
    google-antigravity-sdk # optional
  ];
}
```

## Package Variants

For the GUI applications (`google-antigravity` and `google-antigravity-ide`), two packaging strategies are available:

| Variant | Strategy | Trade-off |
|---|---|---|
| `default` / `google-antigravity` | `buildFHSEnv` + bubblewrap | Sandboxed, but inherits `no_new_privileges` restrictions |
| `google-antigravity-no-fhs` | `autoPatchelfHook` | No sandbox, full system integration |

The **default** uses `buildFHSEnv` to create an isolated FHS environment via bubblewrap. This is the most compatible approach, but the sandbox sets the kernel's `no_new_privileges` flag, which prevents privilege escalation (`sudo`, `pkexec`) and can cause issues with nested namespaces.

The **no-fhs** variant uses `autoPatchelfHook` to patch ELF binaries directly, the same approach used by VS Code in nixpkgs. It runs natively on NixOS without sandboxing.

```nix
# Use the no-fhs variant
home.packages = [
  antigravity-nix.packages.${system}.google-antigravity-no-fhs
  antigravity-nix.packages.${system}.google-antigravity-ide-no-fhs
];
```

Or via override:

```nix
google-antigravity.override { useFHS = false; }
```

### Chrome Profile Isolation

By default, Antigravity GUI apps use your system Chrome profile (`~/.config/google-chrome`), giving access to your installed extensions. To run with an isolated Chrome profile instead (e.g., when testing untrusted apps):

```nix
google-antigravity.override { useSystemChromeProfile = false; }
```

This omits the `--user-data-dir` and `--profile-directory` flags, letting Chrome manage its own profile independently. Works with both FHS and non-FHS variants.

## Usage

```bash
antigravity                  # launch Antigravity Base App
antigravity-ide              # launch Antigravity IDE
agy                          # use the Antigravity CLI
```

## Version Pinning

```nix
# Follow latest (recommended)
inputs.antigravity-nix.url = "github:UnbreakableMJ/antigravity-nix";

# Pin to a specific release
inputs.antigravity-nix.url = "github:UnbreakableMJ/antigravity-nix/v2.0.3-6242596486512640";
```

Update to the latest version:

```bash
nix flake update antigravity-nix
```

All releases: https://github.com/UnbreakableMJ/antigravity-nix/releases

## Troubleshooting

### IDE Freezes on Close (Known Upstream Issue)

The Antigravity IDE currently has a known bug across all Linux distributions (not just NixOS) where it may freeze the system upon closing. As a workaround, you can force-kill the process immediately *after* closing the window to prevent the freeze (do not run this before closing, or your work may not be saved):

```bash
kill -9 $(pgrep -f antigravity-ide)
```

### `fetchurl` fails or hash mismatches

If the default `fetchurl` path fails — Google CDN unreachable, regional restrictions, hash drift after an upstream republish, corporate firewall — you can supply the tarball locally via `srcOverride`:

1. Download the respective tarball from Antigravity.
2. Point the package at it:

```nix
(antigravity-nix.packages.${system}.default.override {
  srcOverride = /absolute/path/to/Antigravity.tar.gz;
})
```

This bypasses `fetchurl` while keeping the rest of the packaging (FHS wrapping, Chrome integration, desktop entry) intact. No `--impure` and no patching required. Works for both the `default` and `no-fhs` variants.

### Antigravity SDK

`google-antigravity-sdk` packages the `google-antigravity` PyPI library (`pip install google-antigravity`) — a Python SDK for building custom agents on Antigravity and Gemini, imported as `google.antigravity`. Unlike the other three components, it is sourced directly from PyPI rather than Google's Cloud Run auto-updater endpoints, since that's the only place it's published. It's supported on `x86_64-linux`, `aarch64-linux`, and `aarch64-darwin` — there is currently no `x86_64-darwin` (Intel Mac) wheel published upstream, so that platform is unsupported until Google ships one.

## Requirements

- Nix with flakes enabled
- `allowUnfree = true` (Antigravity is proprietary software)
- On `aarch64-linux`, Chromium is used automatically since Google Chrome is unavailable

## Contributors

| Contributor | Role |
|---|---|
| [jacopone](https://github.com/jacopone) | Original author |
| [UnbreakableMJ](https://github.com/UnbreakableMJ) | Maintainer |
| [Claude](https://claude.ai) (Anthropic) | AI contributor — code review, packaging improvements, documentation |

## Contributing

1. Fork the repository
2. Create a feature branch
3. Test with `nix build` and `nix flake check`
4. Submit a pull request

## License

MIT License -- see [LICENSE](LICENSE) for details.

Google Antigravity is proprietary software by Google LLC. This is an unofficial package, not affiliated with or endorsed by Google.
