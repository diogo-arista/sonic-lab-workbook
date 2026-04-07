#!/usr/bin/env bash
# scripts/build-sonic-vm.sh
#
# Downloads the SONiC VS KVM disk image from sonic.software and builds
# a vrnetlab Docker image for use with containerlab's sonic-vm kind.
#
# What this does:
#   1. Checks that /dev/kvm is accessible (required to RUN sonic-vm later)
#   2. Downloads sonic-vs.img.gz from sonic.software  (skippable with --image)
#   3. Gunzips and renames the image to sonic-vs-YYYYMM.qcow2
#   4. Clones srl-labs/vrnetlab and runs `make` in the sonic/ directory
#   5. Tags the resulting image as vrnetlab/vr-sonic:latest
#   6. Cleans up build artifacts
#
# Requirements (all present in the dev container):
#   docker, make, git, curl, jq
#
# KVM requirement:
#   /dev/kvm must be accessible to BUILD and RUN sonic-vm nodes.
#   - GitHub Codespaces (privileged mode):  supported
#   - Linux host:                           supported
#   - macOS Docker Desktop:                 NOT supported (no /dev/kvm)
#
# Usage:
#   bash scripts/build-sonic-vm.sh [OPTIONS]
#
# Options:
#   -b, --branch BRANCH    SONiC release branch to download (default: latest)
#                          Use 'list' to show all available branches
#   -i, --image  FILE      Path to a local sonic-vs.img or sonic-vs.img.gz
#                          (skips the download step entirely)
#   -h, --help             Show this help
#
# Environment overrides:
#   SONIC_BRANCH
#
# Examples:
#   bash scripts/build-sonic-vm.sh
#   bash scripts/build-sonic-vm.sh --branch 202411
#   bash scripts/build-sonic-vm.sh --branch list
#   bash scripts/build-sonic-vm.sh --image /tmp/sonic-vs.img.gz

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
BRANCH="${SONIC_BRANCH:-}"
LOCAL_IMAGE=""

BUILDS_API="https://sonic.software/builds.json"
IMAGE_FILE="sonic-vs.img.gz"
VRNETLAB_REPO="https://github.com/srl-labs/vrnetlab"
VRNETLAB_DIR="/tmp/vrnetlab-sonic-build"
FINAL_TAG="vrnetlab/vr-sonic:latest"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BOLD='\033[1m'; NC='\033[0m'
log()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()  { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Download the SONiC VS KVM image and build a vrnetlab Docker image (sonic-vm kind).

Options:
  -b, --branch BRANCH    SONiC release branch (default: latest release branch)
                         Use 'list' to show all available branches
  -i, --image  FILE      Path to an existing sonic-vs.img or sonic-vs.img.gz
                         (skips the download step)
  -h, --help             Show this help

Environment overrides: SONIC_BRANCH

Examples:
  $(basename "$0")                               # latest release branch
  $(basename "$0") --branch 202411              # specific branch
  $(basename "$0") --branch list                # list available branches
  $(basename "$0") --image /tmp/sonic-vs.img    # use local file
EOF
}

check_deps() {
    local missing=()
    for cmd in docker make git curl jq; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    [[ ${#missing[@]} -eq 0 ]] || die "Missing required tools: ${missing[*]}"
}

check_kvm() {
    if [[ ! -e /dev/kvm ]]; then
        die "/dev/kvm not found.
  sonic-vm requires KVM (nested virtualization) to build and run.
    - GitHub Codespaces (privileged mode): supported — KVM is available.
    - Linux host:                          supported.
    - macOS Docker Desktop:                NOT supported. /dev/kvm is not
      exposed by Docker Desktop on macOS. Use a Linux host or Codespaces."
    fi
    log "/dev/kvm is accessible"
}

fetch_builds() {
    curl -sf --max-time 30 "$BUILDS_API" --user-agent "sonic-lab-workbook" \
        || die "Failed to reach $BUILDS_API"
}

latest_release_branch() {
    echo "$1" | jq -r --arg f "$IMAGE_FILE" '
        to_entries[]
        | select(.key | test("^[0-9]{6}$"))
        | select(.value[$f] != null)
        | .key
    ' | sort -n | tail -1
}

get_url() {
    echo "$1" | jq -r --arg b "$2" --arg f "$IMAGE_FILE" '.[$b][$f].url // empty'
}

get_date() {
    echo "$1" | jq -r --arg b "$2" --arg f "$IMAGE_FILE" '.[$b][$f].date // empty'
}

list_branches() {
    echo "$1" | jq -r --arg f "$IMAGE_FILE" '
        to_entries[]
        | select(.value[$f] != null)
        | [.key, .value[$f].date]
        | @tsv
    ' | sort | while IFS=$'\t' read -r branch date; do
        printf "  %-12s  %s\n" "$branch" "$date"
    done
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -b|--branch) BRANCH="$2"; shift 2 ;;
        -i|--image)  LOCAL_IMAGE="$2"; shift 2 ;;
        -h|--help)   usage; exit 0 ;;
        *) die "Unknown option: $1  (use --help for usage)" ;;
    esac
done

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
check_deps
check_kvm

# ---------------------------------------------------------------------------
# Obtain the image
# ---------------------------------------------------------------------------
IMG_GZ=""
IMG_FILE=""

if [[ -n "$LOCAL_IMAGE" ]]; then
    # Use a local file — skip download
    [[ -f "$LOCAL_IMAGE" ]] || die "File not found: $LOCAL_IMAGE"

    if [[ "$LOCAL_IMAGE" == *.gz ]]; then
        IMG_GZ="$LOCAL_IMAGE"
    else
        IMG_FILE="$LOCAL_IMAGE"
    fi

    # Try to extract branch/version from the filename (e.g. sonic-vs-202411.img)
    BRANCH=$(basename "$LOCAL_IMAGE" | grep -oE '[0-9]{6}' | head -1 || true)
    [[ -n "$BRANCH" ]] || BRANCH="custom"
    log "Using local image: $LOCAL_IMAGE  (version: $BRANCH)"

else
    # Download from sonic.software
    log "Fetching build index from sonic.software ..."
    BUILDS=$(fetch_builds)

    if [[ "$BRANCH" == "list" ]]; then
        echo ""
        echo -e "${BOLD}Available branches with $IMAGE_FILE:${NC}"
        list_branches "$BUILDS"
        echo ""
        exit 0
    fi

    if [[ -z "$BRANCH" ]]; then
        BRANCH=$(latest_release_branch "$BUILDS")
        [[ -n "$BRANCH" ]] || die "Could not determine latest release branch from $BUILDS_API"
        log "Auto-selected latest release branch: ${BOLD}$BRANCH${NC}"
    fi

    URL=$(get_url "$BUILDS" "$BRANCH")
    [[ -n "$URL" ]] || die "No $IMAGE_FILE for branch '$BRANCH'. Run with --branch list to see options."

    BUILD_DATE=$(get_date "$BUILDS" "$BRANCH")

    log "Branch    : $BRANCH"
    log "Build date: $BUILD_DATE"
    log "Output    : sonic-vs.img.gz"
    echo ""

    IMG_GZ="sonic-vs.img.gz"
    [[ -f "$IMG_GZ" ]] && warn "$IMG_GZ already exists — overwriting."

    curl -L --progress-bar --output "$IMG_GZ" "$URL" \
        || die "Download failed. URL: $URL"

    echo ""
    log "Downloaded: $IMG_GZ ($(du -sh "$IMG_GZ" | cut -f1))"
fi

# ---------------------------------------------------------------------------
# Prepare the image for vrnetlab
# vrnetlab/sonic expects a file named  sonic-vs-YYYYMM.qcow2
# ---------------------------------------------------------------------------
QCOW2="sonic-vs-${BRANCH}.qcow2"

if [[ -n "$IMG_GZ" ]]; then
    log "Decompressing $(basename "$IMG_GZ") ..."
    gunzip -kf "$IMG_GZ"
    IMG_FILE="${IMG_GZ%.gz}"
fi

log "Renaming to $QCOW2 ..."
cp "$IMG_FILE" "$QCOW2"

# ---------------------------------------------------------------------------
# Clone vrnetlab and build the Docker image
# ---------------------------------------------------------------------------
log "Cloning srl-labs/vrnetlab (shallow) ..."
rm -rf "$VRNETLAB_DIR"
git clone --depth 1 "$VRNETLAB_REPO" "$VRNETLAB_DIR" \
    || die "Failed to clone vrnetlab from $VRNETLAB_REPO"

log "Copying $QCOW2 into vrnetlab/sonic/ ..."
cp "$QCOW2" "$VRNETLAB_DIR/sonic/"

echo ""
log "Building vrnetlab Docker image — this takes several minutes ..."
echo ""
cd "$VRNETLAB_DIR/sonic"
make

# ---------------------------------------------------------------------------
# Tag and clean up
# ---------------------------------------------------------------------------
VERSIONED_TAG="vrnetlab/vr-sonic:${BRANCH}"
cd - > /dev/null

log "Tagging $VERSIONED_TAG → $FINAL_TAG ..."
docker tag "$VERSIONED_TAG" "$FINAL_TAG"

log "Cleaning up build artifacts ..."
rm -rf "$VRNETLAB_DIR" "$QCOW2"
# Leave the downloaded .img.gz in place so re-runs don't need to re-download.
# Delete it manually if you want to reclaim disk space.

echo ""
log "Image ready:"
docker images | grep "vr-sonic" || true
echo ""
echo -e "${BOLD}Next step:${NC}"
echo "  clab deploy --topo labs/01-hello-world/topology.clab.yml --reconfigure"
echo ""
