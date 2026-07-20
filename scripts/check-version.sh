#!/usr/bin/env nix-shell
#!nix-shell -i bash -p jq curl

set -euo pipefail

cd "$(dirname "$0")/.."

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "Checking Antigravity versions..."
echo ""

VERSIONS_JSON="artifacts/versions.json"

if [[ ! -f "$VERSIONS_JSON" ]]; then
    echo -e "${RED}Error: $VERSIONS_JSON not found. Run update-version.sh first!${NC}"
    exit 1
fi

# Extracts the bare "X.Y.Z" semver prefix from a version string that may carry
# a trailing "-<build/execution id>" suffix.
semver_only() {
    echo "$1" | grep -oP '^[0-9]+\.[0-9]+\.[0-9]+' || echo ""
}

# Returns 0 (true) if dotted version $1 is strictly less than dotted version $2.
version_lt() {
    local v1=$1 v2=$2
    [[ "$v1" == "$v2" ]] && return 1
    local IFS=.
    local -a a=($v1) b=($v2)
    for i in 0 1 2; do
        local ai=${a[i]:-0} bi=${b[i]:-0}
        if (( ai < bi )); then return 0; fi
        if (( ai > bi )); then return 1; fi
    done
    return 1
}

# Mirrors update-version.sh's is_downgrade guard, purely for accurate reporting
# here — this script never writes versions.json. Discovered in practice:
# Google's Cloud Run releases endpoint for the Desktop app reported a stale
# older version days after a newer one was already live upstream.
is_downgrade() {
    local current_semver=$(semver_only "$1") latest_semver=$(semver_only "$2")
    [[ -z "$current_semver" || -z "$latest_semver" ]] && return 1
    version_lt "$latest_semver" "$current_semver"
}

check_app() {
local name="$1"
local url="$2"

echo "--- $name ---"

local current
if [[ "$name" == "Antigravity CLI" ]]; then
local current_url=$(jq -r ".\"$name\".\"x86_64-linux\".url" "$VERSIONS_JSON" 2>/dev/null || echo "")
current=$(echo "$current_url" | grep -oP 'antigravity-cli/\K[0-9.]+-[0-9]+' || echo "unknown")
else
local current_url=$(jq -r ".\"$name\".\"x86_64-linux\".url" "$VERSIONS_JSON" 2>/dev/null || echo "")
current=$(echo "$current_url" | grep -oP '[0-9]+\.[0-9]+\.[0-9]+-[0-9]+' || echo "unknown")
fi

echo -e "Current version: $current"

local latest
if [[ "$name" == "Antigravity CLI" ]]; then
latest=$(curl -sL "$url" | jq -r '.url | match("antigravity-cli/([0-9.]+-[0-9]+)/").captures[0].string' 2>/dev/null || echo "")
else
latest=$(curl -sL "$url" | jq -r '.[0] | .version + "-" + .execution_id' 2>/dev/null || echo "")
fi

if [[ -n "$latest" && "$latest" != "null-null" ]]; then
echo -e "Latest version:  $latest"

if [[ "$current" == "$latest" ]]; then
echo -e "${GREEN}✓ Already at latest version!${NC}"
elif is_downgrade "$current" "$latest"; then
echo -e "${YELLOW}⚠ API reports an OLDER version than pinned — likely stale upstream metadata, not a real downgrade. Ignoring.${NC}"
else
echo -e "${YELLOW}⚠ Update available!${NC}"
fi
else
echo -e "${RED}Error: Could not parse version from API${NC}"
fi
echo ""
}

check_app "Antigravity 2.0" "https://antigravity-auto-updater-974169037036.us-central1.run.app/releases"
check_app "Antigravity CLI" "https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/linux_amd64.json"
check_app "Antigravity IDE" "https://antigravity-ide-auto-updater-974169037036.us-central1.run.app/releases"

# SDK is distributed only via PyPI (pip install google-antigravity), not one of
# Google's Cloud Run auto-updater endpoints, so it needs its own check block.
echo "--- Antigravity SDK ---"
current_url=$(jq -r '."Antigravity SDK"."x86_64-linux".url' "$VERSIONS_JSON" 2>/dev/null || echo "")
current=$(echo "$current_url" | grep -oP 'google_antigravity-\K[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
echo -e "Current version: $current"

latest=$(curl -sL "https://pypi.org/pypi/google-antigravity/json" | jq -r '.info.version' 2>/dev/null || echo "")

if [[ -n "$latest" && "$latest" != "null" ]]; then
echo -e "Latest version:  $latest"

if [[ "$current" == "$latest" ]]; then
echo -e "${GREEN}✓ Already at latest version!${NC}"
elif is_downgrade "$current" "$latest"; then
echo -e "${YELLOW}⚠ PyPI reports an OLDER version than pinned — likely a stale/cached response, not a real downgrade. Ignoring.${NC}"
else
echo -e "${YELLOW}⚠ Update available!${NC}"
fi
else
echo -e "${RED}Error: Could not parse version from PyPI API${NC}"
fi
echo ""
