# qemu-spinrite
Wrapper script to optimize running SpinRite in a Qemu VM with KVM accelleration and native I/O
Tested with SpinRite 6.1 but other versions will likely work as well. SpinRite 6.0 should have no trouble, but get the upgrade from grc.com, it's certainly worth it.

# QEMU SpinRite Launcher

A small Bash utility for running **SpinRite 6.1** against physical disks through QEMU.

The script scans the host system for available disks, displays useful information about each device—including its connection bus and negotiated speed where available—and lets you select a physical disk to expose directly to SpinRite inside a QEMU virtual machine.

It uses **KVM hardware acceleration**, **raw block-device access**, and QEMU's **native asynchronous I/O** options for efficient access to the physical disk.

> **Important:** SpinRite is commercial software and is **not included** with this project. You must supply your own legally obtained `SpinRite.iso`.

## Features

- Automatically discovers physical disks using `lsblk`
- Displays:
  - Device name
  - Drive model
  - Capacity
  - Bus/interface
  - Negotiated interface speed where Linux exposes it
  - Mount status
- Detects USB connection speeds such as:
  - `USB 480M`
  - `USB 5000M`
  - `USB 10000M`
- Detects NVMe/PCIe link speed and width, for example:
  - `NVMe / PCIe 8.0 GT/s PCIe x4`
- Attempts to report SATA/ATA negotiated link speed
- Prevents accidental use of mounted disks
- Offers to unmount a selected disk before starting SpinRite
- Passes the physical disk directly to QEMU as a raw block device
- Uses KVM acceleration
- Uses QEMU native asynchronous I/O (`aio=native`)
- Uses `cache=none` to avoid the host page cache

The bus-speed display is particularly useful when working with external SSDs. A fast SSD connected through the wrong USB port or hub can otherwise silently operate at USB 2.0 speeds.

For example:

```text
[1] /dev/sda - Samsung Portable SSD T5 (465.8G) [USB 5000M] [✅ READY (Not mounted)]
[2] /dev/sdb - SandForce[484167] (29.8G) [USB 480M] [✅ READY (Not mounted)]
[3] /dev/nvme0n1 - SAMSUNG MZVLW512HMJP-00000 (476.9G) [NVMe / PCIe 8.0 GT/s PCIe x4] [⚠️ MOUNTED (LOCKED)]
```

In this example, `/dev/sda` is connected at USB 5 Gbit/s while `/dev/sdb` is connected at only USB 480 Mbit/s.

## Requirements

The script requires:

- Linux
- Bash
- QEMU
- KVM support
- `lsblk`
- `udisksctl` or `umount`
- Permission to access the selected raw block device
- A legally obtained SpinRite ISO image

It has been tested on **Arch Linux**.

It should work on most other Linux distributions with the required utilities installed.

QEMU itself also runs on several other Unix-like operating systems, but this script currently makes use of Linux-specific facilities including KVM, `lsblk`, `/sys`, and `udisksctl`. Running it on FreeBSD, macOS, or another Unix-like system would therefore require some adaptation.

## Installation

Clone the repository or simply download the script and make it executable:

```bash
chmod +x qemu-spinrite.sh
```

You can then run it with:

```bash
./qemu-spinrite.sh
```

## Supplying SpinRite.iso

**SpinRite is not supplied by this project.**

Obtain SpinRite separately and create or download the appropriate ISO image according to the SpinRite documentation.

At the beginning of `qemu-spinrite.sh`, locate the `ISO` variable:

```bash
ISO="$HOME/vm-space/ISO/SpinRite.iso"
```

Change it to wherever your own `SpinRite.iso` is stored.

For example:

```bash
ISO="$HOME/Downloads/SpinRite.iso"
```

or:

```bash
ISO="/home/myuser/iso/SpinRite.iso"
```

The script checks that the configured file exists before doing anything with your disks.

## Raw Disk Permissions

QEMU needs direct read/write access to the physical block device that SpinRite will operate on.

On many Linux distributions, raw disks belong to the `disk` group:

```bash
ls -l /dev/sda
```

You might see something similar to:

```text
brw-rw---- 1 root disk ... /dev/sda
```

You can determine the owning group directly with:

```bash
stat -c '%G' /dev/sda
```

For example:

```text
disk
```

Check your current groups with:

```bash
groups
```

### Adding your user to the device group

If the device belongs to `disk`, an administrator can add your user with:

```bash
sudo usermod -aG disk "$USER"
```

Or, to automatically use the group that owns a particular device:

```bash
DEVICE=/dev/sda
GROUP=$(stat -c '%G' "$DEVICE")
echo "Device group: $GROUP"
sudo usermod -aG "$GROUP" "$USER"
```

You will normally need to **log out completely and log back in** before the new group membership takes effect.

Verify it afterwards with:

```bash
groups
```

### A word of caution about the `disk` group

Membership in the `disk` group is highly privileged.

It generally gives your account direct access to physical disks and can allow you to bypass normal filesystem permissions, read data belonging to other users, corrupt filesystems, or overwrite the operating system.

Do not add an untrusted account to this group.

Some distributions use different permissions, ACLs, udev rules, or device groups instead. Check the permissions on the actual device you intend to use rather than assuming the group will always be named `disk`.

The script itself does **not** need to run entirely as root merely to discover disks or determine their USB/PCIe connection speeds. Those details are normally available to an ordinary user through Linux sysfs.

## KVM Permissions

QEMU also needs permission to access `/dev/kvm` in order to use KVM acceleration.

Check it with:

```bash
ls -l /dev/kvm
```

On many distributions it belongs to the `kvm` group.

If necessary:

```bash
sudo usermod -aG kvm "$USER"
```

Again, log out and back in after changing group membership.

You can check whether KVM is available with:

```bash
test -r /dev/kvm && test -w /dev/kvm && echo "KVM access OK"
```

## Usage

Start the script:

```bash
./qemu-spinrite.sh
```

It scans the system and presents a menu similar to:

```text
=========================================================
🔍 scannning system for available disks...
=========================================================
Select the disk that SpinRite should scan::
---------------------------------------------------------
[1] /dev/sda - Samsung Portable SSD T5 (465.8G) [USB 5000M] [✅ Ready (Not mounted)]
[2] /dev/sdb - SandForce[484167] (29.8G) [USB 480M] [✅ Ready (Not mounted)]
[3] /dev/nvme0n1 - SAMSUNG MZVLW512HMJP-00000 (476.9G) [NVMe / PCIe 8.0 GT/s PCIe x4] [⚠️ MOUNTED (LOCKED)]
---------------------------------------------------------
Enter nummer (1-3) or 'q' to quit:
```

Select the disk you want SpinRite to access.

If the selected disk or one of its partitions is currently mounted, the script warns you and offers to unmount it.

SpinRite requires exclusive raw access to the disk, so the script will not intentionally proceed while the selected device remains mounted.

## USB Speed Detection

For USB disks, the script walks the device's Linux sysfs hierarchy and reads the negotiated USB connection speed.

Typical values include:

| Display | Approximate interface |
|---|---|
| `USB 12M` | USB Full Speed |
| `USB 480M` | USB 2.0 High Speed |
| `USB 5000M` | USB 3.x 5 Gbit/s |
| `USB 10000M` | USB 3.x 10 Gbit/s |
| `USB 20000M` | USB 3.x 20 Gbit/s |

This is the **negotiated USB link speed**, not a benchmark of the disk.

For example, seeing:

```text
Samsung Portable SSD T5 (...) [USB 480M]
```

is a strong indication that the SSD is currently connected through a USB 2.0 path, even if both the SSD and another available port support much higher speeds.

Moving the drive to another port might result in:

```text
Samsung Portable SSD T5 (...) [USB 5000M]
```

Actual disk throughput will always be lower than the theoretical bus signalling rate.

## NVMe / PCIe Detection

For NVMe disks, the script examines the PCI device behind the NVMe controller and reads Linux's:

```text
current_link_speed
current_link_width
```

For example:

```text
NVMe / PCIe 8.0 GT/s PCIe x4
```

indicates a PCIe link operating at 8.0 GT/s across four lanes.

As with USB, this describes the negotiated bus connection rather than the measured read/write performance of the SSD.

## How QEMU Is Started

The selected physical disk is passed directly to QEMU:

```bash
-drive file="$DISK",format=raw,if=none,id=sysdisk,cache=none,aio=native
```

and presented to the guest as an IDE disk:

```bash
-device ide-hd,bus=ide.0,unit=0,drive=sysdisk
```

SpinRite is booted from the configured ISO image.

The VM uses:

```bash
-enable-kvm
-machine pc,accel=kvm
-cpu host
```

to enable KVM hardware virtualization and expose the host CPU to the guest.

The important disk options are:

### `format=raw`

The physical block device is treated as a raw disk rather than a QEMU image format.

### `cache=none`

QEMU bypasses the host page cache for disk I/O. This avoids an unnecessary host caching layer between SpinRite and the physical device.

### `aio=native`

QEMU uses the host's native asynchronous I/O mechanism.

Together, these options are intended to keep the virtualized path to the physical disk relatively direct.

## Safety

**Be very careful when selecting a disk.**

This script deliberately gives SpinRite raw read/write access to a physical storage device.

Double-check:

- The device name
- The model
- The capacity
- Whether the device is mounted
- That you have selected the intended physical disk

Never select your system disk unless you specifically understand the consequences and have arranged for it not to be actively used by the host operating system.

Raw block-device access bypasses the protections normally provided by mounted filesystems.

Having current backups of important data is strongly recommended before performing low-level disk maintenance.

## Troubleshooting

### QEMU reports permission denied for `/dev/sdX`

Check the device permissions:

```bash
ls -l /dev/sdX
```

and its group:

```bash
stat -c '%G' /dev/sdX
```

Then verify your groups:

```bash
groups
```

If you have just been added to a group, log out and back in.

### QEMU cannot access KVM

Check:

```bash
ls -l /dev/kvm
```

and:

```bash
groups
```

You may need membership in your distribution's `kvm` group.

### USB speed says 480M

The disk is currently negotiating a USB 2.0 High Speed connection.

Check:

- Which physical USB port is being used
- Whether the port supports USB 3.x
- USB hubs
- USB docks
- Adapters
- The USB cable

A USB 3-capable SSD connected through any USB 2-only component in the path may fall back to 480 Mbit/s.

### Bus information is unavailable

Not every Linux storage driver exposes all connection information in the same way.

The script reports what it can determine from `lsblk` and Linux sysfs. Failure to display a speed does not necessarily indicate a problem with the disk.

## Tested Environment

The script has been tested with:

- Arch Linux
- QEMU/KVM
- USB mass-storage devices
- USB-attached SSDs
- NVMe storage
- SpinRite 6.1

Other modern Linux distributions should work provided the necessary QEMU, KVM, block-device, and userspace utilities are available.

## License

This project contains only the launcher script and related documentation.

**SpinRite is a separate commercial product and is not distributed as part of this project.** SpinRite and its associated trademarks belong to their respective owner.

You must provide your own licensed copy of SpinRite and configure `qemu-spinrite.sh` to point to your own `SpinRite.iso`.
