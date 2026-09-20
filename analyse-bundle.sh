#!/usr/bin/env bash
#
# Quick health check on a sparsebundle — no mounting, no root required.
# Parses Info.plist, counts bands, reports allocated vs declared size,
# and checks whether band 0 (the partition map) exists.
#
# Usage:
#   ./analyse-bundle.sh /path/to/Machine.sparsebundle

set -euo pipefail

BUNDLE="${1:?Usage: $0 /path/to/Machine.sparsebundle}"

if [ ! -d "$BUNDLE" ]; then
    echo "error: $BUNDLE is not a directory" >&2
    exit 1
fi

# Parse Info.plist
PLIST="$BUNDLE/Info.plist"
if [ ! -f "$PLIST" ]; then
    PLIST="$BUNDLE/Info.bckup"
    if [ ! -f "$PLIST" ]; then
        echo "error: no Info.plist or Info.bckup found" >&2
        exit 1
    fi
    echo "warning: Info.plist missing, using Info.bckup"
fi

# Check for binary plist
if head -c8 "$PLIST" | grep -q "bplist00"; then
    echo "error: binary plist — convert first: plutil -convert xml1 $PLIST" >&2
    exit 1
fi

# Extract values
BAND_SIZE=$(grep -A1 '>band-size<' "$PLIST" | grep integer | sed 's/[^0-9]//g')
DECLARED=$(grep -A1 '>size<' "$PLIST" | grep integer | sed 's/[^0-9]//g')

if [ -z "$BAND_SIZE" ]; then
    echo "error: no band-size in plist" >&2
    exit 1
fi

# Band inventory
BANDS_DIR="$BUNDLE/bands"
if [ ! -d "$BANDS_DIR" ]; then
    echo "error: no bands/ directory" >&2
    exit 1
fi

BAND_COUNT=$(find "$BANDS_DIR" -maxdepth 1 -type f | wc -l | tr -d ' ')
ZERO_BANDS=$(find "$BANDS_DIR" -maxdepth 1 -type f -empty | wc -l | tr -d ' ')
HAS_BAND_ZERO="no"
[ -f "$BANDS_DIR/0" ] && HAS_BAND_ZERO="yes"

# Compute sizes
BAND_SIZE_MB=$((BAND_SIZE / 1048576))
ALLOCATED=$((BAND_COUNT * BAND_SIZE))
ALLOCATED_GB=$(echo "scale=1; $ALLOCATED / 1073741824" | bc)
DECLARED_GB=$(echo "scale=1; ${DECLARED:-0} / 1073741824" | bc)

echo "sparsebundle: $(basename "$BUNDLE")"
echo ""
echo "  band size:     ${BAND_SIZE_MB} MiB"
echo "  bands:         ${BAND_COUNT}"
echo "  allocated:     ${ALLOCATED_GB} GiB"
echo "  declared:      ${DECLARED_GB} GiB"
echo "  band 0:        ${HAS_BAND_ZERO}"
echo "  zero-length:   ${ZERO_BANDS}"
echo ""

# Health assessment
if [ "$BAND_COUNT" -eq 0 ]; then
    echo "  health: UNUSABLE — no bands at all"
elif [ "$ZERO_BANDS" -gt 0 ]; then
    echo "  health: UNUSABLE — ${ZERO_BANDS} zero-length bands (truncated copy)"
elif [ "$HAS_BAND_ZERO" = "no" ]; then
    echo "  health: UNUSABLE — band 0 absent (partition map missing)"
else
    echo "  health: SOUND — band 0 present, no zero-length bands"
    echo "  (full health check requires mounting and filesystem inspection)"
fi
