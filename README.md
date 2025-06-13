# server2025

Copy and modified from [ZFS BootMenu Noble Doc](https://docs.zfsbootmenu.org/en/v3.0.x/guides/ubuntu/noble-uefi.html)

<details>
<summary>Configure Live Environment</summary>

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
#### Get disk by id first
```bash
ls -la /dev/disk/by-id
```
Next, define variables that refer to the disks and partition number that will hold the **ZFS pool**:

```bash
export POOL_DISK1="/dev/disk/by-id/nvme-VMware_Virtual_NVMe_Disk_VMware_NVME_0000_1"
export POOL_DISK2="/dev/disk/by-id/nvme-VMware_Virtual_NVMe_Disk_VMware_NVME_0000_2"
export POOL_PART="1"
export POOL_DEVICE1="${POOL_DISK1}-part${POOL_PART}"
export POOL_DEVICE2="${POOL_DISK2}-part${POOL_PART}"
```

</details>
<details>
<summary>Disk preparation</summary>

### Wipe partitions
```bash
zpool labelclear -f "$POOL_DISK1"
zpool labelclear -f "$POOL_DISK2"
```
```bash
wipefs -a "$POOL_DISK1"
wipefs -a "$POOL_DISK2"
wipefs -a "$BOOT_DISK"
```
```bash
sgdisk --zap-all "$POOL_DISK1"
sgdisk --zap-all "$POOL_DISK2"
sgdisk --zap-all "$BOOT_DISK"
```
### Create EFI boot partition
```bash
sgdisk -n "${BOOT_PART}:1m:+512m" -t "${BOOT_PART}:ef00" "$BOOT_DISK"
```
### Create zpool partition
```bash
sgdisk -n "${POOL_PART}:0:-10m" -t "${POOL_PART}:bf00" "$POOL_DISK1"
sgdisk -n "${POOL_PART}:0:-10m" -t "${POOL_PART}:bf00" "$POOL_DISK2"
```

</details>
<details>
<summary>ZFS pool creation</summary>

### Create the zpool
#### export pool parameters
```bash
export ZPOOL_ASHIFT="13"
export ZFS_COMPRESSION="lz4"
```
#### create pool
```bash
zpool create -f \
  -o ashift="$ZPOOL_ASHIFT" \
  -o autotrim=on \
  -o compatibility=openzfs-2.1-linux \
  -O acltype=posixacl \
  -O canmount=off \
  -O compression="$ZFS_COMPRESSION" \
  -O dnodesize=auto \
  -O normalization=formD \
  -O atime=off \
  -O xattr=sa \
  -m none \
  zroot mirror "$POOL_DEVICE1" "$POOL_DEVICE2"
```
> [!NOTE]
> The option `-o compatibility=openzfs-2.1-linux` is a conservative choice. It can be omitted or otherwise adjusted to match your specific system needs.
>
> Binary releases of ZFSBootMenu are generally built with the latest stable release of ZFS. Future releases of ZFSBootMenu may therefore support newer feature sets. Check project release notes prior to updating or removing `compatibility` options and upgrading your system pool.

</details>
<details>
<summary>Create initial file systems</summary>
  
```bash
zfs create -o mountpoint=none zroot/ROOT
zfs create -o mountpoint=/ -o canmount=noauto zroot/ROOT/${ID}
zfs create -o mountpoint=/home zroot/home

zpool set bootfs=zroot/ROOT/${ID} zroot
```

> [!NOTE]
> It is important to set the property `canmount=noauto` on any file systems with `mountpoint=/` (that is, on any additional boot environments you create). Without this property, the OS will attempt to automount all ZFS file systems and fail when multiple file systems attempt to mount at `/`; this will prevent your system from booting. Automatic mounting of `/` is not required because the root file system is explicitly mounted in the boot process.
>
> Also note that, unlike many ZFS properties, `canmount` is not inheritable. Therefore, setting `canmount=noauto` on `zroot/ROOT` is not sufficient, as any subsequent boot environments you create will default to `canmount=on`. It is necessary to explicitly set the `canmount=noauto` on every boot environment you create.

#### Export, then re-import with a temporary mountpoint of /mnt
```bash
zpool export zroot
zpool import -N -R /mnt zroot
zfs mount zroot/ROOT/${ID}
zfs mount zroot/home
```
#### Verify that everything is mounted correctly
```bash
mount | grep mnt
```
should return
```bash
zroot/ROOT/ubuntu on /mnt type zfs (rw,relatime,xattr,posixacl)
zroot/home on /mnt/home type zfs (rw,relatime,xattr,posixacl)
```
#### Update device symlinks
```bash
udevadm trigger
```

</details>
