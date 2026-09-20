# Roadmap

Four phases. Each one solves a real problem that people hit when accessing
old Mac backups from Linux.

---

## Phase 1 — Robustness

The scripts work for the common case: an unencrypted HFS+ sparsebundle on a
local or NFS-mounted path. These are the cases that break today:

| Gap | Problem | Fix |
|---|---|---|
| **Auto-detection** | `mount-tm.sh` tries HFS+ first, falls back to APFS. The fall-through is silent and slow when it fails. | Probe the filesystem type *before* mounting: read band 0 → check for NXSB (APFS) vs H+ (HFS+). Tell the user what was detected. |
| **Encrypted bundles** | `sparsebundlefs` opens them fine but the filesystem mount fails with no useful error. | Detect encryption from the APFS superblock (check nx_keylocker at offset 0x608). Print "this backup is encrypted — decrypt on a Mac first" instead of a generic mount failure. |
| **Binary plists** | `analyse-bundle.sh` can't parse them. Some Synology DSM versions rewrite Info.plist as binary. | Auto-detect and convert via `plistutil` if available, otherwise print the exact command to convert manually. |
| **NFS mount helper** | README documents NFS as faster than SMB but there's no script for it. | Add `mount-nas.sh` — mount a NAS share (SMB or NFS), then hand off to `mount-tm.sh`. Handles credential prompts and common mount options. |
| **Prerequisite check** | Scripts fail mid-way if `sparsebundlefs` or `hfsprogs` isn't installed. | Check all dependencies at the start. Print exactly what to install. |

**When it's done:** The scripts handle every common failure with a clear
message instead of a cryptic error from `mount`.

---

## Phase 2 — File recovery

Mounting a terabyte backup to find one file is slow. These features let you
find and extract what you need without browsing the whole tree.

| Feature | How |
|---|---|
| **`find-file.sh`** | Search for files by name or glob across all snapshots. `./find-file.sh bundle "*.kdbx"` — find every KeePass database in every snapshot. Uses `find` on the mounted filesystem. |
| **`extract.sh`** | Copy specific files or directories out of a backup. `./extract.sh bundle "Latest/Macintosh HD/Users/me/Documents" ~/recovered/` — preserves directory structure. |
| **Snapshot diff** | Show what changed between two snapshots. For HFS+ this is `diff -rq` on the dated directories. Useful for finding which snapshot has the version of a file you want. |
| **Size report** | Per-snapshot and per-directory size breakdown. "How much of this 900 GiB backup is actually unique data vs hard-linked duplicates?" |

**When it's done:** Common recovery tasks are one command, not a manual
browse through a mounted filesystem.

---

## Phase 3 — Containerization

Installing `sparsebundlefs`, `hfsprogs`, and `apfs-fuse` on every machine is
tedious. A container image puts everything in one place.

| Item | Detail |
|---|---|
| **Dockerfile** | Alpine or Debian-based, ships `sparsebundlefs`, `hfsprogs`, `apfs-fuse` (pre-built), and all the scripts. |
| **One-command mount** | `docker run --privileged -v /path/to/bundle:/bundle -v /tmp/tm:/mnt parkwardrr/timemachine-linux /bundle` — mount and browse via a bind mount. |
| **Docker Compose** | For NAS setups: mount the SMB/NFS share and the backup in one `docker-compose.yml`. |
| **CI build** | GitHub Actions builds and pushes the image to GHCR on every tag. |
| **ARM64 support** | Multi-arch image for Raspberry Pi and ARM NAS hosts (Synology DS923+ etc). |

**When it's done:** `docker run` and you're browsing your backup. No package
installation, no kernel module fiddling, no FUSE setup.

---

## Phase 4 — APFS snapshot navigation

HFS+ backups store each snapshot as a dated directory. APFS backups use
actual filesystem snapshots, which are invisible to a normal directory
listing. This phase makes APFS snapshots browsable.

| Feature | Detail |
|---|---|
| **Snapshot listing** | `./list-snapshots.sh bundle` — enumerate all APFS snapshots with dates and sizes. Uses `apfs-fuse` snapshot enumeration or direct superblock reading. |
| **Mount specific snapshot** | `./mount-tm.sh bundle --snapshot 2023-01-15` — mount one snapshot instead of the latest. |
| **Timeline view** | Print a timeline of all snapshots with dates and which machine they belong to. "You have 47 snapshots of MacBook-Pro spanning 2019-03-15 to 2023-01-15." |
| **Volume listing** | APFS containers hold multiple volumes. List them all and let the user pick which to mount. System volume vs Data volume matters — user files are only on Data. |

**When it's done:** APFS backups are as browsable as HFS+ ones. The tool
handles both formats transparently.

---

## Not planned

- **Write support.** Everything is read-only. Modifying a backup image is how
  you destroy it.
- **macOS support.** This is a Linux tool. On a Mac, use `hdiutil` and
  `tmutil` — they already work.
- **Backup *creation*.** This restores and browses. Making Time Machine
  backups from Linux is a different (and much harder) problem.
- **Encrypted backup decryption.** Detecting encryption and telling you about
  it: yes. Decrypting: no. Use a Mac or
  [`apfs-fuse`](https://github.com/sgan81/apfs-fuse) with a password.
