#!/bin/sh

set -e

info() {
  # Don't bother checking for an ANSI-capable terminal
  # https://github.com/actions/runner/issues/241
	echo "\033[0;32m> $*\033[0m"
}


# Set up directories
info "Setting up directories"
OPENFANG_ROOT_DIR=$(pwd)
echo "Project directory: $OPENFANG_ROOT_DIR"
OPENFANG_OUTPUT_DIR="${OPENFANG_OUTPUT_DIR:-$OPENFANG_ROOT_DIR/output}"
if ! [ -d "$OPENFANG_OUTPUT_DIR" ]; then
  echo "Creating output directory: $OPENFANG_OUTPUT_DIR"
  mkdir "$OPENFANG_OUTPUT_DIR"
else
   echo "Output directory: $OPENFANG_OUTPUT_DIR"
fi
OPENFANG_BUILD_DIR="$OPENFANG_ROOT_DIR/_build"
if [ ! -d "$OPENFANG_BUILD_DIR" ]; then
  echo "Creating build directory: $OPENFANG_BUILD_DIR"
  mkdir "$OPENFANG_BUILD_DIR"
else
  echo "Build directory: $OPENFANG_BUILD_DIR"
fi


# Update version info
info "Updating version info"
TAG=rc05_01
DATE=$(date +"%Y-%m-%d %H:%M")
#ID="($(git rev-parse HEAD)) $DATE"
ID="$(git describe --tags)"
SHORTID=$(git rev-parse --short HEAD)
echo "$ID" > fs/opt/version

cp -r fs/ "$OPENFANG_BUILD_DIR/"

sed -i "s/VERSION=.*/VERSION=\"$DATE\"/g" "$OPENFANG_BUILD_DIR/fs/opt/autoupdate.sh"
sed -i "s/TAG=.*/TAG=\"$TAG\"/g" "$OPENFANG_BUILD_DIR/fs/opt/autoupdate.sh"
sed -i "s/ID=.*/ID=\"$SHORTID\"/g" "$OPENFANG_BUILD_DIR/fs/opt/autoupdate.sh"

echo "VERSION: $DATE"
echo "TAG: $TAG"
echo "ID: $ID"
echo "SHORTID: $SHORTID"
[ "$1" = "stamp" ] && exit 0


cd "$OPENFANG_BUILD_DIR"
info "Setting up buildroot"

# Download buildroot
BUILDROOT_VERSION=2016.02
if [ ! -d "buildroot-$BUILDROOT_VERSION" ]; then
  info "Downloading and patching buildroot $BUILDROOT_VERSION"
  wget -q https://buildroot.org/downloads/buildroot-$BUILDROOT_VERSION.tar.gz
  tar -xf buildroot-$BUILDROOT_VERSION.tar.gz
  rm buildroot-$BUILDROOT_VERSION.tar.gz
  cd buildroot-$BUILDROOT_VERSION
  patch -p1 < "$OPENFANG_ROOT_DIR/patches/add_fp_no_fused_madd.patch"
  cd ..
fi
cd buildroot-$BUILDROOT_VERSION

# Update config files
cp "$OPENFANG_ROOT_DIR/config/buildroot.config" .config
cp "$OPENFANG_ROOT_DIR/config/busybox.config" package/busybox/
cp "$OPENFANG_ROOT_DIR/config/uClibc-ng.config" package/uclibc/

[ -d "dl" ] || mkdir dl

cp "$OPENFANG_ROOT_DIR/kernel-3.10.14.tar.xz" dl/
cp "$OPENFANG_ROOT_DIR/uboot-v2013.07.tar.xz" dl/

# Patch buildroot if gcc >= 5
echo "GCC version: $(gcc -dumpversion)"
GCCVER=$(gcc -dumpversion | cut -d'.' -f1)
if [ "$GCCVER" -ge "5" ]; then
  cp "$OPENFANG_ROOT_DIR/patches/automake.in.patch" package/automake/
  cp "$OPENFANG_ROOT_DIR/patches/python/python2.7_gcc8__fix.patch" package/python/
  cp "$OPENFANG_ROOT_DIR/patches/lzop-gcc6.patch" package/lzop/
fi

# Copy Python patches to address host-python build failing when host has
# openssl 1.1.0 headers installed
cp -f "$OPENFANG_ROOT_DIR/patches/python/111-optional-ssl.patch" package/python/
cp "$OPENFANG_ROOT_DIR/patches/python/019-force-internal-hash-if-ssl-disabled.patch" package/python/

# Copy custom openfang packages to buildroot directory
rm -r package/ffmpeg  # use updated package version instead
rm -r package/libtirpc  # use updated package version instead
#rm -r package/python  # use updated package version instead
#rm -r package/uclibc  # use updated package version instead
cp -rf "$OPENFANG_ROOT_DIR/buildroot"/* .


info "Building"
make

# Compile different versions of uboot
[ -f "output/images/u-boot-lzo-with-spl.bin" ] && mv output/images/u-boot-lzo-with-spl.bin output/images/u-boot-lzo-with-spl_t20_128M.bin

# Change uboot configuration
sed -i "s/BR2_TARGET_UBOOT_BOARDNAME=.*/BR2_TARGET_UBOOT_BOARDNAME=\"isvp_t20_sfcnor\"/g" .config

make uboot-dirclean
make uboot

[ -f "output/images/u-boot-lzo-with-spl.bin" ] && mv output/images/u-boot-lzo-with-spl.bin output/images/u-boot-lzo-with-spl_t20_64M.bin
# end uboot compilation


# Copy images to output dir
cp output/images/* "$OPENFANG_OUTPUT_DIR"


# Construct release with git hash label
info "Compressing toolchain..."
tar -c -C output/host/ --transform s/./mipsel-ingenic-linux-uclibc/ --checkpoint=.1000 . | xz --best > "$OPENFANG_OUTPUT_DIR/toolchain-$SHORTID.tar.xz"
info "Compressing rootfs images..."
tar -c -C output/images/ --transform s/./openfang-images/ --checkpoint=.1000 . | xz --best > "$OPENFANG_OUTPUT_DIR/images-$SHORTID.tar.xz"
info "Build completed successfully."
