#!/bin/bash

current_user=`whoami`

if [ ${current_user} !== "root" ] ; then
    echo "Please run this script as root"
    exit 1
fi

if [ $# != "1" ] ; then
    printf "Usage:\n\t$0 <target_device>\n"
    exit 1
fi

target_device=$1

root_partition=`mount | grep "on / " | awk '{print $1}'`
root_device=${root_partition%p*}
if [ ${root_device} == ${target_device} ] ; then
    echo "Cannot replicate to current root device ${root_device}"
    exit 1
fi

echo "Current device: ${root_device} Target device: ${target_device}"

target_partition=${target_device}p1

# Unmount if necessary
umount ${target_partition} || true

# Clear the first 32M
dd if=/dev/zero of=${target_device} bs=1M count=32 || (echo "erasing failed" && exit 1)

# Make the entire disk a Linux partition
sfdisk --in-order --Linux --unit M ${target_device} <<-__EOF__
1,,L,*
__EOF__

if [ $? != "0" ] ; then
    echo "sfdisk failed"
    exit 1
fi

mkfs.ext4 ${target_partition} -L PiggySting

umount ${target_partition}

# Write U-Boot as raw mode
dd if=/boot/MLO of=${target_device} bs=512 seek=256 count=256 conv=notrunc
dd if=/boot/u-boot.img of=${target_device} bs=512 seek=768 count=1024 conv=notrunc
blockdev --flushbufs ${target_device}

## Mount target device
mount ${target_partition} /mnt
scripts_dir="/mnt/opt/scripts/"

# Install u-boot
mkdir -p /mnt/boot
cp -v /boot/MLO /mnt/boot/
cp -v /boot/u-boot.img /mnt/boot/
# Record kernel version
cp -v /boot/kernel_version /mnt/boot/
kernel_version=`cat /boot/kernel_version`
# Install Linux kernel
cp -v /boot/vmlinuz-${kernel_version} /mnt/boot/
# Save kernel config file
cp -v /mnt/boot/config-${kernel_version} /mnt/boot/
# Install Device Tree
tar xfv /opt/scripts/${kernel_version}-dtbs.tar.gz -C /mnt/boot/dtbs/${kernel_version}/
# Install kernel modules
tar xfv /opt/scripts/${kernel_version}-modules.tar.gz -C /mnt/
# Install Ubuntu Core rootfs
tar zxvpf /opt/scripts/${rootfs_archive} -C /mnt
# Configure fstab
sh -c "echo '/dev/mmcblk0p1  /  auto  errors=remount-ro  0  1' >> /mnt/etc/fstab"
# Configure serial
cp -v ${root_dir}/serial.conf /mnt/etc/init/serial.conf

