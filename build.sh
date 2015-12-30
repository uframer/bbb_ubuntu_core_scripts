#!/bin/bash

root_dir=$PWD

if [ $# != "2" ] ; then
    echo "Usage: $0 <target_dir> <target_device>"
    exit 1
fi

target_dir=$1
target_device=$2

mkdir -p ${target_dir}
cd ${target_dir}
target_dir=$PWD

# TODO: check target device
# 1. check existence
# 2. check if it is current rootfs

# Use my fork from Robert Nelson's script to build u-boot
cd ${target_dir}
uboot_builder_script=uboot_builder_script
git clone https://github.com/uframer/Bootloader-Builder.git ${uboot_builder_script}
cd ${uboot_builder_script}
./build.sh am335x_boneblack_flasher
cp -f deploy/am335x_boneblack/MLO-am335x_boneblack-v2015.10-r12 ${target_dir}/MLO
cp -f deploy/am335x_boneblack/u-boot-am335x_boneblack-v2015.10-r12.img ${target_dir}/u-boot.img

# Clone Linus's Linux kernel repository
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
git branch -d build
git checkout remotes/origin/v4.3.x -b build

need_rebuild_linux=0
if [ ! -f deploy/4.3.3-armv7-x1.zImage ] ; then
  need_rebuild_linux=1
fi
if [ ! -f deploy/4.3.3-armv7-x1-dtbs.tar.gz ] ; then
  need_rebuild_linux=1
fi
if [ ! -f deploy/4.3.3-armv7-x1-firmware.tar.gz ] ; then
  need_rebuild_linux=1
fi
if [ ! -f deploy/4.3.3-armv7-x1-modules.tar.gz ] ; then
  need_rebuild_linux=1
fi
if [ ! -f deploy/config-4.3.3-armv7-x1 ] ; then
  need_rebuild_linux=1
fi

if [ ${need_rebuild_linux} == "1" ] ; then
  echo "Need to build Linux kernel"
  AUTO_BUILD=1 LINUX_GIT="${local_linux_source}" ./build_kernel.sh
else
  echo "Linux kernel was built before, skip this phase"
fi

cp -f deploy/4.3.3-armv7-x1.zImage ${target_dir}/
cp -f deploy/4.3.3-armv7-x1-dtbs.tar.gz ${target_dir}/
cp -f deploy/4.3.3-armv7-x1-firmware.tar.gz ${target_dir}/
cp -f deploy/4.3.3-armv7-x1-modules.tar.gz ${target_dir}/
cp -f deploy/config-4.3.3-armv7-x1 ${target_dir}/
unset kernel_version
kernel_version=`cat kernel_version`
echo "kernel_version=${kernel_version}"
export kernel_version

# Download Ubuntu Core rootfs
cd ${target_dir}
ubuntu_core_dir=ubuntu_core_dir
mkdir -p ${ubuntu_core_dir}
cd ${ubuntu_core_dir}
rootfs_archive="ubuntu-core-15.04-core-armhf.tar.gz"
if [ ! -f ${rootfs_archive} ] ; then
  wget http://cdimage.ubuntu.com/ubuntu-core/releases/15.04/release/SHA1SUMS
  wget http://cdimage.ubuntu.com/ubuntu-core/releases/15.04/release/${rootfs_archive}
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

# Clear the first 32M
sudo dd if=/dev/zero of=${target_device} bs=1M count=32
if [ $? != "0" ] ; then
  echo "erasing failed"
  exit 1
fi

# Make the entire disk a Linux partition
sudo sfdisk --in-order --Linux --unit M ${target_device} <<-__EOF__
1,,L,*
;
__EOF__

if [ $? != "0" ] ; then
  echo "sfdisk failed"
  exit 1
fi

sudo mkfs.ext4 ${target_device}1 -L PiggyString

sudo umount ${target_device}1

# Write U-Boot as raw mode
sudo dd if=MLO of=${target_device} bs=512 seek=256 count=256 conv=notrunc
sudo dd if=u-boot.img of=${target_device} bs=512 seek=768 count=1024 conv=notrunc
sudo blockdev --flushbufs ${target_device}

## Mount target device
sudo mount ${target_device}1 /mnt
sudo mkdir -p /mnt/boot
sudo cp -v ${target_dir}/MLO /mnt/boot/
sudo cp -v ${target_dir}/u-boot.img /mnt/boot/
# TODO setup uEnv.txt
sudo sh -c "echo 'uname_r=${kernel_version}' >> /mnt/boot/uEnv.txt"
sudo tar zxvpf ${target_dir}/${ubuntu_core_dir}/${rootfs_archive} -C /mnt

cd ${root_dir}
