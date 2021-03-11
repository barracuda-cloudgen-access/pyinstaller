#!/bin/bash
# Top-level build script called from Dockerfile

# Stop at any error, show all commands
set -exuo pipefail

# Get script directory
MY_DIR=$(dirname "${BASH_SOURCE[0]}")

# Get build utilities
source $MY_DIR/build_utils.sh

check_var ${WINE_ROOT}
check_var ${WINE_HASH}
check_var ${WINE_DOWNLOAD_URL}

yum -y install epel-release
yum -y install cabextract flex xz libXi-devel libX11-devel freetype-devel zlib-devel libxcb-devel libxslt-devel libgcrypt-devel libxml2-devel gnutls-devel libpng-devel libjpeg-turbo-devel libtiff-devel dbus-devel fontconfig-devel

fetch_source ${WINE_ROOT}.tar.xz ${WINE_DOWNLOAD_URL}
check_sha256sum ${WINE_ROOT}.tar.xz ${WINE_HASH}
tar -xf ${WINE_ROOT}.tar.xz
pushd ${WINE_ROOT}
export DESTDIR=/manylinux-rootfs
./configure --enable-win64 --disable-tests --with-xattr
make -j"$(nproc)"
make -j"$(nproc)" install
popd
rm -rf ${WINE_ROOT} ${WINE_ROOT}.tar.xz
ln -s wine64 /manylinux-rootfs/usr/local/bin/wine
