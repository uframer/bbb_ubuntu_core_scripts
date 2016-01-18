#!/bin/bash

# This script is designed to construct a bootable ubnutu core system on SD card for Beaglebone Black.

root_dir=$PWD

if [ $# != "2" ] ; then
    echo "Usage: $0 <target_dir> <target_device>"
    exit 1
fi

# Workspace
target_dir=$1
# Device file for SD card
target_device=$2

mkdir -p ${target_dir}
cd ${target_dir}
# Use absolute path of target_dir
target_dir=$PWD

# TODO: check target device
# check if it is current rootfs

# Use my fork from Robert Nelson's script to build u-boot
# My fork added the ability to specify target board on command line.
cd ${target_dir}
uboot_builder_script=uboot_builder_script
if [ -d ${uboot_builder_script} ] ; then
    cd ${uboot_builder_script}
    git pull
else
    git clone https://github.com/uframer/Bootloader-Builder.git ${uboot_builder_script}
    cd ${uboot_builder_script}
fi

need_rebuild_uboot=0
if [ ! -f deploy/am335x_boneblack/MLO-am335x_boneblack-v2015.10-r12 ] ; then
    need_rebuild_uboot=1
fi
if [ ! -f deploy/am335x_boneblack/u-boot-am335x_boneblack-v2015.10-r12.img ] ; then
    need_rebuild_uboot=1
fi
if [ ${need_rebuild_uboot} == "1" ] ; then
    ./build.sh am335x_boneblack_flasher
fi
cp -f deploy/am335x_boneblack/MLO-am335x_boneblack-v2015.10-r12 ${target_dir}/MLO
cp -f deploy/am335x_boneblack/u-boot-am335x_boneblack-v2015.10-r12.img ${target_dir}/u-boot.img

# Clone Linus's Linux kernel repository to try to save some loading for repetitive compilation.
torvalds_linux="https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git"
local_linux_source="${HOME}/linux-src/"
if [ ! -f "${local_linux_source}/.git/config" ] ; then
    rm -rf ${local_linux_source}
    git clone ${torvalds_linux} ${local_linux_source}
fi

# Use my fork from Robert Nelson's script to build Linux kernel
cd ${target_dir}
linux_builder_script=linux_builder_script
if [ -d ${linux_builder_script} ] ; then
    cd ${linux_builder_script}
    git pull
else
    git clone https://github.com/uframer/armv7-multiplatform.git ${linux_builder_script}
    cd ${linux_builder_script}
fi

# Checkout v4.3.x branch
# v4.3.x is the highest stable kernel version currently, we may update this as the kernel evolve.
git branch -d build
git checkout remotes/origin/v4.3.x -b build

if [ -f kernel_version ] ; then
    kernel_version=`cat kernel_version`
    need_rebuild_linux=0
    if [ ! -f deploy/${kernel_version}.zImage ] ; then
        need_rebuild_linux=1
    fi
    if [ ! -f deploy/${kernel_version}-dtbs.tar.gz ] ; then
        need_rebuild_linux=1
    fi
    if [ ! -f deploy/${kernel_version}-modules.tar.gz ] ; then
        need_rebuild_linux=1
    fi
    if [ ! -f deploy/config-${kernel_version} ] ; then
        need_rebuild_linux=1
    fi
else
    need_rebuild_linux=1
fi

if [ ${need_rebuild_linux} == "1" ] ; then
    echo "Need to build Linux kernel"
    AUTO_BUILD=1 LINUX_GIT="${local_linux_source}" ./build_kernel.sh
else
  echo "Linux kernel was built before, skip this phase"
fi

# Export kernel version, we need this to copy kernel files later.
unset kernel_version
kernel_version=`cat kernel_version`
echo "kernel_version=${kernel_version}"
export kernel_version

# Download Ubuntu Core rootfs
cd ${target_dir}
ubuntu_core_dir=ubuntu_core_dir
mkdir -p ${ubuntu_core_dir}
cd ${ubuntu_core_dir}
# 14.04 LTS is the only suppored release of ROS
rootfs_archive="ubuntu-core-14.04-core-armhf.tar.gz"
rootfs_url_prefix="http://cdimage.ubuntu.com/ubuntu-core/releases/14.04.3/release/"
if [ ! -f ${rootfs_archive} ] ; then
    wget ${rootfs_url_prefix}/SHA1SUMS
    wget ${rootfs_url_prefix}/${rootfs_archive}
fi
# Check SHA1
grep armhf SHA1SUMS | sha1sum -c
if [ $? != "0" ] ; then
    echo "rootfs verification failed, please delete intermediate file and retry"
    exit 1
fi

# Prepare target disk
cd ${target_dir}
file ${target_device} | grep block
if [ $? != "0" ] ; then
    echo "Target device ${target_device} does not exist"
    exit 1
fi

sudo umount ${target_device}1

# Clear the first 32M defensively
sudo dd if=/dev/zero of=${target_device} bs=1M count=32
if [ $? != "0" ] ; then
    echo "erasing failed"
    exit 1
fi

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

sudo mkfs.ext4 ${target_device}1 -L PiggySting

sudo umount ${target_device}1

# Install U-Boot as raw mode
sudo dd if=MLO of=${target_device} bs=512 seek=256 count=256 conv=notrunc
sudo dd if=u-boot.img of=${target_device} bs=512 seek=768 count=1024 conv=notrunc
sudo blockdev --flushbufs ${target_device}

## Mount target device
sudo mount ${target_device}1 /mnt
# Copy u-boot to /boot
sudo mkdir -p /mnt/boot
sudo cp -v ${target_dir}/MLO /mnt/boot/
sudo cp -v ${target_dir}/u-boot.img /mnt/boot/
sudo echo ${kernel_version} > /mnt/boot/kernel_version
# With u-boot v2014.07 and the corresponding patches from Robert Nelson, each partition
# of the SD card will be searched for an environment file under /boot/uEnv.txt. If an
# uEnv.txt file is found, its contents are imported.
# The name of a dtb file may be set with the variable 'dtb' within the uEnv.txt file.
#
# Furthermore, if 'uname_r' is specified, a compressed kernel binary (zImage) is
# assumed to be in /boot/vmlinuz-{uname_r}, and 'run uname_boot' is executed, at the
# end of which 'run mmcargs' is executed.
#
# Therefore, if you want to completely override the boot process, you would need
# to override 'uname_boot' within this file.
#
# The boot command is defined in include/configs/am335x_evm.h's CONFIG_BOOTCOMMAND
sudo sh -c "echo 'uname_r=${kernel_version}' >> /mnt/boot/uEnv.txt"
# Install Linux kernel
sudo cp -v ${target_dir}/${linux_builder_script}/deploy/${kernel_version}.zImage /mnt/boot/vmlinuz-${kernel_version}
# Save kernel config file
sudo cp -v ${target_dir}/${linux_builder_script}/deploy/config-${kernel_version} /mnt/boot/
# Install Device Tree
sudo mkdir -p /mnt/boot/dtbs/${kernel_version}/
sudo tar xfv ${target_dir}/${linux_builder_script}/deploy/${kernel_version}-dtbs.tar.gz -C /mnt/boot/dtbs/${kernel_version}/
# Install kernel modules
sudo tar xfv ${target_dir}/${linux_builder_script}/deploy/${kernel_version}-modules.tar.gz -C /mnt/
# Install Ubuntu Core rootfs
sudo tar zxvpf ${target_dir}/${ubuntu_core_dir}/${rootfs_archive} -C /mnt
# Configure fstab
# Set noatime to reduce disk IO and extend eMMC's lifetime
sudo sh -c "echo '/dev/mmcblk0p1  /  ext4  noatime,errors=remount-ro  0  1' >> /mnt/etc/fstab"
# Configure serial
sudo cp -v ${root_dir}/serial.conf /mnt/etc/init/serial.conf

# We need qemu-arm-static to run armhf rootfs via binfmt_misc
sudo cp -v /usr/bin/qemu-arm-static /mnt/usr/bin/
# Copy host's dns configuration to target
sudo cp -b /etc/resolv.conf /mnt/etc/resolv.conf
# Prepare scripts to run in chroot environment
scripts_dir="/opt/scripts/"
target_scripts_dir=/mnt/${scripts_dir}
sudo mkdir -p ${target_scripts_dir}
sudo cp -v ${root_dir}/construct_rootfs.sh ${target_scripts_dir}
sudo cp -v ${root_dir}/package.list ${target_scripts_dir}
sudo cp -v ${root_dir}/replicate.sh ${target_scripts_dir}
sudo chmod u+x ${target_scripts_dir}/replicate.sh
# Mount necessary fs
sudo mount -t proc /proc /mnt/proc
sudo mount -t sysfs /sys /mnt/sys
sudo mount -o bind /dev /mnt/dev
sudo mount -o bind /dev/pts /mnt/dev/pts
# chroot!
sudo LC_ALL=C chroot /mnt /bin/bash ${scripts_dir}/construct_rootfs.sh
# Clean up
sudo rm /mnt/usr/bin/qemu-arm-static
sudo umount /mnt/proc
sudo umount /mnt/sys
sudo umount /mnt/dev/pts
sudo umount /mnt/dev
sudo umount /mnt

cd ${root_dir}
