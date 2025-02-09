#!/bin/bash
set -e

#### THE PLAN ####
# 1. Kernel
# 2. Userspace (busybox)
# 3. Bootloader (syslinux)

#### CONFIFURATION ####
kernel_source_package="https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.13.tar.xz"
busybox_source_package="https://www.busybox.net/downloads/busybox-1.37.0.tar.bz2"

#### COLORS ####
RED="\e[91m"
GREEN="\e[92m"
BLUE="\e[94m"
WHITE="\e[97m"
ENDC="\e[0m"

build_requirements=(
# kernel
    "bison" 
    "flex"
    "gawk" 
    "libelf-dev"
    "libncurses-dev"
    "libssl-dev"
    "make"
    "openssl"
    "pv"
    "tar"
    "wget"

# busybox
    "bzip2"

# initramfs
    "cpio"

# qemu
    "qemu-system-x86"

# diskimage
    "dosfstools"
    "syslinux"
)

check_dependencies() {
    missing_packages=()
    
    for pkg in "${build_requirements[@]}"; do
        version=$(dpkg-query -W -f='${Package} ${Version}\n' 2>/dev/null | grep -E "^$pkg(:[a-z0-9]+)? " | awk '{print $2}')
        if [[ -n "$version" ]]; then
            echo -e "  [ ${GREEN}OK${ENDC} ] $pkg at version ${BLUE}$version${ENDC}"
        else
            echo -e "  [${RED}FAIL${ENDC}] $pkg"
            missing_packages+=("$pkg")
        fi
    done

    if [ ${#missing_packages[@]} -eq 0 ]; then
        echo "All requirements satisfied."
    else
        echo "Missing dependencies:"
        printf " - %s\n" "${missing_packages[@]}"
        exit 1
    fi
}

if [[ "$1" == "--deps" ]]; then
    check_dependencies
    exit 0
fi

project_dir=$(pwd)

##temporary for easy clean
project_dir=$project_dir/temp
[ -d $project_dir ] || mkdir $project_dir

### directories
sources=$project_dir/sources
sources_kernel=$sources/kernel
sources_userspace=$sources/userspace

build=$project_dir/build
build_kernel=$build/kernel
build_userspace=$build/userspace

image=$project_dir/image
image_initramfs=$project_dir/image/initramfs

[ -d $sources ] || mkdir $sources
[ -d $sources_kernel ] || mkdir $sources_kernel
[ -d $sources_userspace ] || mkdir $sources_userspace

[ -d $build ] || mkdir $build
[ -d $build_kernel ] || mkdir $build_kernel
[ -d $build_userspace ] || mkdir $build_userspace

[ -d $image ] || mkdir $image
[ -d $image_initramfs ] || mkdir $image_initramfs

arch=$(uname -m)
[ ${arch} = 'i686' ] && arch="i386" # hack i686 to i386 packages :D

### KERNEL BUILD ###
cd $sources_kernel

if [ -f ${build_kernel}/*/arch/${arch}/boot/bzImage ] ; then
    echo -e "Do you want to use previously build kernel? (use n if want to rebuild on changed config) [Y/n]:"
    read kernel_choice
    kernel_choice=${kernel_choice:-Y}
fi

if [[ "$kernel_choice" =~ ^[Yy]$ ]]; then
    echo -e "Using already build kernel from ${build_kernel}"
else
    echo -e "${WHITE}Step 1.1.${GREEN} Downloading kernel${ENDC}"
    wget --no-clobber --show-progress $kernel_source_package

    echo -e "${WHITE}Step 1.2.${GREEN} Extracting kernel${ENDC}"
    if find ${build_kernel} -mindepth 1 -maxdepth 1 | read; then
        echo -e "Extracted kernel found in ${BLUE}${build_kernel}${ENDC} - skipping extraction\n"
    else
        pv *.tar.xz | tar -Jx -C  ${build_kernel}
    fi

    cd $build_kernel/linux*
    build_kernel=$(pwd)

    echo -e "${WHITE}Step 1.3.${GREEN} Making default kernel config${ENDC}"

    if [ -f ${build_kernel}/.config ] ; then
        echo -e "Using existing config found in ${BLUE}${build_kernel}/.config${ENDC} - not generating new one\n"

    else
        make defconfig  #try smaller config later (tinyconfig?)
    fi

    echo -e "${WHITE}Step 1.4.${GREEN} Building kernel${ENDC}"
    make -j$(nproc)

    echo -e "${WHITE}Step 1.5.${GREEN} Saving bzImage${ENDC}"
    cp arch/$arch/boot/bzImage $image 
fi

### USERSPACE BUILD ###
cd $sources_userspace

if [ -f ${build_userspace}/*/busybox ] ; then
    echo -e "Do you want to use previously build userspace toolkit? (use n if want to rebuild on changed config) [Y/n]:"
    read userspace_kernel_choice
    userspace_kernel_choice=${userspace_kernel_choice:-Y}
fi

if [[ "$userspace_kernel_choice" =~ ^[Yy]$ ]]; then
    echo -e "Using already build userspace toolkit from ${build_userspace}"
else
    echo -e "${WHITE}Step 2.1.${GREEN} Downloading userspace${ENDC}"
    wget --no-clobber --show-progress ${busybox_source_package}

    echo -e "${WHITE}Step 2.2.${GREEN} Extracting userspace${ENDC}"
    pv *.tar.bz2 | tar -xjv -C ${build_userspace} -f -

    echo -e "${WHITE}Step 2.3.${GREEN} Making default userspace config${ENDC}"

    cd ${build_userspace}/busybox*
    build_userspace=$(pwd)

    if [ -f ${build_userspace}/.config ] ; then
        echo -e "Using existing config found in ${BLUE}${build_userspace}/.config${ENDC} - not generating new one\n"

    else
        make defconfig
    fi

    echo -e "${WHITE}Step 2.4.${GREEN} Switching to static linking${ENDC}"
    sed 's/^.*CONFIG_STATIC.*$/CONFIG_STATIC=y/' -i .config # for static linking
    sed 's/^CONFIG_MAN=y/CONFIG_MAN=n/' -i .config  # no manual pages
    echo "CONFIG_STATIC_LIBGCC=y" >> .config   # configure static libgcc

    echo -e "${WHITE}Step 2.5.${GREEN} Fixing of busybox traffic control related symbols ${ENDC}"
    sed 's/^CONFIG_TC=y/CONFIG_TC=n/' -i .config    # some newer kernels are not providing traffic control defines anymore

    echo -e "${WHITE}Step 2.6.${GREEN} Building userspace${ENDC}"
    make -j$(nproc)

    echo -e "${WHITE}Step 2.7.${GREEN} Installing userspace${ENDC}"
    make CONFIG_PREFIX=${image_initramfs} install
    rm ${image_initramfs}/linuxrc
fi

echo -e "${WHITE}Step 3.1.${GREEN} Creating init script${ENDC}"
cd ${image_initramfs}

cat << EOF > ./init
#!/bin/sh

ln -sf /dev/null /dev/tty2
ln -sf /dev/null /dev/tty3
ln -sf /dev/null /dev/tty4

/bin/sh
EOF

echo -e "${WHITE}Step 3.2.${GREEN} Marking init script as executable${ENDC}"
chmod +x ./init

echo -e "${WHITE}Step 3.3.${GREEN} Creating initramfs${ENDC}"
find . | cpio -o -H newc > ${image}/initramfs.cpio

### IMAGE CREATION ###
echo -e "${WHITE}Step 4.1.${GREEN} Creating boot image${ENDC}"
cd ${image}
dd if=/dev/zero of=./boot.img bs=1M count=64

echo -e "${WHITE}Step 4.2.${GREEN} Creating file system for boot image${ENDC}"
mkfs -t fat boot.img

echo -e "${WHITE}Step 4.3.${GREEN} Installing syslinux bootloader ${ENDC}"
syslinux ./boot.img

echo -e "${WHITE}Step 4.4.${GREEN} Creating syslinux bootloader config${ENDC}"

cat << EOF > ./syslinux.cfg
DEFAULT minimal
PROMPT 0        # Set to 1 to display boot: prompt
TIMEOUT 50
LABEL minimal
    MENU LABEL Minimal Linux
    LINUX ../bzImage 
    INITRD ../initramfs.cpio
EOF

# TODO consider different method of boot image creation that does not require root privileges
echo -e "${WHITE}Step 4.5.${GREEN} Copying kernel and initramfs to boot image ${ENDC}"
[ -d boot_mount ] || mkdir boot_mount
sudo mount boot.img boot_mount
sudo cp {bzImage,syslinux.cfg,initramfs.cpio} boot_mount
sudo umount boot_mount
rm boot_mount -rf

### RUN ###
echo -e "${WHITE}Step 4.6.${RED} Starting qemu with kernel and initramfs packed in boot.img${ENDC}"
qemu-system-x86_64 -drive format=raw,file=./boot.img
