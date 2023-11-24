#!/usr/bin/env sh

WORKDIR="$(pwd)"

# Changable Data:

# Clang Data
CLANG_REPO="ZyCromerZ/Clang"

# Kernel Data
KERNEL_NAME="MilkKernel"
KERNEL_GIT="https://github.com/SchweGELBin/kernel_milk_davinci.git"
KERNEL_BRANCH="kenvyra-13.0"
ANDROID_VERSION="13"

# Anykernel3 Data
ANYKERNEL3_GIT="https://github.com/SchweGELBin/AnyKernel3_davinci.git"
ANYKERNEL3_BRANCH="master"

# Build Data
DEVICE_CODE="davinci"
DEVICE_DEFCONFIG="davinci_defconfig"
DEVICE_ARCH="arch/arm64"


CLANG_DLINK="$(curl -s https://api.github.com/repos/$CLANG_REPO/releases/latest\
| grep -wo "https.*" | grep Clang-.*.tar.gz | sed 's/.$//')"
CLANG_DIR="$WORKDIR/Clang/bin"

KERNEL_REPO=${KERNEL_GIT::-4}/
KERNEL_SOURCE=${KERNEL_REPO::-1}/tree/$KERNEL_BRANCH
KERNEL_DIR="$WORKDIR/$KERNEL_NAME"

DEVICE_DEFCONFIG_FILE="$KERNEL_DIR/$DEVICE_ARCH/configs/$DEVICE_DEFCONFIG"
IMAGE="$KERNEL_DIR/out/$DEVICE_ARCH/boot/Image.gz"
DTB="$KERNEL_DIR/out/$DEVICE_ARCH/boot/dtb.img"
DTBO="$KERNEL_DIR/out/$DEVICE_ARCH/boot/dtbo.img"

export KBUILD_BUILD_USER=SchweGELBin
export KBUILD_BUILD_HOST=GitHubCI

# Highlight
msg() {
	echo
	echo -e "\e[1;33m$*\e[0m"
	echo
}

cd $WORKDIR

# Setup
msg "Setup"

msg "Clang"
mkdir -p Clang
aria2c -s16 -x16 -k1M $CLANG_DLINK -o Clang.tar.gz
tar -C Clang/ -zxvf Clang.tar.gz
rm -rf Clang.tar.gz

CLANG_VERSION="$($CLANG_DIR/clang --version | head -n 1 | cut -f1 -d "(" | sed 's/.$//')"
LLD_VERSION="$($CLANG_DIR/ld.lld --version | head -n 1 | cut -f1 -d "(" | sed 's/.$//')"

msg "Kernel"
git clone --depth=1 $KERNEL_GIT -b $KERNEL_BRANCH $KERNEL_DIR

KERNEL_VERSION=$(cat $KERNEL_DIR/Makefile | grep -w "VERSION =" | cut -d '=' -f 2 | cut -b 2-)\
.$(cat $KERNEL_DIR/Makefile | grep -w "PATCHLEVEL =" | cut -d '=' -f 2 | cut -b 2-)\
.$(cat $KERNEL_DIR/Makefile | grep -w "SUBLEVEL =" | cut -d '=' -f 2 | cut -b 2-)\
.$(cat $KERNEL_DIR/Makefile | grep -w "EXTRAVERSION =" | cut -d '=' -f 2 | cut -b 2-)

[ ${KERNEL_VERSION: -1} = "." ] && KERNEL_VERSION=${KERNEL_VERSION::-1}
msg "Kernel Version: $KERNEL_VERSION"

cd $KERNEL_DIR

msg "KernelSU"
echo $(curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh") >> setup.sh
# Edit script to edit Makefile after clone
curl -LSs "https://raw.githubusercontent.com/SchweGELBin/KernelSU/main/kernel/setup.sh" | bash -s main

echo "CONFIG_KPROBES=y" >> $DEVICE_DEFCONFIG_FILE
echo "CONFIG_HAVE_KPROBES=y" >> $DEVICE_DEFCONFIG_FILE
echo "CONFIG_KPROBE_EVENTS=y" >> $DEVICE_DEFCONFIG_FILE

KSU_GIT_VERSION=$(cd KernelSU && git rev-list --count HEAD)
KERNELSU_VERSION=$(($KSU_GIT_VERSION + 10200))
msg "KernelSU Version: $KERNELSU_VERSION"

sed -i "/CONFIG_LOCALVERSION=/c\CONFIG_LOCALVERSION=\"-$KERNELSU_VERSION-$KERNEL_NAME\"/" $DEVICE_DEFCONFIG_FILE

#Build
msg "Build"

args="PATH=$CLANG_DIR:$PATH \
ARCH=arm64 \
SUBARCH=arm64 \
CROSS_COMPILE=aarch64-linux-gnu- \
CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
CC=clang \
NM=llvm-nm \
CXX=clang++ \
AR=llvm-ar \
LD=ld.lld \
STRIP=llvm-strip \
OBJDUMP=llvm-objdump \
OBJSIZE=llvm-size \
READELF=llvm-readelf \
HOSTAR=llvm-ar \
HOSTLD=ld.lld \
HOSTCC=clang \
HOSTCXX=clang++ \
LLVM=1 \
LLVM_IAS=1"

rm -rf out
make O=out $args $DEVICE_DEFCONFIG
make O=out $args kernelversion
make O=out $args -j"$(nproc --all)"
msg "Kernel version: $KERNEL_VERSION"

# Package
msg "Package"
cd $WORKDIR
git clone --depth=1 $ANYKERNEL3_GIT -b $ANYKERNEL3_BRANCH $WORKDIR/Anykernel3
cd $WORKDIR/Anykernel3
cp $IMAGE .
cp $DTB $WORKDIR/Anykernel3/dtb
cp $DTBO .

# Archive
TIME=$(TZ='Europe/Berlin' date +"%Y-%m-%d %H:%M:%S")
ZIP_NAME="$KERNEL_NAME.zip"
find ./ * -exec touch -m -d "$TIME" {} \;
zip -r9 $ZIP_NAME *
cp *.zip $WORKDIR/out/artifacts

cd $WORKDIR/out

# Release Files
msg "Release Files"
echo "
## $KERNEL_NAME
- **Time**: $TIME # CET

<br>

- **Codename**: $DEVICE_CODE
- **Android Version**: $ANDROID_VERSION

<br>

- **Kernel Version**: $KERNEL_VERSION
- **KernelSU Version**: $KERNELSU_VERSION

<br>

- **CLANG Version**: $CLANG_VERSION
- **LLD Version**: $LLD_VERSION

<br>

- **[Kernel Repo]($KERNEL_REPO)**
- **[Kernel Source]($KERNEL_SOURCE)**
" > bodyFile.md
echo "$KERNEL_NAME-$KERNEL_VERSION-$KERNELSU_VERSION" > name.txt
echo "$KERNEL_NAME.zip" > filename.txt

# Finish
msg "Done"
