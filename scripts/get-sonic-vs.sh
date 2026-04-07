#!/usr/bin/env bash
# scripts/get-sonic-vs.sh
#
# Download the latest SONiC VS Docker image for use with containerlab.
#
# Source: https://sonic.software/builds.json
# The JSON index is maintained by the SONiC community and maps each branch
# to its latest successful build artifact with a direct download URL.
#
# Usage:
#   bash scripts/get-sonic-vs.sh [OPTIONS]
#   bash scripts/get-sonic-vs.sh --branch list
#   bash scripts/get-sonic-vs.sh --branch 202411 --load

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults (override via flags or environment variables)
# ---------------------------------------------------------------------------
BRANCH="${SONIC_BRANCH:-}"                  # empty = auto-detect latest release
OUTPUT="${SONIC_OUTPUT:-docker-sonic-vs.gz}"
DOCKER_TAG="${SONIC_TAG:-docker-sonic-vs:latest}"
LOAD_IMAGE=false

BUILDS_API="https://sonic.software/builds.json"
IMAGE_FILE="docker-sonic-vs.gz"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BOLD='\033[1m'; NC='\033[0m'
log()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()  { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

check_deps() {
    local missing=()
    for cmd in curl jq; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    [[ ${#missing[@]} -eq 0 ]] || die "Missing required tools: ${missing[*]}"
}

fetch_builds() {
    curl -sf --max-time 30 "$BUILDS_API" --user-agent "sonic-lab-workbook" \
        || die "Failed to reach $BUILDS_API"
}

# Return the highest-numbered release branch that has the image (e.g. 202511)
latest_release_branch() {
    echo "$1" | jq -r --arg f "$IMAGE_FILE" '
        to_entries[]
        | select(.key | test("^[0-9]{6}$"))
        | select(.value[$f] != null)
        | .key
    ' | sort -n | tail -1
}

get_url()  {
    echo "$1" | jq -r --arg b "$2" --arg f "$IMAGE_FILE" '.[$b][$f].url  // empty'
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

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Download the latest SONiC VS Docker image for containerlab.

Options:
  -b, --branch BRANCH    Branch to download (default: latest release branch)
                         Use 'master' for the latest development build
                         Use 'list'   to show all available branches
  -o, --output FILE      Output filename          (default: $OUTPUT)
  -t, --tag TAG          Docker tag after load     (default: $DOCKER_TAG)
  -l, --load             Load image into Docker after download
  -h, --help             Show this help

Environment overrides: SONIC_BRANCH  SONIC_OUTPUT  SONIC_TAG

Examples:
  $(basename "$0") --branch list
  $(basename "$0") --branch 202411 --load
  $(basename "$0") --branch master --output sonic-master.gz
EOF
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -b|--branch)  BRANCH="$2"; shift 2 ;;
        -o|--output)  OUTPUT="$2"; shift 2 ;;
        -t|--tag)     DOCKER_TAG="$2"; shift 2 ;;
        -l|--load)    LOAD_IMAGE=true; shift ;;
        -h|--help)    usage; exit 0 ;;
        *) die "Unknown option: $1  (use --help for usage)" ;;
    esac
done

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
check_deps

log "Fetching build index from sonic.software..."
BUILDS=$(fetch_builds)

# List mode
if [[ "$BRANCH" == "list" ]]; then
    echo ""
    echo -e "${BOLD}Available branches with $IMAGE_FILE:${NC}"
    list_branches "$BUILDS"
    echo ""
    exit 0
fi

# Auto-detect branch
if [[ -z "$BRANCH" ]]; then
    BRANCH=$(latest_release_branch "$BUILDS")
    [[ -n "$BRANCH" ]] || die "Could not determine latest release branch from $BUILDS_API"
    log "Auto-selected latest release branch: ${BOLD}$BRANCH${NC}"
fi

URL=$(get_url "$BUILDS" "$BRANCH")
[[ -n "$URL" ]] || die "No $IMAGE_FILE found for branch '$BRANCH'. Run with --branch list to see options."

BUILD_DATE=$(get_date "$BUILDS" "$BRANCH")

log "Branch    : $BRANCH"
log "Build date: $BUILD_DATE"
log "Output    : $OUTPUT"
echo ""

[[ -f "$OUTPUT" ]] && warn "$OUTPUT already exists — overwriting."

curl -L --progress-bar --output "$OUTPUT" "$URL" \
    || die "Download failed. URL was: $URL"

echo ""
SIZE=$(du -sh "$OUTPUT" | cut -f1)
log "Saved: $OUTPUT ($SIZE)"

if [[ "$LOAD_IMAGE" == true ]]; then
    echo ""
    log "Loading into Docker..."
    LOAD_OUT=$(docker load -i "$OUTPUT" 2>&1) || die "docker load failed:\n$LOAD_OUT"
    echo "$LOAD_OUT"

    # Retag if the loaded name differs from what we want
    LOADED_TAG=$(echo "$LOAD_OUT" | grep -oE 'Loaded image[^:]*: .+' | awk '{print $NF}' | head -1)
    if [[ -n "$LOADED_TAG" && "$LOADED_TAG" != "$DOCKER_TAG" ]]; then
        docker tag "$LOADED_TAG" "$DOCKER_TAG"
        log "Tagged as: $DOCKER_TAG"
    fi

    echo ""
    log "Done. Verify with: docker images | grep sonic"
else
    echo ""
    echo -e "${BOLD}Next steps:${NC}"
    echo "  docker load -i $OUTPUT"
    echo "  docker images | grep sonic"
fi
