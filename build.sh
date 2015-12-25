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

# Use my fork from Robert Nelson's script to build Linux kernel
cd ${target_dir}
linux_builder_script=linux_builder_script
git clone https://github.com/uframer/armv7-multiplatform.git ${linux_builder_script}
# Checkout v4.3.x branch
cd ${linux_builder_script}
git checkout remotes/origin/v4.3.x -b build
AUTO_BUILD=1 ./build_kernel.sh

cd {root_dir}
