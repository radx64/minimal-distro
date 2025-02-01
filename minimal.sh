#!/bin/bash

set -e

# 1. Download kernel
# 2. Download busybox


# TODO make some function to validate requirements 
# via dpkg or apt
# sorry I'm running on LMDE

build_requirements=(
    "wget"
    "tar"
    "pv"
    "make"
    "qemu"
)


#### CONFIFURATION ####
kernel="https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.13.tar.xz"


#### COLORS ####
RED="\e[31m"
GREEN="\e[92m"
BLUE="\e[33m"
WHITE="\e[97m"
ENDCOLOR="\e[0m"

project_dir=$(pwd)

##temporary for easy clean
project_dir=$project_dir/temp
[ -d $project_dir ] || mkdir $project_dir

### directories
sources=$project_dir/sources
sources_kernel=$sources/kernel

build=$project_dir/build
build_kernel=$build/kernel
image=$project_dir/image

[ -d $sources ] || mkdir $sources
[ -d $sources_kernel ] || mkdir $sources_kernel

[ -d $build ] || mkdir $build
[ -d $build_kernel ] || mkdir $build_kernel

[ -d $image ] || mkdir $image

cd $sources_kernel

echo -e "${WHITE}Step 1.${GREEN} Downloading kernel${ENDCOLOR}"
wget --show-progress $kernel

echo -e "${WHITE}Step 2.${GREEN} Extracting kernel${ENDCOLOR}"
pv *.tar.xz | tar -Jx -C $build_kernel

cd $build_kernel/linux*
build_kernel=$(pwd)

echo -e "${WHITE}Step 3.${GREEN} Making default kernel config${ENDCOLOR}"
make defconfig

echo -e "${WHITE}Step 4.${GREEN} Building kernel${ENDCOLOR}"
make -j$(nproc)

echo -e "${WHITE}Step 5.${GREEN} Saving bzImage${ENDCOLOR}"
## TODO add architecture selection/detection
cp arch/x86/boot/bzImage $image 

echo -e "${WHITE}Step 6.${RED} Running temporary qemu to test bzImage. It will kernel panic!${ENDCOLOR}"
### CTRL + A x to kill nographic qemu
qemu-system-x86_64 -nographic --kernel $image/bzImage  --append "console=ttyS0,9600 console=tty0"
