#!/bin/bash

## init
export ARCH=arm64
export HOME_DIR=$(pwd)
export KERNEL_PATH="${HOME_DIR}/linux-stable"
export TOOLCHAIN_PATH="${HOME_DIR}/toolchain"
export CROSS_COMPILE=${TOOLCHAIN_PATH}/bin/aarch64-linux-gnu-
export DST_DIR="${HOME_DIR}/output-odroid-c2/" && rm -rf $DST_DIR
export DST_DIR_BOOT="${DST_DIR}boot/"


## linux kernel
rm -rf linux-stable
git clone --depth 1 https://kernel.googlesource.com/pub/scm/linux/kernel/git/stable/linux -b linux-5.15.y linux-stable


## toolchain
rm -rf toolchain
git clone --depth=1 https://github.com/theradcolor/aarch64-linux-gnu -b master toolchain


## clean-up
cd linux-stable
make mrproper && make defconfig


## kernel configuration
sed -i -e 's/.*CONFIG_SQUASHFS_XZ.*/CONFIG_SQUASHFS_XZ=y/' .config
sed -i -e 's/.*CONFIG_UEVENT_HELPER.*/CONFIG_UEVENT_HELPER=y/' .config
sed -i -e 's/.*CONFIG_BLK_DEV_RAM.*/CONFIG_BLK_DEV_RAM=y/' .config
echo CONFIG_UEVENT_HELPER_PATH=\"/sbin/hotplug\" >> .config
echo CONFIG_BLK_DEV_RAM_COUNT=16 >> .config
echo CONFIG_BLK_DEV_RAM_SIZE=4096 >> .config
sed -i -e 's/CONFIG_DRM_\(.*\)=.*/# CONFIG_DRM_\1 is not set/' .config
sed -i -e 's/.*CONFIG_DRM_LIMA.*/CONFIG_DRM_LIMA=m/' .config
sed -i -e 's/.*CONFIG_DRM_PANFROST.*/CONFIG_DRM_PANFROST=m/' .config


## build
time make -j$(nproc) Image modules


## dtbs
git apply --ignore-space-change --ignore-whitespace - << EOF
diff --git a/arch/arm64/boot/dts/amlogic/meson-gxbb-odroidc2.dts b/arch/arm64/boot/dts/amlogic/meson-gxbb-odroidc2.dts
index 201596247..027df3756 100644
--- a/arch/arm64/boot/dts/amlogic/meson-gxbb-odroidc2.dts
+++ b/arch/arm64/boot/dts/amlogic/meson-gxbb-odroidc2.dts
@@ -348,7 +348,8 @@ &saradc {
 };

 &scpi_clocks {
-       status = "disabled";
+       /* Works only with new blobs that have limited DVFS table */
+       status = "okay";
 };

 /* SD */
EOF
time make -j$(nproc) dtbs


## modloop
rm -rf "${KERNEL_PATH}/installed-modules" && mkdir "${KERNEL_PATH}/installed-modules"
INSTALL_MOD_PATH="${KERNEL_PATH}/installed-modules" make modules_install
find "${KERNEL_PATH}/installed-modules" -type l -delete
rm -f "${KERNEL_PATH}/modloop"
mksquashfs "${KERNEL_PATH}/installed-modules/lib/" "${KERNEL_PATH}/modloop" -b 1048576 -comp xz -Xdict-size 100% -all-root
rm -rf "${KERNEL_PATH}/installed-modules"


## assembly
mkdir -p ${DST_DIR_BOOT}
gzip -c "${KERNEL_PATH}/arch/arm64/boot/Image > ${DST_DIR_BOOT}/vmlinuz
cp "${KERNEL_PATH}/.config" ${DST_DIR_BOOT}/config
mv "${KERNEL_PATH}/modloop" ${DST_DIR_BOOT}/modloop
cp "${KERNEL_PATH}/System.map" ${DST_DIR_BOOT}/System.map
mkdir ${DST_DIR_BOOT}/dtbs/
cp "${KERNEL_PATH}/arch/arm64/boot/dts/amlogic/meson-gxbb-odroidc2.dts" ${DST_DIR_BOOT}/dtbs/
cp "${KERNEL_PATH}/arch/arm64/boot/dts/amlogic/meson-gxbb-odroidc2.dtb" ${DST_DIR_BOOT}/dtbs/


## clean-up
cd ${HOME_DIR}
rm -rf "${KERNEL_PATH}"
rm -rf "${TOOLCHAIN_PATH}"
