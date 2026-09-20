[![License: Blue Oak 1.0.0](https://img.shields.io/badge/license-Blue%20Oak%201.0.0-2D6CDF)](https://blueoakcouncil.org/license/1.0.0)
[![Platform: Linux](https://img.shields.io/badge/platform-Linux-orange)](https://kernel.org)
[![Shell: Bash](https://img.shields.io/badge/shell-bash-green)](https://www.gnu.org/software/bash/)
[![GitHub last commit](https://img.shields.io/github/last-commit/ParkWardRR/timemachine-linux)](https://github.com/ParkWardRR/timemachine-linux/commits/main)
[![GitHub stars](https://img.shields.io/github/stars/ParkWardRR/timemachine-linux)](https://github.com/ParkWardRR/timemachine-linux/stargazers)

# timemachine-linux

Mount and browse macOS Time Machine backups on Linux. Three scripts, zero dependencies beyond FUSE.

You have an old Mac backup sitting on a NAS. You need a file from it. You're on Linux. The information you need is scattered across a dozen Stack Overflow posts, half of which are wrong or outdated. This repo is the working answer.

## What you need

Two packages. Pick the set that matches your backup format.

**HFS+ backups** (macOS Sierra and earlier, or any backup started before High Sierra):

```bash
# Debian / Ubuntu
sudo apt install sparsebundlefs hfsprogs

# Fedora / RHEL
sudo dnf install sparsebundlefs hfsplus-tools
```

**APFS backups** (High Sierra and later):

```bash
# Debian / Ubuntu
sudo apt install sparsebundlefs
# apfs-fuse must be built from source:
sudo apt install fuse3 libfuse3-dev bzip2 libbz2-dev cmake g++ git zlib1g-dev
git clone https://github.com/sgan81/apfs-fuse.git
cd apfs-fuse && git submodule init && git submodule update
mkdir build && cd build && cmake .. && make
sudo cp apfs-fuse /usr/local/bin/
```

If you don't know which format you have, try HFS+ first. The mount script tries both automatically.

**Also needed:** FUSE. Most distros have it. If you get `/dev/fuse` errors, run `sudo modprobe fuse`.

## Quick start

```bash
git clone https://github.com/ParkWardRR/timemachine-linux.git
cd timemachine-linux

# Check the bundle health first (no root, no mounting)
./analyse-bundle.sh /path/to/MyMac.sparsebundle

# Mount it
sudo ./mount-tm.sh /path/to/MyMac.sparsebundle

# When you see the machine list, re-run with the machine name
sudo ./mount-tm.sh /path/to/MyMac.sparsebundle "My MacBook Pro"
```

That's it. The script tells you where it mounted. Browse with `ls`, copy what you need, press Enter to unmount.

## What is a sparsebundle

A sparsebundle is Apple's disk image format for Time Machine network backups. It is not a single file -- it is a directory that pretends to be one. Inside:

```
MyMac.sparsebundle/
├── Info.plist          # metadata: band size, declared image size
├── Info.bckup          # backup copy of Info.plist
├── bands/              # the actual data, split into fixed-size chunks
│   ├── 0               # band 0: partition map (must exist)
│   ├── 1
│   ├── 2
│   ├── ...
│   ├── a               # hex! not decimal
│   ├── b
│   ├── ...
│   ├── ff
│   ├── 100
│   └── ...
└── token               # lock file (ignorable)
```

Each band is a fixed-size chunk (typically 8 MiB). The band count times band size gives you the actual disk usage. The `Info.plist` declares a maximum image size, which is much larger -- that's the virtual disk size, not how much space the backup actually uses.

## The scripts

### mount-tm.sh

Mounts a sparsebundle and drops you into a browsable filesystem. Does three things:

1. Uses `sparsebundlefs` to reassemble the bands into a virtual disk image via FUSE
2. Mounts the filesystem inside that image (tries HFS+ first, falls back to APFS)
3. Finds `Backups.backupdb` and lists available machines/snapshots

Requires root (for the filesystem mount). Cleans up automatically when you press Enter or the script exits.

```bash
# List machines in the backup
sudo ./mount-tm.sh /volume1/timemachine/MyMac.sparsebundle

# Mount a specific machine
sudo ./mount-tm.sh /volume1/timemachine/MyMac.sparsebundle "My MacBook Pro"
```

The script keeps running while you browse. Open another terminal to explore. Press Enter in the script's terminal to unmount.

### analyse-bundle.sh

Quick health check. No mounting, no root required. Reads `Info.plist` and counts bands.

```bash
./analyse-bundle.sh /volume1/timemachine/MyMac.sparsebundle
```

Output:

```
sparsebundle: MyMac.sparsebundle

  band size:     8 MiB
  bands:         48276
  allocated:     377.2 GiB
  declared:      999.9 GiB
  band 0:        yes
  zero-length:   0

  health: SOUND — band 0 present, no zero-length bands
```

What the fields mean:
- **band size**: chunk size, usually 8 MiB (8388608 bytes)
- **bands**: number of band files -- this times band size is actual disk usage
- **allocated**: actual data on disk
- **declared**: virtual disk size from `Info.plist` (always larger than allocated)
- **band 0**: partition map -- if this is missing, the image is unusable
- **zero-length**: bands that exist but are empty -- indicates a truncated or corrupted copy

Health verdicts:
- **SOUND**: band 0 exists, no zero-length bands. Likely mountable.
- **UNUSABLE**: something is structurally broken. Details in the message.

### unmount-tm.sh

Cleans up mounts left behind if `mount-tm.sh` was killed without cleanup.

```bash
# Unmount everything
sudo ./unmount-tm.sh

# Unmount a specific mount point
sudo ./unmount-tm.sh /tmp/tm-fs-12345
```

## Step by step

For people who want to understand what is happening, or who need to do it manually.

### Step 1: Reassemble the sparsebundle

A sparsebundle is a directory full of band files. `sparsebundlefs` concatenates them into a single virtual disk image via FUSE:

```bash
mkdir /tmp/tm-dmg
sparsebundlefs /path/to/MyMac.sparsebundle /tmp/tm-dmg
ls /tmp/tm-dmg/
# sparsebundle.dmg
```

This does not copy any data. It presents the bands as a single file through FUSE. Fast, uses no extra disk space.

### Step 2: Mount the filesystem

The virtual disk image contains either an HFS+ or APFS filesystem.

**HFS+:**

```bash
mkdir /tmp/tm-fs
sudo mount -t hfsplus -o ro,loop /tmp/tm-dmg/sparsebundle.dmg /tmp/tm-fs
```

**APFS:**

```bash
mkdir /tmp/tm-fs
apfs-fuse /tmp/tm-dmg/sparsebundle.dmg /tmp/tm-fs
```

Always mount read-only. You do not want to write to a backup image.

### Step 3: Find your files

HFS+ Time Machine backups have this structure:

```
/tmp/tm-fs/
└── Backups.backupdb/
    └── My MacBook Pro/
        ├── 2019-03-15-120000/
        │   └── Macintosh HD/
        │       ├── Users/
        │       ├── Applications/
        │       └── ...
        ├── 2019-03-16-120000/
        ├── ...
        └── Latest -> 2023-01-15-080000
```

Each dated folder is a snapshot. `Latest` is a symlink to the most recent one. Your files are under `Macintosh HD/Users/yourusername/`.

APFS backups have a different structure -- see the APFS section below.

### Step 4: Clean up

```bash
sudo umount /tmp/tm-fs
fusermount -u /tmp/tm-dmg
rmdir /tmp/tm-fs /tmp/tm-dmg
```

Or just use `./unmount-tm.sh`.

## HFS+ vs APFS

**How to tell which you have:**

- Backup started on macOS Sierra (10.12) or earlier: HFS+
- Backup started on High Sierra (10.13) or later: probably APFS
- Not sure: try mounting as HFS+ first. If it fails, it is APFS.
- Or check: `file /tmp/tm-dmg/sparsebundle.dmg` -- but this is often unreliable through FUSE.

**HFS+:**
- Well-supported on Linux via `hfsprogs` (in every distro's repos)
- `Backups.backupdb` directory with dated snapshot folders
- Hard links used for deduplication between snapshots
- Reliable. This is the easy case.

**APFS:**
- Linux support via [`apfs-fuse`](https://github.com/sgan81/apfs-fuse) only
- Read-only
- Slower than HFS+ mounts
- No `Backups.backupdb` -- snapshots are APFS snapshots within the volume
- Works for file recovery. Not fast, but it works.

If you have an APFS backup and `apfs-fuse` is not cooperating, your best fallback is booting a macOS VM or using a Mac to pull the files.

## Troubleshooting

### `mount: unknown filesystem type 'hfsplus'`

The HFS+ kernel module is not loaded or `hfsprogs` is not installed.

```bash
sudo apt install hfsprogs    # Debian/Ubuntu
sudo modprobe hfsplus        # load the kernel module
```

Some minimal/cloud kernels strip HFS+ support. Check: `cat /proc/filesystems | grep hfs`. If it is not listed and `modprobe` fails, you need a different kernel.

### `fusermount: failed to open /dev/fuse: No such file or directory`

FUSE is not loaded.

```bash
sudo modprobe fuse
sudo apt install fuse        # if the module doesn't exist
```

In containers (Docker, LXC), FUSE requires `--device /dev/fuse` or `--privileged`.

### `sparsebundlefs: command not found`

Install it:

```bash
sudo apt install sparsebundlefs      # Debian/Ubuntu (if available)
# or build from source:
git clone https://github.com/torarnv/sparsebundlefs.git
cd sparsebundlefs && make
sudo cp sparsebundlefs /usr/local/bin/
```

### `Input/output error` during mount or file access

The sparsebundle is damaged. Common causes:
- Incomplete copy from NAS (interrupted rsync/cp)
- NAS disk errors
- Time Machine backup was interrupted mid-write

Run `./analyse-bundle.sh` first. If it reports zero-length bands or missing band 0, the image is corrupt. There is no fix -- you need the original or a better copy.

### Binary plist

`analyse-bundle.sh` refuses to parse binary plists. Convert it first:

```bash
# On macOS:
plutil -convert xml1 /path/to/Info.plist

# On Linux (install plistutil):
sudo apt install plistutil
plistutil -i Info.plist -o Info.plist
```

### `mount: wrong fs type, bad option, bad superblock`

Usually means the filesystem inside the sparsebundle does not match what you are trying to mount it as. If HFS+ fails, try APFS. If both fail, the image may be damaged.

### Permission denied on band files

If the sparsebundle is on a NAS mount, check that your Linux user has read access to all files in the `bands/` directory. A common issue: Synology sets ownership to a local NAS user. Fix:

```bash
# Mount the NAS share with appropriate options
sudo mount -t cifs //nas/timemachine /mnt/nas -o username=admin,uid=$(id -u),gid=$(id -g),ro
```

## NAS notes

### Synology

Time Machine backups live at:

```
/volume1/timemachine/<hostname>.sparsebundle
```

Or if you set up a dedicated shared folder:

```
/volume1/<shared-folder>/<hostname>.sparsebundle
```

**Accessing from another machine on the network** (e.g., a Linux box mounting the NAS share):

```bash
# SMB mount
sudo mount -t cifs //synology/timemachine /mnt/tm -o username=admin,ro

# Then run the scripts against the mounted path
./analyse-bundle.sh /mnt/tm/MyMac.sparsebundle
sudo ./mount-tm.sh /mnt/tm/MyMac.sparsebundle
```

**Accessing directly on the NAS** (SSH into the Synology):

Synology runs Linux. You can SSH in and run the scripts directly. But Synology's DSM does not ship `sparsebundlefs` or `hfsprogs`. You will need to install them via `opkg` (Entware) or compile from source. This is doable but fiddly.

Simpler path: copy the sparsebundle to a Linux machine and work there. If the bundle is huge, mount the NAS share over NFS instead of copying.

### QNAP

Similar layout. Backups typically at:

```
/share/Timemachine/<hostname>.sparsebundle
```

Same approach: either mount the QNAP share on a Linux box, or SSH into the QNAP. QNAP's QTS has more package support than Synology -- check `opkg` or the App Center.

### Performance

Mounting a sparsebundle over SMB and then mounting the filesystem inside it means two layers of network I/O. This is slow for large backups.

Best approaches, in order of speed:
1. **Run directly on the NAS** -- zero network overhead, but limited tooling
2. **NFS mount** -- faster than SMB for this workload
3. **Copy the sparsebundle locally** -- slow upfront, fast after
4. **SMB mount** -- works, but you will notice the latency

## The band filename trap

Band files are named in hexadecimal. Not decimal. This matters.

```bash
ls bands/ | head -20
# 0
# 1
# 2
# ...
# 9
# a       <-- this is band 10
# b       <-- band 11
# ...
# f       <-- band 15
# 10      <-- band 16, not band 10!
```

`ls` sorts these lexicographically, which puts `10` after `1` and before `2`. The actual order by band number is: `0, 1, 2, ..., 9, a, b, ..., f, 10, 11, ...`

This does not matter for normal use -- `sparsebundlefs` handles it. It matters if you are:
- Manually inspecting bands
- Writing scripts that iterate over bands
- Trying to determine which part of the disk a band maps to

To sort bands numerically:

```bash
ls bands/ | sort -t/ -k1,1 --sort=version
# or
ls bands/ | while read b; do printf '%d %s\n' "0x$b" "$b"; done | sort -n
```

## Limitations

- **Read-only.** These scripts mount everything read-only. You cannot write to the backup, and you should not try.
- **No incremental restore.** This gives you a mounted filesystem to browse. It does not reconstruct a bootable Mac or handle Time Machine's deduplication logic across snapshots.
- **APFS support is experimental.** `apfs-fuse` works for file recovery but is not a production filesystem driver. Expect slow directory listings on large volumes.
- **Hard links across snapshots.** HFS+ Time Machine backups use directory hard links for deduplication. Linux's HFS+ driver handles this, but tools like `du` may report wrong sizes because they count hard-linked files multiple times.
- **Encrypted backups.** If the sparsebundle is encrypted, `sparsebundlefs` cannot open it. You need to decrypt it first on a Mac, or use a tool that supports the encryption format.
- **No macOS metadata.** Extended attributes, resource forks, and ACLs may not survive the mount. File contents are fine; metadata may be partial.

## License

[Blue Oak Model License 1.0.0](LICENSE.md) -- a short, readable, permissive license.
