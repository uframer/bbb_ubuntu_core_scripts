#!/bin/bash

root_dir=$PWD

if [ $# != "2" ] ; then
    echo "Usage: $0 <workspace> <image_filename>"
    exit 1
fi

echo "====Prepare Workspace===="
# Workspace
workspace=$1
# Device file for SD card
image_filename=$2
image_size="4096" # 4G

if [ ! -f ${image_filename} ] ; then
    dd if=/dev/zero of=${image_filename} bs=1M count=${image_size}
else
    file_bytes=$(stat -c%s "${image_filename}")
    image_bytes=$((${image_size}*1024*1024))
    if [ ! "${file_bytes}" == "${image_bytes}" ] ; then
        echo "image size mismatch, create new file"
        dd if=/dev/zero of=${image_filename} bs=1M count=${image_size}
    else
       echo "using existing file ${image_filename} of size ${file_bytes}"
    fi
fi

# use the last one to avoid conflicts
loop_device=/dev/loop7
sudo losetup ${loop_device} ${image_filename}

./build.sh ${workspace} ${loop_device} 2>&1 | tee build.log

sudo losetup -d ${loop_device}