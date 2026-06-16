#!/bin/bash
PATH="/usr/sbin:/usr/bin"

update_part() {
    partx -u "$1"
    udevadm trigger
    udevadm settle
}

# el  fdisk parted (el7part)
# ubuntu  fdisk growpart

# 
# el/ubuntu fdisk

# 
# el7 grownparted 
# el8/9/fedora parted
# ubuntu grownpart

# 
root_drive=$(mount | awk '$3=="/" {print $1}')
xda=$(lsblk -r --inverse "$root_drive" | grep -w disk | awk '{print $1}')

#  installer 
installer_num=$(readlink -f /dev/disk/by-label/installer | grep -o '[0-9]*$')
if [ -n "$installer_num" ]; then
    #  LC_NUMERIC %\%cron
    # locale -a "en_US.UTF-8""C.UTF-8"
    LC_NUMERIC="C.UTF-8"
    printf "d\n%s\nw" "$installer_num" | fdisk "/dev/$xda"
    update_part "/dev/$xda"
fi

# 
# el7  lsblk  --sort
# shellcheck disable=2012
part_num=$(ls -1v "/dev/$xda"* | tail -1 | grep -o '[0-9]*$')
part_fstype=$(lsblk -no FSTYPE "/dev/$xda"*"$part_num")

# 
# ubuntu  el7  growpart parted
# el7 partedfdisk PARTUUID growpart
if grep -E -i 'centos:7|ubuntu' /etc/os-release; then
    growpart "/dev/$xda" "$part_num"
else
    printf 'yes\n100%%' | parted "/dev/$xda" resizepart "$part_num" ---pretend-input-tty
fi
update_part "/dev/$xda"

# 
case $part_fstype in
xfs) xfs_growfs / ;;
ext*) resize2fs "/dev/$xda"*"$part_num" ;;
btrfs) btrfs filesystem resize max / ;;
esac
update_part "/dev/$xda"

# 
rm -f /resize.sh /etc/cron.d/resize
