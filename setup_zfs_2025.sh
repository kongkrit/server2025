#!/bin/bash

## server2025
set -x

## parameters
ZPOOL_ASHIFT="13"
ZFS_COMPRESSION="lz4"
ROOTZFS_FULL_NAME="ubuntu-$(date +%Y-%m-%d)"
HOSTNAME="server"
## root password
ROOT_PASSWORD="r"
## admin account
USER="kadmin"
PASSWORD="h"
## set DEBUG to non empty to pauses
DEBUG=yes

debugm() {
  echo "$1"
  if [[ -n "$DEBUG" ]]; then
    read -r _
  fi
}

echo "Check for root priviliges"
if [ "$(id -u)" -ne 0 ]; then
   echo "Please run as root."
   exit 1
fi

echo "Confirm EFI support:"
if test -d /sys/firmware/efi; then
   echo "found efi boot environment"
else
   echo "booted up in bios, not efi. script requires EFI booting."
   exit 1
fi

echo "source etc/os-release to get ID"
source /etc/os-release
## export ID

echo "Install helpers"
apt update
apt install -y debootstrap gdisk zfsutils-linux

echo "Generate /etc/hostid"
zgenhostid -f 0x00bab10c

### Define disk variables

## For convenience and to reduce the likelihood of errors, set environment variables that refer to the devices that will be configured during the setup.

## For many users, it is most convenient to place boot files (i.e., ZFSBootMenu and any loader responsible for launching it) on the the same disk that will hold the ZFS pool. However, some users may wish to dedicate an entire disk to the ZFS pool or create a multi-disk pool. A USB flash drive provides a convenient location for the boot partition. Fortunately, this alternative configuration is easily realized by simply defining a few environment variables differently.

## Verify your target disk devices with lsblk. /dev/sda, /dev/sdb and /dev/nvme0n1 used below are examples.

#### Get disk by id first

getdiskID(){
	##Get root Disk UUID
	ls -la /dev/disk/by-id
	echo "Enter Disk ID (must match exactly):"
	read -r DISKID
	#DISKID=ata-VBOX_HARDDISK_VBXXXXXXXX-XXXXXXXX ##manual override
	##error check
	errchk="$(find /dev/disk/by-id -maxdepth 1 -mindepth 1 -name "$DISKID")"
	if [ -z "$errchk" ];
	then
		echo "Disk ID not found. Exiting."
		exit 1
	fi
	echo "Disk ID set to ""$DISKID"""
}

getDiskIDs(){

	checkDiskById() {
		read -r NAME
	        errchk="$(find /dev/disk/by-id -maxdepth 1 -mindepth 1 -name "$NAME")"
        	if [ -z "$errchk" ]; then
                	echo "Disk ID not found. Exiting."
                	exit 1
        	fi
		echo $NAME
	}

	##Get Disk UUIDs
	ls -la /dev/disk/by-id
	echo "Enter Disk ID for EFI:"
	BOOT_DISK=$(checkDiskById)
	ls -la /dev/disk/by-id
	echo "Enter Disk ID for ZFS (1 of 2):"
	POOL_DISK1=$(checkDiskById)
	ls -la /dev/disk/by-id
	echo "Enter Disk ID for ZFS (2 of 2):"
	POOL_DISK2=$(checkDiskById)

	cat <<-EOF
 	BOOT_DISK=$BOOT_DISK
 	POOL_DISK1=$POOL_DISK1
 	POOL_DISK2=$POOL_DISK2
 	Please confirm with enter or break with ctrl-c
	EOF

	if [ "$BOOT_DISK" = "$POOL_DISK1" ]; then
		echo "ERROR: disk ids are not all unique!";
		exit 1
	fi
	if [ "$BOOT_DISK" = "$POOL_DISK2" ]; then
		echo "ERROR: disk ids are not all unique!";
		exit 1
	fi
	if [ "$POOL_DISK1" = "$POOL_DISK2" ]; then
		echo "ERROR: disk ids are not all unique!"
		exit 1
	fi
}

echo "get all Disk IDs"
getDiskIDs
read -r _

BOOT_PART="1"
BOOT_DISK="/dev/disk/by-id/${BOOT_DISK}"
BOOT_DEVICE="${BOOT_DISK}-part${BOOT_PART}"

POOL_DISK1="/dev/disk/by-id/${POOL_DISK1}"
POOL_DISK2="/dev/disk/by-id/${POOL_DISK2}"
POOL_PART="1"
POOL_DEVICE1="${POOL_DISK1}-part${POOL_PART}"
POOL_DEVICE2="${POOL_DISK2}-part${POOL_PART}"

cat <<-EOF
	BOOT_PART=${BOOT_PART}
 	BOOT_DISK=${BOOT_DISK}
	BOOT_DEVICE=${BOOT_DEVICE}
 
	POOL_DISK1=${POOL_DISK1}
	POOL_DISK2=${POOL_DISK2}
	POOL_PART=${POOL_PART}
	POOL_DEVICE1=${POOL_DEVICE1}
	POOL_DEVICE2=${POOL_DEVICE2}
EOF

debugm "--about to wipe partitions"

echo "Wipe partitions"
zpool labelclear -f "$POOL_DISK1"
sleep 2
zpool labelclear -f "$POOL_DISK2"
sleep 2
echo "  failed to clear label error is ok"

wipefs -a "$POOL_DISK1"
sleep 2
wipefs -a "$POOL_DISK2"
sleep 2
wipefs -a "$BOOT_DISK"
sleep 2

sgdisk --zap-all "$POOL_DISK1"
sleep 2
sgdisk --zap-all "$POOL_DISK2"
sleep 2
sgdisk --zap-all "$BOOT_DISK"
sleep 2

echo "Create EFI boot partition"
sgdisk -n "${BOOT_PART}:1M:+512M" -t "${BOOT_PART}:ef00" "$BOOT_DISK"
sleep 2

## echo "Create zpool partition"
sgdisk -n "${POOL_PART}:0:-10m" -t "${POOL_PART}:bf00" "$POOL_DISK1"
sleep 2
sgdisk -n "${POOL_PART}:0:-10m" -t "${POOL_PART}:bf00" "$POOL_DISK2"
sleep 2

debugm "--done zapping disks--"

echo "Create the zpool"

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

## > [!NOTE]
## > The option -o compatibility=openzfs-2.1-linux is a conservative choice. It can be omitted or otherwise adjusted to match your specific system needs.
## >
## > Binary releases of ZFSBootMenu are generally built with the latest stable release of ZFS. Future releases of ZFSBootMenu may therefore support newer feature sets. Check project release notes prior to updating or removing compatibility options and upgrading your system pool.

echo "Create initial file systems"
echo "  ROOTZFS_FULL_NAME is ${ROOTZFS_FULL_NAME}"

zfs create -o mountpoint=none zroot/ROOT

zfs create -o mountpoint=/ -o canmount=noauto zroot/ROOT/${ROOTZFS_FULL_NAME}

zfs create -o mountpoint=/var zroot/var 
zfs create -o mountpoint=/var/lib zroot/var/lib
zfs create -o mountpoint=/var/log zroot/var/log
zfs create -o mountpoint=/var/lib/libvirt zroot/var/lib/libvirt

zfs create -o mountpoint=/var/lib/docker zroot/var/lib/docker
zfs create -o mountpoint=/var/lib/containers zroot/var/lib/containers

zfs create -o mountpoint=/home zroot/home
zfs create -o mountpoint=/root zroot/home/root

zpool set bootfs=zroot/ROOT/${ROOTZFS_FULL_NAME} zroot

echo " exclude /var/cache, /var/tmp, /var/lib/docker, /var/lib/containers from snapshot"
zfs create -o com.sun:auto-snapshot=false zroot/var/cache
zfs create -o com.sun:auto-snapshot=false zroot/var/tmp
zfs create -o com.sun:auto-snapshot=false zroot/var/lib/docker
zfs create -o com.sun:auto-snapshot=false zroot/var/lib/containers
chmod 1777 /mnt/var/tmp

## > [!NOTE]
## > It is important to set the property canmount=noauto on any file systems with mountpoint=/ (that is, on any additional boot environments you create). Without this property, the OS will attempt to automount all ZFS file systems and fail when multiple file systems attempt to mount at /; this will prevent your system from booting. Automatic mounting of / is not required because the root file system is explicitly mounted in the boot process.
## >
## > Also note that, unlike many ZFS properties, canmount is not inheritable. Therefore, setting canmount=noauto on zroot/ROOT is not sufficient, as any subsequent boot environments you create will default to canmount=on. It is necessary to explicitly set the canmount=noauto on every boot environment you create.

echo "Export, then re-import with a temporary mountpoint of /mnt"
zpool export zroot
zpool import -N -R /mnt zroot
zfs mount zroot/ROOT/${ROOTZFS_FULL_NAME}
zfs mount zroot/home
zfs mount zroot/home/root
zfs mount zroot/var
zfs mount zroot/var/lib
zfs mount zroot/var/log
zfs mount zroot/var/lib/libvirt
zfs mount zroot/var/lib/docker
zfs mount zroot/var/lib/containers

echo "Verify that everything is mounted correctly"
mount | grep mnt
cat <<-EOF
	the above should return
	zroot/ROOT/ubuntu on /mnt type zfs (rw,noatime,xattr,posixacl,casesensitive)
	zroot/home on /mnt/home type zfs (rw,noatime,xattr,posixacl)
	zroot/home/root on /mnt/root type zfs (rw,noatime,xattr,posixacl)
	zroot/var on /mnt/var
	zroot/var/lib on /mnt/var/lib
	zroot/var/log on /mnt/var/log
	zroot/var/lib/libvirt on /mnt/var/lib/libvirt
	zroot/var/lib/docker on /mnt/var/lib/docker
	zroot/var/lib/containers on /mnt/var/lib/containers
EOF

echo "prevent /root directory access by others"
chmod 700 /mnt/root

echo "Update device symlinks"
udevadm trigger

debugm "--ready to install ubuntu--"

echo "Install Ubuntu"
debootstrap noble /mnt
echo "Copy files into the new install"
cp /etc/hostid /mnt/etc
cp /etc/resolv.conf /mnt/etc

echo "Chroot into the new OS"
mount -t proc proc /mnt/proc
mount -t sysfs sys /mnt/sys
mount -B /dev /mnt/dev
mount -t devpts pts /mnt/dev/pts

chroot /mnt /bin/bash -x <<-EOCHROOT
	echo 'server' > /etc/hostname
	echo -e '127.0.1.1\tserver' >> /etc/hosts

	echo "set root password"
	passwd
EOCHROOT

echo "Configure apt. Use other mirrors if you prefer."
cat <<-EOF > /mnt/etc/apt/sources.list
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

echo "Update the repository cache and system"
chroot /mnt /bin/bash -x <<-EOCHROOT
	apt update
	apt upgrade -y
EOCHROOT

echo "Install additional base packages"
chroot /mnt /bin/bash -x <<-EOCHROOT
	apt install --no-install-recommends -y linux-generic locales keyboard-configuration console-setup
EOCHROOT

echo "Install additional not-so-base packages"
chroot /mnt /bin/bash -x <<-EOCHROOT
	apt install --no-install-recommends -y wget nano git make man-db
EOCHROOT

## > [!NOTE]
## > The --no-install-recommends flag is used here to avoid installing recommended, but not ## strictly needed, packages (including grub2).

echo "netplan DHCP setup"
echo "  get ethernet interface"

## need heredoc in chroot below
chroot /mnt /bin/bash -x <<-'EOCHROOT'
	export ethprefix="e"
	export ethernetinterface="$(basename "$(find /sys/class/net -maxdepth 1 -mindepth 1 -name "${ethprefix}*")")"
	echo "$ethernetinterface"

	echo "  generate ethernet interface file"
	cat > /etc/netplan/01-"$ethernetinterface".yaml <<-EOF
		network:
		  version: 2
		  ethernets:
		  $ethernetinterface:
		    dhcp4: yes
	EOF
	echo "  disable read from (g)roup and (o)thers"
	chmod go-r /etc/netplan/01-"$ethernetinterface".yaml
EOCHROOT

echo "  check and troubleshoot if there's any problem"
chroot /mnt /bin/bash -x <<-EOCHROOT
	netplan --debug generate
EOCHROOT

echo "  Install openssh-server"
chroot /mnt /bin/bash -x <<-EOCHROOT
	apt install -y openssh-server
	# -- uncomment to permit root login
	# sed -i.bak -E 's/(^#PermitRootLogin )(.*)$/\1\2\nPermitRootLogin yes/g' /etc/ssh/sshd_config
EOCHROOT

debugm "--about to do locale timezone console fonts--"

echo "  Configure packages to customize locale and console properties"
echo "    Scripted way"
  
echo "    set locale for en_US.UTF-8"
chroot /mnt /bin/bash -x <<-EOCHROOT
	export DEBIAN_FRONTEND=noninteractive

	echo "    1. Ensure locales package is present"
	apt-get update && apt-get install -y locales

	echo "    2. Generate the desired locale"
	echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
	locale-gen

	echo "    3. Set system-wide default locale"
	update-locale LANG=en_US.UTF-8

	echo "    4. Apply locale to current shell"
	export LANG=en_US.UTF-8
	export LANGUAGE=en_US.UTF-8
	export LC_ALL=en_US.UTF-8

	echo "    5. (Optional) Confirm with locale:"
	locale
EOCHROOT

echo "  Set Time Zone to Asia/Bangkok"
chroot /mnt /bin/bash -x <<-EOCHROOT
	ln -sf /usr/share/zoneinfo/Asia/Bangkok /etc/localtime
	dpkg-reconfigure -f noninteractive tzdata
EOCHROOT

echo "  Set keyboard to US qwerty"
chroot /mnt /bin/bash -x <<-EOCHROOT
	echo "keyboard-configuration keyboard-configuration/layoutcode string us" | debconf-set-selections
	dpkg-reconfigure -f noninteractive keyboard-configuration
EOCHROOT

echo "    Set font sizes"
chroot /mnt /bin/bash -x <<-EOCHROOT
	echo "console-setup console-setup/fontface select Terminus" | debconf-set-selections
	echo "console-setup console-setup/fontsize select 16x32" | debconf-set-selections
	dpkg-reconfigure -f noninteractive console-setup
EOCHROOT
## At 3840x2160 resolution and normal viewing distance (~60 cm), Terminus works well:
## - 16x32 – large and very readable
## - 12x24 – slightly smaller, still very sharp
## - 10x20 – medium size, good for more content, still readable

echo "  Check locale, timezone, and keyboard"
chroot /mnt /bin/bash -x <<-EOCHROOT
	echo "  check locale"
	locale
	echo "  check timezone"
	date

	echo "  check keyboard layout"
	cat /etc/default/keyboard
EOCHROOT
## > [!NOTE]
## > You should always enable the en_US.UTF-8 locale because some programs require it.
## 
## > [!NOTE]
## > See also
## >
## > Any additional software should be selected and installed at this point. A basic debootstrap installation is very limited, lacking several packages that might be expected from an interactive installation.

debugm "--about to do ZFS configuration--"

echo "ZFS Configuration"

echo "  Install required packages"
chroot /mnt /bin/bash -x <<-EOCHROOT
	apt install -y dosfstools zfs-initramfs zfsutils-linux

	echo "  Enable systemd ZFS services"
	systemctl enable zfs.target
	systemctl enable zfs-import-cache
	systemctl enable zfs-mount
	systemctl enable zfs-import.target
EOCHROOT
cat <<EOF
You can safely ignore -Running in chroot, ignoring command -daemon-reload- when running systemctl inside a chroot or non-systemd environment (such as minimal install, live environment, or container without full init).
EOF

echo "Configure initramfs-tools"
echo "  Unencrypted pool -> No required steps"

echo "Rebuild the initramfs"
chroot /mnt /bin/bash -x <<-EOCHROOT
	update-initramfs -c -k all
EOCHROOT

debugm "--about to install ZFSBootMenu--"

echo "Install and configure ZFSBootMenu"

### Set ZFSBootMenu properties on datasets
## Assign command-line arguments to be used when booting the final kernel. Because ZFS properties are inherited, assign the common properties to the ROOT dataset so all children will inherit common arguments by default.
chroot /mnt /bin/bash -x <<-EOCHROOT
	## quiet version -- zfs set org.zfsbootmenu:commandline="quiet" zroot/ROOT
	zfs set org.zfsbootmenu:commandline="" zroot/ROOT
EOCHROOT

echo "Create a vfat filesystem"
# env BOOT_DEVICE="$BOOT_DEVICE" chroot /mnt /bin/bash <<-EOCHROOT
chroot /mnt /bin/bash <<-EOCHROOT
	mkfs.vfat -F32 "${BOOT_DEVICE}"
EOCHROOT

echo "  Create an fstab entry and mount"
chroot /mnt /bin/bash -x <<-EOCHROOT
	cat <<-EOF >> /etc/fstab
		$( blkid "$BOOT_DEVICE" | grep "$BOOT_DEVICE" | cut -d ' ' -f 2 ) /boot/efi vfat defaults 0 0
	EOF

	mkdir -p /boot/efi
	mount /boot/efi
EOCHROOT

echo "Install ZFSBootMenu (prebuilt)"
chroot /mnt /bin/bash -x <<-EOCHROOT
	apt install --no-install-recommends -y curl
EOCHROOT
echo "  Fetch a prebuilt ZFSBootMenu EFI executable, saving it to the EFI system partition:"
chroot /mnt /bin/bash -x <<-EOCHROOT
	mkdir -p /boot/efi/EFI/ZBM
	curl -o /boot/efi/EFI/ZBM/VMLINUZ.EFI -L https://get.zfsbootmenu.org/efi
	cp /boot/efi/EFI/ZBM/VMLINUZ.EFI /boot/efi/EFI/ZBM/VMLINUZ-BACKUP.EFI
EOCHROOT

echo "  Configure EFI boot entries"
chroot /mnt /bin/bash -x <<-EOCHROOT
	mount -t efivarfs efivarfs /sys/firmware/efi/efivars
EOCHROOT
echo "  **Direct**"
chroot /mnt /bin/bash -x <<-EOCHROOT
	apt install -y efibootmgr
EOCHROOT
echo "  Mount efivarfs (If Missing)"
echo "  check mount for efivars results between dashed lines"

## need heredoc in chroot below
chroot /mnt /bin/bash -x <<-'EOCHROOT'
	EMPTYEFIVARFS=$(mount | grep efivarfs)
	if [[ -z "$EMPTYEFIVARFS" ]]; then
	  echo "  empty result, mount"
	  mount -t efivarfs efivarfs /sys/firmware/efi/efivars
	else
	  echo "  non empty result, do nothing"
	fi
EOCHROOT

echo "  add boot entries"
chroot /mnt /bin/bash -x <<-EOCHROOT
	efibootmgr -c -d "$BOOT_DISK" -p "$BOOT_PART" \
	  -L "ZFSBootMenu (Backup)" \
	  -l '\EFI\ZBM\VMLINUZ-BACKUP.EFI' \
	  -u "timeout=3"

	efibootmgr -c -d "$BOOT_DISK" -p "$BOOT_PART" \
	  -L "ZFSBootMenu" \
	  -l '\EFI\ZBM\VMLINUZ.EFI' \
	  -u "timeout=3"
EOCHROOT
## > [!NOTE}
## > See also
## >
## > Some systems can have issues with EFI boot entries. If you reboot and do not see the above entries in your EFI selection screen (usually accessible through an F key during POST), you might need to use a well-known EFI file name. See [Portable EFI](https://docs.zfsbootmenu.org/en/v2.3.x/general/portable.html) for help with this. Your existing ESP can be used, in place of an external USB drive.
## >
## > Refer to [zbm-kcl.8](https://docs.zfsbootmenu.org/en/v2.3.x/man/zbm-kcl.8.html) and [zfsbootmenu.7](https://docs.zfsbootmenu.org/en/v2.3.x/man/zfsbootmenu.7.html) for details on configuring the boot-time behavior of ZFSBootMenu.

debugm "--about to set root password--"

echo "set root password"
chroot /mnt /bin/bash -x <<-EOCHROOT
	printf $ROOT_PASSWORD"\n"$ROOT_PASSWORD | passwd
EOCHROOT

echo "set up non-root user"
chroot /mnt /bin/bash -x <<-EOCHROOT
	zfs create -o mountpoint=/home/"$USER" zroot/home/${USER}
	## gecos parameter disabled asking for finger info
	adduser --disabled-password --gecos "" "$USER"
	cp -a /etc/skel/. /home/"$USER"
	chown -R "$USER":"$USER" /home/"$USER"
	usermod -a -G adm,cdrom,dip,lpadmin,lxd,plugdev,sambashare,sudo "$USER"
	printf $PASSWORD"\n"$PASSWORD | passwd $USER
EOCHROOT

echo "  double check whether /home/"$USER" belongs to $USER"
chroot /mnt /bin/bash -x <<-EOCHROOT
	ls -al /home
EOCHROOT

echo "Prepare for first boot"

### Exit the chroot, unmount everything
## exit

echo "  unmount everything"
umount -n -R /mnt

echo "Export the zpool"
zpool export zroot

echo ""
echo "You may reboot with reboot command"
## reboot
