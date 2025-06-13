# server2025

Copy and modified from [ZFS BootMenu Noble Doc](https://docs.zfsbootmenu.org/en/v3.0.x/guides/ubuntu/noble-uefi.html)

## Configure Live Environment
### Open a root shell
Open a terminal on the live installer session, then:
```bash
sudo -i
```
Confirm EFI support:
```bash
# dmesg | grep -i efivars
[    0.301784] Registered efivars operations
```
### Source `/etc/os-release`
The file `/etc/os-release` defines variables that describe the running distribution. In particular, the `$ID` variable defined within can be used as a short name for the filesystem that will hold this installation.
```bash
source /etc/os-release
export ID
```
### Install helpers
```bash
apt update
apt install debootstrap gdisk zfsutils-linux
```
### Generate `/etc/hostid`
```bash
zgenhostid -f 0x00bab10c
```
### Define disk variables

For convenience and to reduce the likelihood of errors, set environment variables that refer to the devices that will be configured during the setup.

For many users, it is most convenient to place boot files (i.e., ZFSBootMenu and any loader responsible for launching it) on the the same disk that will hold the ZFS pool. However, some users may wish to dedicate an entire disk to the ZFS pool or create a multi-disk pool. A USB flash drive provides a convenient location for the boot partition. Fortunately, this alternative configuration is easily realized by simply defining a few environment variables differently.

Verify your target disk devices with `lsblk`. `/dev/sda`, `/dev/sdb` and `/dev/nvme0n1` used below are examples.

First, define variables that refer to the disk and partition number that will hold **boot files**:
```bash
export BOOT_DISK="/dev/sda"
export BOOT_PART="1"
export BOOT_DEVICE="${BOOT_DISK}${BOOT_PART}"
```
