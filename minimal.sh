#!/bin/bash
set -e

#### THE PLAN ####
# 1. Kernel
# 2. Userspace (busybox)
# 3. Bootloader (syslinux)

#### CONFIGURATION ####
kernel_source_package="https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.13.tar.xz"
busybox_source_package="https://www.busybox.net/downloads/busybox-1.37.0.tar.bz2"
toybox_source_package="https://github.com/landley/toybox/archive/refs/tags/0.8.12.tar.gz"

# default userspace is toybox, use -u to change
selected_userspace="toybox"

#### COLORS ####
RED="\e[91m"
GREEN="\e[92m"
YELLOW="\e[93m"
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

scripts_dir=$(pwd)
distro_dir=${scripts_dir}/distro
[ -d ${distro_dir} ] || mkdir ${distro_dir}

help()
{
    echo -e "${BLUE} _____ __    ____  "
    echo -e "|     |  |  |    \ "
    echo -e "| | | |  |__|  |  |"
    echo -e "|_|_|_|_____|____/ "
    echo -e "${ENDC}"
    echo -e "${GREEN}Minimal Linux Distro${ENDC} build script by ${RED}radx64${ENDC}"
    echo -e " "
    echo -e "Usage: ${GREEN}$0${ENDC} [OPTION]"
    echo -e "Build small bootable Linux distribution from sources."
    echo -e ""
    echo -e "Optional arguments:"
    echo -e "-c, --distclean    Cleans distribution build directory"
    echo -e "                   removing all downloaded and built artifacts"
    echo -e "                   Removes: ${RED}${distro_dir}${ENDC}"
    echo -e "-d, --deps         Checks if host system has all necessary"
    echo -e "                   packages installed (uses dpkg)"
    echo -e "-h, --help         Prints this help"
    echo -e "-u, --userspace    Selects preferred userspace"
    echo -e "                   valid options are ${RED}busybox${ENDC} or ${RED}toybox${ENDC}"
}

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

distclean() {
    echo -e "Cleaning distro files: ${RED}${distro_dir}${ENDC}"
    rm -rf ${distro_dir}
}

print_step() {
    local step_number="$1"
    local step_name="$2"
    
    local text=" Step ${GREEN}$step_number${ENDC}: $step_name "
    local control_chars="${GREEN}${ENDC}"

    local text_len=${#text}
    local control_chars_len=${#control_chars}
    local plain_text_len=$((text_len - control_chars_len)) 
    local border=$(printf '%*s' "$plain_text_len" '' | tr ' ' '=')
    
    echo ""
    echo -e "$border"
    echo -e "$text"
    echo -e "$border"
    echo ""
}

if [[ "$1" == "--deps" ]] || [[ "$1" == "-d" ]]; then
    check_dependencies
    exit 0
elif [[ "$1" == "--distclean" ]] || [[ "$1" == "-c" ]]; then
    distclean
    exit 0
elif [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
    help
    exit 0

elif [[ "$1" == "--userspace" ]] || [[ "$1" == "-u" ]]; then
    
    if [[ "$2" == "busybox" ]]; then 
        echo -e "Selected busybox"
        selected_userspace="busybox"

    elif [[ "$2" == "toybox" ]]; then
        echo -e "Selected toybox"
        selected_userspace="toybox"
    else
        echo -e "${RED}Error: ${WHITE}Userspace ${RED}$2${WHITE} is not a valid option${ENDC}!"
        echo -e "Valid options are ${GREEN}busybox${ENDC} or ${GREEN}toybox${ENDC}"
        exit 1
    fi
fi


### directories
sources=$distro_dir/sources
sources_kernel=$sources/kernel
sources_userspace=$sources/userspace

build=$distro_dir/build
build_kernel=$build/kernel
build_userspace=$build/userspace

image=$distro_dir/image
image_initramfs=$distro_dir/image/initramfs

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

eval "kernel_file=(${build_kernel}/*/arch/${arch}/boot/bzImage)"

if [ -f ${kernel_file} ] ; then
    echo -e "Do you want to use previously build kernel from ${BLUE}${kernel_file}${ENDC}? (use n if want to rebuild on changed config) [Y/n]:"
    read kernel_choice
    kernel_choice=${kernel_choice:-Y}
fi

if [[ "$kernel_choice" =~ ^[Yy]$ ]]; then
    echo -e "Using already build kernel from ${build_kernel}"
else
    print_step "1.1" "Downloading kernel"
    wget --no-clobber --show-progress $kernel_source_package

    print_step "1.2" "Extracting kernel"
    if [ -f  ${build_kernel}/.extracted ] ; then
        echo -e "Extracted kernel found in ${BLUE}${build_kernel}${ENDC} - skipping extraction\n"
    else
        pv *.tar.xz | tar -Jx -C  ${build_kernel}
        touch ${build_kernel}/.extracted
    fi

    cd $build_kernel/linux*
    build_kernel=$(pwd)

    print_step "1.3" "Making tiny kernel config"
    if [ -f ${build_kernel}/.config ] ; then
        echo -e "Using existing config found in ${BLUE}${build_kernel}/.config${ENDC} - not generating new one\n"

    else
        make ARCH=x86_64 tinyconfig
        print_step "1.4.1" "Patching kernel configuration"
        ${build_kernel}/scripts/kconfig/merge_config.sh ${build_kernel}/.config ${scripts_dir}/tiny_config_patch.fragment
        print_step "1.4.2" "Rebuilding kernel configuration"
        make olddefconfig
    fi

    print_step "1.5" "Building kernel"
    make -j$(nproc)

    print_step "1.6" "Saving bzImage"
    cp arch/$arch/boot/bzImage $image 
fi

### USERSPACE BUILD ###
cd $sources_userspace

eval "busybox_userspace_file=(${build_userspace}/*/busybox)"
eval "toybox_userspace_file=(${build_userspace}/*/toybox)"

if [[ ${selected_userspace} == "busybox" ]]; then

    if [ -f ${toybox_userspace_file} ] ; then
        echo -e "${YELLOW}Warning: ${ENDC}Toybox binary already found in ${BLUE}${build_userspace}${ENDC}. Consider calling this script with --distclean first!"
        echo -e "${YELLOW}Warning: ${ENDC}Build might be corrupted or might contain unnecessary files. Press [Enter] to continue!"
        read
    fi
    if [ -f ${busybox_userspace_file} ] ; then
        echo -e "Do you want to use previously build userspace toolkit from ${BLUE}${busybox_userspace_file}${ENDC}? (use n if want to rebuild on changed config) [Y/n]:"
        read userspace_choice
        userspace_choice=${userspace_choice:-Y}
    fi

    if [[ "$userspace_choice" =~ ^[Yy]$ ]]; then
        echo -e "Using already build userspace toolkit from ${build_userspace}"
    else
        print_step "2.1" "Downloading userspace"
        wget --no-clobber --show-progress ${busybox_source_package}

        if [ -f  ${build_userspace}/.busybox_extracted ] ; then    
            echo -e "Extracted userspace found in ${BLUE}${build_userspace}${ENDC} - skipping extraction\n"
        else
            print_step "2.2" "Extracting userspace"
            pv *.tar.bz2 | tar -xjv -C ${build_userspace} -f -
            touch ${build_userspace}/.busybox_extracted
        fi

        print_step "2.3" "Making default userspace config"
        cd ${build_userspace}/busybox*
        build_userspace=$(pwd)

        if [ -f ${build_userspace}/.config ] ; then
            echo -e "Using existing config found in ${BLUE}${build_userspace}/.config${ENDC} - not generating new one\n"

        else
            make defconfig
        fi

        print_step "2.4" "Switching to static linking"
        sed 's/^.*CONFIG_STATIC.*$/CONFIG_STATIC=y/' -i .config # for static linking
        sed 's/^CONFIG_MAN=y/CONFIG_MAN=n/' -i .config  # no manual pages
        echo "CONFIG_STATIC_LIBGCC=y" >> .config   # configure static libgcc

        print_step "2.5" "Fixing of busybox traffic control related symbols"
        sed 's/^CONFIG_TC=y/CONFIG_TC=n/' -i .config    # some newer kernels are not providing traffic control defines anymore

        print_step "2.6" "Building userspace"
        make -j$(nproc)

        print_step "2.7" "Installing userspace"
        make CONFIG_PREFIX=${image_initramfs} install
        rm ${image_initramfs}/linuxrc
    fi

elif [[ ${selected_userspace} == "toybox" ]]; then

    if [ -f ${busybox_userspace_file} ] ; then
        echo -e "${YELLOW}Warning: ${ENDC}Busybox binary already found in ${BLUE}${build_userspace}${ENDC}. Consider calling this script with --distclean first!"
        echo -e "${YELLOW}Warning: ${ENDC}Build might be corrupted or might contain unnecessary files. Press [Enter] to continue!"
        read
    fi
    if [ -f ${toybox_userspace_file} ] ; then
        echo -e "Do you want to use previously build userspace toolkit from ${BLUE}${toybox_userspace_file}${ENDC}? (use n if want to rebuild on changed config) [Y/n]:"
        read userspace_choice
        userspace_choice=${userspace_choice:-Y}
    fi

    if [[ "$userspace_choice" =~ ^[Yy]$ ]]; then
        echo -e "Using already build userspace toolkit from ${build_userspace}"
    else
        print_step "2.1" "Downloading userspace"
        wget --no-clobber --show-progress ${toybox_source_package}

        if [ -f  ${build_userspace}/.toybox_extracted ] ; then    
            echo -e "Extracted userspace found in ${BLUE}${build_userspace}${ENDC} - skipping extraction\n"
        else
            print_step "2.2" "Extracting userspace"
            pv *.tar.gz | tar -xz -C ${build_userspace} -f -
            touch ${build_userspace}/.toybox_extracted
        fi

        print_step "2.3" "Making default userspace config"
        cd ${build_userspace}/toybox*
        build_userspace=$(pwd)

        if [ -f ${build_userspace}/.config ] ; then
            echo -e "Using existing config found in ${BLUE}${build_userspace}/.config${ENDC} - not generating new one\n"
        else
            export LDFLAGS=--static 
            make defconfig
            echo "CONFIG_SH=y" >> .config      # build shell from pending toys
            echo "CONFIG_ROUTE=y" >> .config   # build route from pending toys
        fi

        print_step "2.4" "Building userspace"
        make -j$(nproc)

        print_step "2.5" "Installing userspace"
        PREFIX=${image_initramfs} make install
    fi
fi

print_step "3.1" "Creating init script"
cd ${image_initramfs}

cat << EOF > ./welcome
======================================================

 _____ __    ____  
|     |  |  |    \ 
| | | |  |__|  |  |
|_|_|_|_____|____/ 

Welcome in Minimal Linux Distro build by radx64 script
    
======================================================
EOF

cat << EOF > ./init
#!/bin/sh

# Fake TTYs
ln -sf /dev/null /dev/tty2
ln -sf /dev/null /dev/tty3
ln -sf /dev/null /dev/tty4

# Setup proc and sysfs
mkdir /proc && mount -t proc proc /proc
mkdir /sys && mount -t sysfs sys /sys

# SETUP QEMU networking
ifconfig lo 127.0.0.1
ifconfig eth0 10.0.2.15
route add default gw 10.0.2.2

# Fix for not working ping
echo 0 99999 > /proc/sys/net/ipv4/ping_group_range

cat welcome

/bin/sh
EOF

print_step "3.2" "Marking init script as executable"
chmod +x ./init

print_step "3.3" "Creating initramfs"
find . | cpio -o -H newc > ${image}/initramfs.cpio

### IMAGE CREATION ###
print_step "4.1" "Creating boot disk image"
cd ${image}
dd if=/dev/zero of=./boot.img bs=1M count=64

print_step "4.2" "Creating file system for boot disk image"
mkfs -t fat boot.img

print_step "4.3" "Installing syslinux bootloader"
syslinux ./boot.img

print_step "4.4" "Creating syslinux bootloader config"
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
print_step "4.5" "Copying kernel and initramfs to boot image (root privileges required)"
[ -d boot_mount ] || mkdir boot_mount
sudo mount boot.img boot_mount
sudo cp {bzImage,syslinux.cfg,initramfs.cpio} boot_mount
sudo umount boot_mount
rm boot_mount -rf

### RUN ###
print_step "5.1" "Starting qemu with kernel and initramfs packed in boot.img"
qemu-system-x86_64 -drive format=raw,file=./boot.img -net nic -net user
