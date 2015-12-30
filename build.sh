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
__EOF__

if [ $? != "0" ] ; then
    echo "sfdisk failed"
    exit 1
fi

sudo mkfs.ext4 ${target_device}1 -L PiggySting

sudo umount ${target_device}1

# Write U-Boot as raw mode
sudo dd if=MLO of=${target_device} bs=512 seek=256 count=256 conv=notrunc
sudo dd if=u-boot.img of=${target_device} bs=512 seek=768 count=1024 conv=notrunc
sudo blockdev --flushbufs ${target_device}

## Mount target device
sudo mount ${target_device}1 /mnt
# Install u-boot
sudo mkdir -p /mnt/boot
sudo cp -v ${target_dir}/MLO /mnt/boot/
sudo cp -v ${target_dir}/u-boot.img /mnt/boot/
# TODO setup uEnv.txt
sudo sh -c "echo 'uname_r=${kernel_version}' >> /mnt/boot/uEnv.txt"
# Install Linux kernel
sudo cp -v ${target_dir}/${linux_builder_script}/deploy/${kernel_version}.zImage /mnt/boot/vmlinuz-${kernel_version}
# Install Device Tree
sudo mkdir -p /mnt/boot/dtbs/${kernel_version}/
sudo tar xfv ${target_dir}/${linux_builder_script}/deploy/${kernel_version}-dtbs.tar.gz -C /mnt/boot/dtbs/${kernel_version}/
# Install kernel modules
sudo tar xfv ${target_dir}/${linux_builder_script}/deploy/${kernel_version}-modules.tar.gz -C /mnt/
# Install Ubuntu Core rootfs
sudo tar zxvpf ${target_dir}/${ubuntu_core_dir}/${rootfs_archive} -C /mnt
# Setup fstab
sudo sh -c "echo '/dev/mmcblk0p1  /  auto  errors=remount-ro  0  1' >> /mnt/etc/fstab"
# Setup serial
sudo cp -v ${root_dir}/serial.conf /mnt/etc/init/serial.conf

# Add user
target_user=piggysting
#sudo groupadd -R /mnt ${target_user} || echo "failed to add group ${target_user}"
#sudo useradd -R /mnt -s '/bin/bash' -m -G ${target_user},adm,sudo ${target_user}
#sudo useradd -R /mnt -s '/bin/bash' -m ${target_user}
#echo "Set password for ${target_user}:"
#sudo passwd -R /mnt ${target_user}
#echo "Set password for root:"
#sudo passwd -R /mnt root
sudo cp -v /usr/bin/qemu-arm-static /mnt/usr/bin/
sudo LC_ALL=C chroot /mnt /bin/bash -c "useradd -s '/bin/bash' -m -G adm,sudo ${target_user};echo \"Set password for ${target_user}:\";passwd ${target_user};echo \"Set password for root:\";passwd root"
sudo rm /mnt/usr/bin/qemu-arm-static
sudo umount /mnt

cd ${root_dir}
