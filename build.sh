#!/bin/bash


## init
export ARCH=arm64
export HOME_DIR=$(pwd)
export KERNEL_PATH="${HOME_DIR}/linux-stable"
export TOOLCHAIN_PATH="${HOME_DIR}/toolchain"
export CROSS_COMPILE=${TOOLCHAIN_PATH}/bin/aarch64-linux-gnu-
export DST_DIR="${HOME_DIR}/output-odroid-c2/" && rm -rf $DST_DIR
export DST_DIR_BOOT="${DST_DIR}boot/"
export NBPROC=$(($(nproc)+1))
export KERNEL_BRANCH="5.15"
echo "[INFO] $(nproc) processors are available"


## version check
NEXT_VERSION=$(wget -qO- "https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain/Makefile?h=linux-$KERNEL_BRANCH.y" | awk '/SUBLEVEL/ {print $3; exit}')
CURRENT_VERSION=$(wget -qO- "https://raw.githubusercontent.com/odroid-c2/kernel/kernel-releases/version" || echo 0)
if [[ ${CURRENT_VERSION} == ${NEXT_VERSION} ]]; then
	echo "o ${KERNEL_BRANCH}.${CURRENT_VERSION} is up to date, nothing to do"
	exit 0
else
	echo "o Current version is ${KERNEL_BRANCH}.${CURRENT_VERSION}, building ${KERNEL_BRANCH}.${NEXT_VERSION}"
fi


## set version
echo "${NEXT_VERSION}" > version


## linux kernel
rm -rf linux-stable
echo "o [$(date +%H:%M:%S)] Clonning linux-stable kernel"
git clone --quiet --depth 1 https://kernel.googlesource.com/pub/scm/linux/kernel/git/stable/linux -b linux-5.15.y linux-stable


## toolchain
rm -rf toolchain
echo "o [$(date +%H:%M:%S)] Clonning aarch64-linux-gnu toolchain"
git clone --quiet --depth=1 https://github.com/theradcolor/aarch64-linux-gnu -b master toolchain


## clean-up
cd linux-stable
echo "o [$(date +%H:%M:%S)] Setting-up kernel configuration"
(make mrproper && make defconfig) 2>&1 > /dev/null


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
sed -i -e 's/.*CONFIG_WIRELESS.*/# CONFIG_WIRELESS is not set/' .config


## build image
echo "o [$(date +%H:%M:%S)] Building image"
make -j$NBPROC Image 2>&1 > kernel.log


## build modules
echo "o [$(date +%H:%M:%S)] Building modules"
make -j$NBPROC modules 2>&1 > modules.log


## build dtbs
echo "o [$(date +%H:%M:%S)] Building dtbs"
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
make -j$NBPROC dtbs 2>&1 > dtbs.log


## modloop
echo "o [$(date +%H:%M:%S)] Creating modloop"
rm -rf "${KERNEL_PATH}/installed-modules" && mkdir "${KERNEL_PATH}/installed-modules"
INSTALL_MOD_PATH="${KERNEL_PATH}/installed-modules" make modules_install 2>&1 > /dev/null
find "${KERNEL_PATH}/installed-modules" -type l -delete
rm -f "${KERNEL_PATH}/modloop"
mksquashfs "${KERNEL_PATH}/installed-modules/lib/" "${KERNEL_PATH}/modloop" -b 1048576 -comp xz -Xdict-size 100% -all-root
rm -rf "${KERNEL_PATH}/installed-modules"


## assembly
echo "o [$(date +%H:%M:%S)] Assembly"
mkdir -p ${DST_DIR_BOOT}
gzip -c "${KERNEL_PATH}/arch/arm64/boot/Image" > ${DST_DIR_BOOT}/vmlinuz
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


## generate .PKGINFO
echo "# Generated by custom script" > ${DST_DIR}.PKGINFO
echo "# using my hands ;)" >> ${DST_DIR}.PKGINFO
echo "$(date)" >> ${DST_DIR}.PKGINFO
echo "pkgname = linux-kernel-amlogic" >> ${DST_DIR}.PKGINFO
echo "pkgver = ${KERNEL_BRANCH}.${CURRENT_VERSION}" >> ${DST_DIR}.PKGINFO
echo "pkgdesc = Linux kernel for Amlogic" >> ${DST_DIR}.PKGINFO
echo "url = https://github.com/odroid-c2/kernel" >> ${DST_DIR}.PKGINFO
echo "builddate = $(date +%s)" >> ${DST_DIR}.PKGINFO
echo "packager = unknown for now" >> ${DST_DIR}.PKGINFO
echo "size = $(du ${DST_DIR_BOOT} | awk '{print$1}')" >> ${DST_DIR}.PKGINFO
echo "arch = aarch64" >> ${DST_DIR}.PKGINFO
echo "origin = linux-kernel-amlogic" >> ${DST_DIR}.PKGINFO
# pseudo-random data for now
echo "commit = $(cat ${DST_DIR_BOOT}/vmlinuz | openssl dgst -sha1 -binary | xxd -p)" >> ${DST_DIR}.PKGINFO
echo "maintainer = odroid-c2" >> ${DST_DIR}.PKGINFO
echo "license = GPL-3.0" >> ${DST_DIR}.PKGINFO
echo "# automatically detected:" >> ${DST_DIR}.PKGINFO
# pseudo-random data for now
echo "datahash = $(du ${DST_DIR_BOOT} | openssl dgst -sha1 -binary | xxd -p)" >> ${DST_DIR}.PKGINFO


## compress data
tar -C ${DST_DIR} -czf linux-kernel-amlogic-${KERNEL_BRANCH}.${CURRENT_VERSION}.tar.gz .PKGINFO boot/


## clean again
rm -rf "${DST_DIR}"
