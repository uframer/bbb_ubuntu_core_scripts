#!/bin/bash

current_user=`whoami`

if [ ${current_user} != "root" ] ; then
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

# Check sfdisk's version
sfdisk_old_version=0
sfdisk --help | grep -m 1 -e "--in-order" > /dev/null && sfdisk_old_version=1
# Make the entire disk a Linux partition
if [ $sfdisk_old_version == "1" ] ; then

sudo sfdisk --force --in-order --Linux --unit M ${target_device} <<-__EOF__
1,,L,*
__EOF__

else

sudo sfdisk --force ${target_device} <<-__EOF__
1M,,L,*
__EOF__

fi

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

# Mount target device
mount ${target_partition} /mnt

# Copy system rootfs
rsync -aAx /* /mnt/ --exclude={/dev/*,/proc/*,/sys/*,/tmp/*,/run/*,/mnt/*,/media/*,/lost+found}

if [ -d /mnt/etc/ssh/ ] ; then
    touch /mnt/etc/ssh/ssh.regenerate
fi

root_uuid=$(/sbin/blkid -c /dev/null -s UUID -o value ${target_device}p1)
if [ "${root_uuid}" ] ; then
    sed -i -e 's:uuid=:#uuid=:g' /mnt/boot/uEnv.txt
    echo "uuid=${root_uuid}" >> /mnt/boot/uEnv.txt

    root_uuid="UUID=${root_uuid}"
else
    echo "Failed to get root_uuid"
    exit 1
fi

echo "args_mmc_old=setenv bootargs console=\${console} \${optargs} \${cape_disable} \${cape_enable} root=/dev/mmcblk0p1 ro rootfstype=\${mmcrootfstype} \${cmdline}" >> /mnt/boot/uEnv.txt

echo "${root_uuid}  /  ext4  noatime,errors=remount-ro  0  1" > /mnt/etc/fstab
echo "debugfs  /sys/kernel/debug  debugfs  defaults  0  0" >> /mnt/etc/fstab

sync
blockdev --flushbufs ${target_device}
echo "Replication done. Please unplug the SD card if necessary then reboot."
