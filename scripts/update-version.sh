#!/usr/bin/env nix-shell
#!nix-shell -i bash -p jq curl

set -euo pipefail

cd "$(dirname "$0")/.."

OUTPUT_JSON="artifacts/versions.json"

log_info() { echo -e "\033[0;32m[INFO]\033[0m $*" >&2; }
log_error() { echo -e "\033[0;31m[ERROR]\033[0m $*" >&2; }

mkdir -p artifacts
if [[ ! -f "$OUTPUT_JSON" ]]; then
    echo "{}" > "$OUTPUT_JSON"
fi

log_info "Fetching IDE/App latest versions..."
APP_VER=$(curl -sL "https://antigravity-auto-updater-974169037036.us-central1.run.app/releases" | jq -r '.[0] | .version + "-" + .execution_id')
IDE_VER=$(curl -sL "https://antigravity-ide-auto-updater-974169037036.us-central1.run.app/releases" | jq -r '.[0] | .version + "-" + .execution_id')

if [[ -z "$APP_VER" || "$APP_VER" == "null-null" ]]; then log_error "Failed to fetch App version"; exit 1; fi
if [[ -z "$IDE_VER" || "$IDE_VER" == "null-null" ]]; then log_error "Failed to fetch IDE version"; exit 1; fi

get_hash() {
    local url=$1
    local name_arg=$2
    if [[ -n "$name_arg" ]]; then
        nix-prefetch-url --type sha256 --name "$name_arg" "$url" || echo ""
    else
        nix-prefetch-url --type sha256 "$url" || echo ""
    fi
}

to_sri() {
    local hash=$1
    if [[ -n "$hash" ]]; then
        nix hash to-sri --type sha256 "$hash"
    else
        echo ""
    fi
}

process_app() {
    local name="$1"
    local version="$2"
    local base_url="$3"
    local is_ide="$4"

    # Check existing version
    local current_url=$(jq -r ".\"$name\".\"x86_64-linux\".url" "$OUTPUT_JSON" 2>/dev/null || echo "null")
    if [[ "$current_url" != "null" ]]; then
        local current_version=$(echo "$current_url" | grep -oP '[0-9]+\.[0-9]+\.[0-9]+-[0-9]+' || echo "unknown")
        if [[ "$current_version" == "$version" ]]; then
            log_info "$name is already at latest version ($version). Skipping download..."
            return 0
        fi
    fi

    log_info "Updating $name to $version..."

    # Define standard platforms mapping
    local platforms=(
        "x86_64-linux:linux-x64:Antigravity${is_ide:+%20IDE}.tar.gz"
        "aarch64-linux:linux-arm:Antigravity${is_ide:+%20IDE}.tar.gz"
        "x86_64-darwin:darwin-x64:Antigravity${is_ide:+%20IDE}.dmg"
        "aarch64-darwin:darwin-arm:Antigravity${is_ide:+%20IDE}.dmg"
    )

    local jq_payload="{}"

    for plat in "${platforms[@]}"; do
        IFS=':' read -r nix_os api_os filename <<< "$plat"
        log_info "Fetching hash for $name on $nix_os..."
        local url="${base_url}/${version}/${api_os}/${filename}"

        # Always provide a safe name to avoid illegal characters (like %20) in the Nix store path
        local current_name_arg=""
        if [[ "$is_ide" == "true" ]]; then
            if [[ "$nix_os" == *linux* ]]; then
                current_name_arg="Antigravity_IDE.tar.gz"
            else
                current_name_arg="Antigravity_IDE.dmg"
            fi
        fi

        local hash=$(get_hash "$url" "$current_name_arg")
        local sri_hash=$(to_sri "$hash")

        if [[ -z "$sri_hash" ]]; then
            log_error "Failed to get hash for $url"
            exit 1
        fi

        jq_payload=$(echo "$jq_payload" | jq --arg plat "$nix_os" --arg url "$url" --arg hash "$sri_hash" \
            '.[$plat] = {url: $url, hash: $hash}')
    done

    local tmp_json=$(mktemp)
    jq --arg name "$name" --argjson payload "$jq_payload" '.[$name] = $payload' "$OUTPUT_JSON" > "$tmp_json"
    mv "$tmp_json" "$OUTPUT_JSON"
}

process_app "Antigravity 2.0" "$APP_VER" "https://storage.googleapis.com/antigravity-public/antigravity-hub" ""
process_app "Antigravity IDE" "$IDE_VER" "https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable" "true"

# Antigravity SDK is distributed only via PyPI (pip install google-antigravity),
# not one of Google's Cloud Run auto-updater endpoints, so it needs its own
# bespoke block (closest existing analog is the CLI block below: the manifest
# already exposes a hash directly, so no nix-prefetch-url is needed here either).
# NOTE: placed before the CLI section on purpose, since CLI has an early
# `exit 0` below when it's already up to date, which would otherwise skip this.
log_info "Fetching Antigravity SDK latest version from PyPI..."
SDK_JSON=$(curl -sL "https://pypi.org/pypi/google-antigravity/json" || echo "")
SDK_LATEST_VER=$(echo "$SDK_JSON" | jq -r '.info.version' 2>/dev/null || echo "")

if [[ -z "$SDK_LATEST_VER" || "$SDK_LATEST_VER" == "null" ]]; then
    log_error "Failed to fetch Antigravity SDK version from PyPI"
    exit 1
fi

SDK_CURRENT_URL=$(jq -r '."Antigravity SDK"."x86_64-linux".url' "$OUTPUT_JSON" 2>/dev/null || echo "null")
SDK_UP_TO_DATE=false
if [[ "$SDK_CURRENT_URL" != "null" ]]; then
    SDK_CURRENT_VER=$(echo "$SDK_CURRENT_URL" | grep -oP 'google_antigravity-\K[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
    if [[ "$SDK_CURRENT_VER" == "$SDK_LATEST_VER" ]]; then
        SDK_UP_TO_DATE=true
    fi
fi

if [[ "$SDK_UP_TO_DATE" == "true" ]]; then
    log_info "Antigravity SDK is already at latest version ($SDK_LATEST_VER). Skipping..."
else
    log_info "Updating Antigravity SDK to $SDK_LATEST_VER..."

    # Map PyPI wheel platform tags to Nix systems. win_amd64/win_arm64 have no
    # matching Nix system (expected, not an error). There is currently no
    # x86_64-darwin (Intel Mac) wheel published at all, so that platform stays
    # absent from versions.json and pkgs/sdk.nix throws a clear error for it.
    sdk_payload="{}"
    sdk_matched=0

    while IFS=$'\t' read -r plat_tag file_url sha256_hex; do
        case "$plat_tag" in
            manylinux*_x86_64) nix_os="x86_64-linux" ;;
            manylinux*_aarch64) nix_os="aarch64-linux" ;;
            macosx*_arm64) nix_os="aarch64-darwin" ;;
            macosx*_x86_64) nix_os="x86_64-darwin" ;;
            win_amd64|win_arm64)
                log_info "Skipping SDK wheel for $plat_tag (no matching Nix system)"
                continue
                ;;
            *)
                log_info "Skipping unrecognized Antigravity SDK wheel platform tag: $plat_tag"
                continue
                ;;
        esac

        sri_hash=$(to_sri "$sha256_hex")
        if [[ -z "$sri_hash" ]]; then
            log_error "Failed to convert Antigravity SDK hash for $plat_tag"
            exit 1
        fi

        sdk_payload=$(echo "$sdk_payload" | jq --arg plat "$nix_os" --arg url "$file_url" --arg hash "$sri_hash" \
            '.[$plat] = {url: $url, hash: $hash}')
        sdk_matched=$((sdk_matched + 1))
    done < <(echo "$SDK_JSON" | jq -r '.urls[] | select(.packagetype=="bdist_wheel") | [(.filename | capture("py3-none-(?<tag>.+)\\.whl").tag), .url, .digests.sha256] | @tsv')

    if [[ "$sdk_matched" -eq 0 ]]; then
        log_error "No usable Antigravity SDK wheels found for any supported Nix system"
        exit 1
    fi

    tmp_json=$(mktemp)
    jq --argjson payload "$sdk_payload" '.["Antigravity SDK"] = $payload' "$OUTPUT_JSON" > "$tmp_json"
    mv "$tmp_json" "$OUTPUT_JSON"
fi

log_info "Fetching CLI latest versions..."

# Get CLI latest version to check if we can skip
CLI_LATEST_URL=$(curl -sL "https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/linux_amd64.json" | jq -r '.url' || echo "")
CLI_LATEST_VER=$(echo "$CLI_LATEST_URL" | grep -oP 'antigravity-cli/\K[0-9.]+-[0-9]+' || echo "")

if [[ -n "$CLI_LATEST_VER" ]]; then
    CLI_CURRENT_URL=$(jq -r '."Antigravity CLI"."x86_64-linux".url' "$OUTPUT_JSON" 2>/dev/null || echo "null")
    if [[ "$CLI_CURRENT_URL" != "null" ]]; then
        CLI_CURRENT_VER=$(echo "$CLI_CURRENT_URL" | grep -oP 'antigravity-cli/\K[0-9.]+-[0-9]+' || echo "unknown")
        if [[ "$CLI_CURRENT_VER" == "$CLI_LATEST_VER" ]]; then
            log_info "Antigravity CLI is already at latest version ($CLI_LATEST_VER). Skipping download..."
            log_info "Done! $OUTPUT_JSON is up to date."
            exit 0
        fi
    fi
fi

log_info "Updating Antigravity CLI..."
cli_payload="{}"

CLI_PLATFORMS=(
    "x86_64-linux:linux_amd64"
    "aarch64-linux:linux_arm64"
    "x86_64-darwin:darwin_amd64"
    "aarch64-darwin:darwin_arm64"
)

for plat in "${CLI_PLATFORMS[@]}"; do
    IFS=':' read -r nix_os api_os <<< "$plat"
    log_info "Fetching CLI manifest for $nix_os..."
    manifest_url="https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/${api_os}.json"
    manifest_json=$(curl -sL "$manifest_url" || echo "")

    if [[ -z "$manifest_json" ]]; then
        log_error "Failed to fetch manifest: $manifest_url"
        exit 1
    fi

    url=$(echo "$manifest_json" | jq -r '.url')
    hash=$(echo "$manifest_json" | jq -r '.sha512')
    sri_hash="sha512-$hash"

    cli_payload=$(echo "$cli_payload" | jq --arg plat "$nix_os" --arg url "$url" --arg hash "$sri_hash" \
        '.[$plat] = {url: $url, hash: $hash}')
done

tmp_json=$(mktemp)
jq --argjson payload "$cli_payload" '.["Antigravity CLI"] = $payload' "$OUTPUT_JSON" > "$tmp_json"
mv "$tmp_json" "$OUTPUT_JSON"

log_info "Done! Updated $OUTPUT_JSON"
