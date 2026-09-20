#!/usr/bin/env bash
# Unmount a previously mounted Time Machine backup.
# Usage: ./unmount-tm.sh [mount-point]
#
# Without arguments, finds and unmounts all tm-fs-* and tm-dmg-* mounts.

set -euo pipefail

if [ -n "${1:-}" ]; then
    umount "$1" 2>/dev/null || fusermount -u "$1" 2>/dev/null || echo "warning: could not unmount $1"
    exit 0
fi

# Find our mounts
for mnt in /tmp/tm-fs-* /tmp/tm-dmg-*; do
    if mountpoint -q "$mnt" 2>/dev/null; then
        echo "unmounting $mnt"
        umount "$mnt" 2>/dev/null || fusermount -u "$mnt" 2>/dev/null || true
    fi
    rmdir "$mnt" 2>/dev/null || true
done

echo "done"
