# server2025

Copy and modified from [ZFS BootMenu Noble Doc](https://docs.zfsbootmenu.org/en/v3.0.x/guides/ubuntu/noble-uefi.html)

<details>
<summary>Configure Live Environment</summary>

### Open a root shell
Open a terminal on the live installer session, then:
```bash
sudo -i
```
optionally see how environment variables expand
```bash
set -x
```
Confirm EFI support:
```bash
dmesg | grep -i efivars
## should return -> [    0.301784] Registered efivars operations
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
apt install -y debootstrap gdisk zfsutils-linux
```
### Generate `/etc/hostid`
```bash
zgenhostid -f 0x00bab10c
```
### Define disk variables

For convenience and to reduce the likelihood of errors, set environment variables that refer to the devices that will be configured during the setup.

For many users, it is most convenient to place boot files (i.e., ZFSBootMenu and any loader responsible for launching it) on the the same disk that will hold the ZFS pool. However, some users may wish to dedicate an entire disk to the ZFS pool or create a multi-disk pool. A USB flash drive provides a convenient location for the boot partition. Fortunately, this alternative configuration is easily realized by simply defining a few environment variables differently.

Verify your target disk devices with `lsblk`. `/dev/sda`, `/dev/sdb` and `/dev/nvme0n1` used below are examples.

#### Get disk by id first
```bash
ls -la /dev/disk/by-id
```
First, define variables that refer to the disk and partition number that will hold **boot files**:
```bash
export BOOT_DISK="/dev/disk/by-id/ata-VMware_Virtual_SATA_Hard_Drive_0000"
```
```bash
export BOOT_PART="1"
export BOOT_DEVICE="${BOOT_DISK}-part${BOOT_PART}"
```
Next, define variables that refer to the disks and partition number that will hold the **ZFS pool**:

```bash
export POOL_DISK1="/dev/disk/by-id/nvme-VMware_Virtual_NVMe_Disk_VMware_NVME_0000_1"
export POOL_DISK2="/dev/disk/by-id/nvme-VMware_Virtual_NVMe_Disk_VMware_NVME_0000_2"
```
```bash
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
sleep 2
zpool labelclear -f "$POOL_DISK2"
sleep 2
```
`failed to clear label` error is ok if this is a set of new disks
```bash
wipefs -a "$POOL_DISK1"
sleep 2
wipefs -a "$POOL_DISK2"
sleep 2
wipefs -a "$BOOT_DISK"
sleep 2
```
```bash
sgdisk --zap-all "$POOL_DISK1"
sleep 2
sgdisk --zap-all "$POOL_DISK2"
sleep 2
sgdisk --zap-all "$BOOT_DISK"
sleep 2
```
### Create EFI boot partition
```bash
sgdisk -n "${BOOT_PART}:1m:+512m" -t "${BOOT_PART}:ef00" "$BOOT_DISK"
sleep 2
```
### Create zpool partition
```bash
sgdisk -n "${POOL_PART}:0:-10m" -t "${POOL_PART}:bf00" "$POOL_DISK1"
sleep 2
sgdisk -n "${POOL_PART}:0:-10m" -t "${POOL_PART}:bf00" "$POOL_DISK2"
sleep 2
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
  zroot mirror "$POOL_DISK1" "$POOL_DISK2"
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

zfs create -o mountpoint=/var zroot/var 
zfs create -o mountpoint=/var/lib zroot/var/lib
zfs create -o mountpoint=/var/log zroot/var/log
zfs create -o mountpoint=/var/lib/libvirt zroot/var/lib/libvirt

zfs create -o mountpoint=/home zroot/home
zfs create -o mountpoint=/root zroot/home/root

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
zfs mount zroot/home/root
zfs mount zroot/var
zfs mount zroot/var/lib
zfs mount zroot/var/log
zfs mount zroot/var/lib/libvirt
```
#### Verify that everything is mounted correctly
```bash
mount | grep mnt
```
should return
```bash
zroot/ROOT/ubuntu on /mnt type zfs (rw,noatime,xattr,posixacl,casesensitive)
zroot/home on /mnt/home type zfs (rw,noatime,xattr,posixacl)
zroot/home/root on /mnt/root type zfs (rw,noatime,xattr,posixacl)
zroot/var on /mnt/var
zroot/var/lib on /mnt/var/lib
zroot/var/log on /mnt/var/log
zroot/var/lib/libvirt on /mnt/var/lib/libvirt
```
#### prevent `/root` directory access by others
```bash
chmod 700 /mnt/root
```
#### Update device symlinks
```bash
udevadm trigger
```

</details>
<details>
<summary>Install Ubuntu</summary>

```bash
debootstrap noble /mnt
```
### Copy files into the new install
```bash
cp /etc/hostid /mnt/etc
cp /etc/resolv.conf /mnt/etc
```
### Chroot into the new OS
```bash
mount -t proc proc /mnt/proc
mount -t sysfs sys /mnt/sys
mount -B /dev /mnt/dev
mount -t devpts pts /mnt/dev/pts
chroot /mnt /bin/bash
```

</details>
<details>
<summary>Basic Ubuntu Configuration</summary>

### Set a hostname
```bash
echo 'server' > /etc/hostname
echo -e '127.0.1.1\tserver' >> /etc/hosts
```
### Set a root password
```bash
passwd
```
### Configure `apt`. Use other mirrors if you prefer.
```bash
cat <<EOF > /etc/apt/sources.list
# Uncomment the deb-src entries if you need source packages

deb http://archive.ubuntu.com/ubuntu/ noble main restricted universe multiverse
# deb-src http://archive.ubuntu.com/ubuntu/ noble main restricted universe multiverse

deb http://archive.ubuntu.com/ubuntu/ noble-updates main restricted universe multiverse
# deb-src http://archive.ubuntu.com/ubuntu/ noble-updates main restricted universe multiverse

deb http://archive.ubuntu.com/ubuntu/ noble-security main restricted universe multiverse
# deb-src http://archive.ubuntu.com/ubuntu/ noble-security main restricted universe multiverse

deb http://archive.ubuntu.com/ubuntu/ noble-backports main restricted universe multiverse
# deb-src http://archive.ubuntu.com/ubuntu/ noble-backports main restricted universe multiverse
EOF
```
### Update the repository cache and system
```bash
apt update
apt upgrade -y
```
### Install additional base packages
```bash
apt install --no-install-recommends -y linux-generic locales keyboard-configuration console-setup
```
### Install additional not-so-base packages
```bash
apt install --no-install-recommends -y wget nano git make man-db
```
> [!NOTE]
> The `--no-install-recommends` flag is used here to avoid installing recommended, but not strictly needed, packages (including `grub2`).

### netplan DHCP setup
get ethernet interface
```bash
##get ethernet interface
export ethprefix="e"
export ethernetinterface="$(basename "$(find /sys/class/net -maxdepth 1 -mindepth 1 -name "${ethprefix}*")")"
echo "$ethernetinterface"
```
generate ethernet interface file
```bash
cat > /etc/netplan/01-"$ethernetinterface".yaml <<-EOF
  network:
    version: 2
    ethernets:
      $ethernetinterface:
        dhcp4: yes
EOF
# disable read from (g)roup and (o)thers
chmod go-r /etc/netplan/01-"$ethernetinterface".yaml
```
check and troubleshoot if there's any problem
```bash
netplan --debug generate
```
### Install openssh-server
```bash
apt install -y openssh-server
# -- uncomment to permit root login
# sed -i.bak -E 's/(^#PermitRootLogin )(.*)$/\1\2\nPermitRootLogin yes/g' /etc/ssh/sshd_config
```

### Configure packages to customize local and console properties
<details>
<summary>UI way</summary>
  
```bash
dpkg-reconfigure locales tzdata keyboard-configuration console-setup
```

</details>
<details>
<summary>Scripted way</summary>
  
#### set locale for `en_US.UTF-8`
```bash
export DEBIAN_FRONTEND=noninteractive

# 1. Ensure locales package is present
apt-get update && apt-get install -y locales

# 2. Generate the desired locale
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen

# 3. Set system-wide default locale
update-locale LANG=en_US.UTF-8

# 4. Apply locale to current shell
export LANG=en_US.UTF-8
export LANGUAGE=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# 5. (Optional) Confirm with:
locale
```

#### Set Time Zone to `Asia/Bangkok`
```bash
ln -sf /usr/share/zoneinfo/Asia/Bangkok /etc/localtime
dpkg-reconfigure -f noninteractive tzdata
```

#### Set keyboard to `us` qwerty
```bash
echo "keyboard-configuration keyboard-configuration/layoutcode string us" | debconf-set-selections
dpkg-reconfigure -f noninteractive keyboard-configuration
```
#### Set font sizes
```bash
echo "console-setup console-setup/fontface select Terminus" | debconf-set-selections
echo "console-setup console-setup/fontsize select 16x32" | debconf-set-selections
dpkg-reconfigure -f noninteractive console-setup
```
At 3840x2160 resolution and normal viewing distance (~60 cm), `Terminus` works well:
- 16x32 – large and very readable
- 12x24 – slightly smaller, still very sharp
- 10x20 – medium size, good for more content, still readable

<details>
<summary>Check locale, timezone, and keyboard</summary>

#### check locale
```bash
locale
```
#### check timezone
```bash
timedatectl
```
#### check keyboar layout
```bash
cat /etc/default/keyboard
```

</details>

> [!NOTE]
> You should always enable the `en_US.UTF-8` locale because some programs require it.

> [!NOTE]
> See also
>
> Any additional software should be selected and installed at this point. A basic debootstrap installation is very limited, lacking several packages that might be expected from an interactive installation.
  
</details>
<details>
<summary>ZFS Configuration</summary>

### Install required packages
```bash
apt install dosfstools zfs-initramfs zfsutils-linux
```
### Enable systemd ZFS services
```bash
systemctl enable zfs.target
systemctl enable zfs-import-cache
systemctl enable zfs-mount
systemctl enable zfs-import.target
```
### Configure `initramfs-tools`
Unencrypted pool -> No required steps

### Rebuild the initramfs
```bash
update-initramfs -c -k all
```

</details>
<details>
<summary>Install and configure ZFSBootMenu</summary>

### Set ZFSBootMenu properties on datasets
Assign command-line arguments to be used when booting the final kernel. Because ZFS properties are inherited, assign the common properties to the `ROOT` dataset so all children will inherit common arguments by default.
```bash
zfs set org.zfsbootmenu:commandline="quiet" zroot/ROOT
```
### Create a `vfat` filesystem
```bash
mkfs.vfat -F32 "$BOOT_DEVICE"
```
### Create an fstab entry and mount
```bash
cat << EOF >> /etc/fstab
$( blkid | grep "$BOOT_DEVICE" | cut -d ' ' -f 2 ) /boot/efi vfat defaults 0 0
EOF

mkdir -p /boot/efi
mount /boot/efi
```
### Install ZFSBootMenu
**Prebuilt**
```bash
apt install --no-install-recommends -y curl
```
Fetch a prebuilt ZFSBootMenu EFI executable, saving it to the EFI system partition:
```bash
mkdir -p /boot/efi/EFI/ZBM
curl -o /boot/efi/EFI/ZBM/VMLINUZ.EFI -L https://get.zfsbootmenu.org/efi
cp /boot/efi/EFI/ZBM/VMLINUZ.EFI /boot/efi/EFI/ZBM/VMLINUZ-BACKUP.EFI
```
### Configure EFI boot entries
```
mount -t efivarfs efivarfs /sys/firmware/efi/efivars
```
**Direct**
```bash
apt install -y efibootmgr
```
Mount `efivarfs` (If Missing)
- check
  ```bash
  mount | grep efivarfs
  ```
- if nothing appears, mount manually
  ```bash
  mount -t efivarfs efivarfs /sys/firmware/efi/efivars
  ```
then add boot entries
```bash
efibootmgr -c -d "$BOOT_DISK" -p "$BOOT_PART" \
  -L "ZFSBootMenu (Backup)" \
  -l '\EFI\ZBM\VMLINUZ-BACKUP.EFI'

efibootmgr -c -d "$BOOT_DISK" -p "$BOOT_PART" \
  -L "ZFSBootMenu" \
  -l '\EFI\ZBM\VMLINUZ.EFI'
```
> [!NOTE}
> See also
>
> Some systems can have issues with EFI boot entries. If you reboot and do not see the above entries in your EFI selection screen (usually accessible through an F key during POST), you might need to use a well-known EFI file name. See [Portable EFI](https://docs.zfsbootmenu.org/en/v2.3.x/general/portable.html) for help with this. Your existing ESP can be used, in place of an external USB drive.
>
> Refer to [zbm-kcl.8](https://docs.zfsbootmenu.org/en/v2.3.x/man/zbm-kcl.8.html) and [zfsbootmenu.7](https://docs.zfsbootmenu.org/en/v2.3.x/man/zfsbootmenu.7.html) for details on configuring the boot-time behavior of ZFSBootMenu.

</details>
<details>
<summary>set up non-root user</summary>

```
##6.6 create user account and setup groups
export USER="kadmin"
export PASSWORD="h"
zfs create -o mountpoint=/home/"$USER" zroot/home/${USER}
##gecos parameter disabled asking for finger info
adduser --disabled-password --gecos "" "$USER"
cp -a /etc/skel/. /home/"$USER"
chown -R "$USER":"$USER" /home/"$USER"
usermod -a -G adm,cdrom,dip,lpadmin,lxd,plugdev,sambashare,sudo "$USER"
printf $PASSWORD"\n"$PASSWORD | passwd $USER
```

</details>
<details>
<summary>set up `openssh-server`</summary>

```
apt install -y openssh-server
```

</details>
<details>
<summary>Prepare for first boot</summary>

### Exit the chroot, unmount everything
```bash
exit
```
```bash
umount -n -R /mnt
```
### Export the zpool and reboot
```bash
zpool export zroot
```
```bash
reboot
```

</details>
