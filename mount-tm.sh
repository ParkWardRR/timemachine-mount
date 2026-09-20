#!/usr/bin/env bash
#
# Mount a macOS Time Machine sparsebundle on Linux.
#
# Prerequisites:
#   apt install sparsebundlefs hfsprogs   # HFS+ backups (pre-Catalina)
#   apt install sparsebundlefs apfs-fuse  # APFS backups (Catalina+)
#
# Usage:
#   ./mount-tm.sh /path/to/Machine.sparsebundle [machine-name]

set -euo pipefail

BUNDLE="${1:?Usage: $0 /path/to/Machine.sparsebundle [machine-name]}"
MACHINE="${2:-}"

DMG_MNT="/tmp/tm-dmg-$$"
FS_MNT="/tmp/tm-fs-$$"

cleanup() {
    echo "cleaning up mounts…"
    umount "$FS_MNT" 2>/dev/null || true
    fusermount -u "$DMG_MNT" 2>/dev/null || true
    rmdir "$DMG_MNT" "$FS_MNT" 2>/dev/null || true
}
trap cleanup EXIT

if [ ! -d "$BUNDLE" ]; then
    echo "error: $BUNDLE is not a directory (expected a .sparsebundle)" >&2
    exit 1
fi

# Step 1: present the sparsebundle as a single disk image via FUSE
mkdir -p "$DMG_MNT" "$FS_MNT"
echo "mounting sparsebundle via sparsebundlefs…"
sparsebundlefs "$BUNDLE" "$DMG_MNT"

DMG="$DMG_MNT/sparsebundle.dmg"
if [ ! -f "$DMG" ]; then
    echo "error: sparsebundlefs did not produce $DMG" >&2
    exit 1
fi

# Step 2: mount the filesystem
echo "mounting filesystem…"
if mount -t hfsplus -o ro,loop "$DMG" "$FS_MNT" 2>/dev/null; then
    echo "  mounted as HFS+"
elif command -v apfs-fuse >/dev/null 2>&1; then
    umount "$FS_MNT" 2>/dev/null || true
    apfs-fuse "$DMG" "$FS_MNT"
    echo "  mounted as APFS (via apfs-fuse)"
else
    echo "error: could not mount as HFS+ and apfs-fuse is not installed" >&2
    exit 1
fi

# Step 3: find backup root
BACKUPDB="$FS_MNT/Backups.backupdb"
if [ ! -d "$BACKUPDB" ]; then
    echo "no Backups.backupdb — may be APFS-style backup"
    echo "filesystem root: $FS_MNT"
else
    if [ -z "$MACHINE" ]; then
        echo "available machines:"
        ls -1 "$BACKUPDB"
        echo ""
        echo "re-run with: $0 $BUNDLE <machine-name>"
        exit 0
    fi
    echo "backup root: $BACKUPDB/$MACHINE"
    echo ""
    echo "snapshots:"
    ls -1 "$BACKUPDB/$MACHINE" | head -20
fi

echo ""
echo "mounted at: $FS_MNT"
echo "browse with: ls $FS_MNT"
echo ""
echo "to unmount: fusermount -u $DMG_MNT && umount $FS_MNT"
echo "(or just exit this script — cleanup runs automatically)"

# Keep the mounts alive until the user is done
echo ""
echo "press enter to unmount and exit"
read -r
