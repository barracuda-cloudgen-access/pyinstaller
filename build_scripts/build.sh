#!/bin/bash
# Top-level build script called from Dockerfile

# Stop at any error, show all commands
set -ex

# Set build environment variables
MY_DIR=$(dirname "${BASH_SOURCE[0]}")

# obtain latest version of all required build_scripts/ file from the manylinux repo
for one in ambv-pubkey.txt build_env.sh cpython-pubkeys.txt manylinux-check.py python-tag-abi-tag.py requirements.txt ssl-check.py; do
    curl -fsSLo $MY_DIR/$one https://raw.githubusercontent.com/pypa/manylinux/master/docker/build_scripts/$one
done

. $MY_DIR/build_env.sh

# pick lastest CPYTHON version
for CPYTHON_VERSION in $CPYTHON_VERSIONS; do true; done

# See https://unix.stackexchange.com/questions/41784/can-yum-express-a-preference-for-x86-64-over-i386-packages
echo "multilib_policy=best" >> /etc/yum.conf

# https://hub.docker.com/_/centos/
# "Additionally, images with minor version tags that correspond to install
# media are also offered. These images DO NOT recieve updates as they are
# intended to match installation iso contents. If you choose to use these
# images it is highly recommended that you include RUN yum -y update && yum
# clean all in your Dockerfile, or otherwise address any potential security
# concerns."
# Decided not to clean at this point: https://github.com/pypa/manylinux/pull/129
yum -y update

# Dependencies for compiling Python that we want to remove from
# the final image after compiling Python
PYTHON_COMPILE_DEPS="zlib-devel bzip2-devel expat-devel ncurses-devel readline-devel tk-devel gdbm-devel db4-devel libpcap-devel xz-devel"

# Libraries that are allowed as part of the manylinux2010 profile
# Extract from PEP: https://www.python.org/dev/peps/pep-0571/#the-manylinux2010-policy
# On RPM-based systems, they are provided by these packages:
# Package:    Libraries
# glib2:      libglib-2.0.so.0, libgthread-2.0.so.0, libgobject-2.0.so.0
# glibc:      libresolv.so.2, libutil.so.1, libnsl.so.1, librt.so.1, libcrypt.so.1, libpthread.so.0, libdl.so.2, libm.so.6, libc.so.6
# libICE:     libICE.so.6
# libX11:     libX11.so.6
# libXext:    libXext.so.6
# libXrender: libXrender.so.1
# libgcc:     libgcc_s.so.1
# libstdc++:  libstdc++.so.6
# mesa:       libGL.so.1
#
# PEP is missing the package for libSM.so.6 for RPM based system
# Install development packages (except for libgcc which is provided by gcc install)
MANYLINUX2010_DEPS="glibc-devel libstdc++-devel glib2-devel libX11-devel libXext-devel libXrender-devel mesa-libGL-devel libICE-devel libSM-devel"

# Get build utilities
source $MY_DIR/build_utils.sh

# Development tools and libraries
yum -y install \
    automake \
    bison \
    bzip2 \
    cmake28 \
    devtoolset-8-binutils \
    devtoolset-8-gcc \
    devtoolset-8-gcc-c++ \
    devtoolset-8-gcc-gfortran \
    diffutils \
    gettext \
    file \
    kernel-devel-`uname -r` \
    libffi-devel \
    make \
    patch \
    unzip \
    which \
    yasm \
    ${PYTHON_COMPILE_DEPS}

# Install Mono (to be able to sign windows executables)
rpm --import ${MY_DIR}/mono-pubkeys.txt
curl https://download.mono-project.com/repo/centos6-stable.repo | tee /etc/yum.repos.d/mono-centos6-stable.repo
yum -y install mono-devel

# Build an OpenSSL for Pythons. We'll delete this at the end.
build_openssl $OPENSSL_ROOT $OPENSSL_HASH

# Install wine 4.0.1
yum -y install cabextract flex xz libX11-devel freetype-devel zlib-devel libxcb-devel libxslt-devel libgcrypt-devel libxml2-devel gnutls-devel libpng-devel libjpeg-turbo-devel libtiff-devel gstreamer-devel dbus-devel fontconfig-devel
curl -fsSLO https://dl.winehq.org/wine/source/4.0/wine-4.0.1.tar.xz
tar -xvf wine-4.0.1.tar.xz
cd wine-4.0.1
do_standard_install --enable-win64
cd ..
rm -fr wine-4.0.1*
ln -s /usr/local/bin/wine64 /usr/local/bin/wine

curl -fsSLo /usr/local/bin/winetricks https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks
chmod +x /usr/local/bin/winetricks

winetricks win7

MAJMINWITHDOT=${CPYTHON_VERSION:0:3}
MAJMINNODOT="${CPYTHON_VERSION:0:1}${CPYTHON_VERSION:2:1}"

for msifile in `echo core dev exe lib path tcltk tools`; do
    curl -O "https://www.python.org/ftp/python/$CPYTHON_VERSION/amd64/${msifile}.msi"
    wine msiexec /i "${msifile}.msi" /qb TARGETDIR=C:/Python$MAJMINNODOT
    while pgrep wineserver >/dev/null; do echo "Waiting for wineserver"; sleep 1; done
    rm -f ${msifile}.msi
done

cd /wine/drive_c/Python$MAJMINNODOT
mkdir -p /usr/win64/bin/
echo 'wine '\'"C:\Python$MAJMINNODOT\python.exe"\'' "$@"' > /usr/win64/bin/python
echo 'wine '\'"C:\Python$MAJMINNODOT\Scripts\easy_install-$MAJMINWITHDOT.exe"\'' "$@"' > /usr/win64/bin/easy_install
echo 'wine '\'"C:\Python$MAJMINNODOT\Scripts\pip$MAJMINWITHDOT.exe"\'' "$@"' > /usr/win64/bin/pip
echo 'assoc .py=PythonScript' | wine cmd
echo "ftype PythonScript=c:\Python$MAJMINNODOT\python.exe"' "%1" %*' | wine cmd
while pgrep wineserver >/dev/null; do echo "Waiting for wineserver"; sleep 1; done
chmod +x /usr/win64/bin/python /usr/win64/bin/easy_install /usr/win64/bin/pip

# install pip from the python distribution itself
/usr/win64/bin/python -m ensurepip
rm -rf /tmp/.wine-*

# Install perl rename
yum -y install perl-ExtUtils-MakeMaker
curl -fsSLo - "https://search.cpan.org/CPAN/authors/id/R/RM/RMBARKER/File-Rename-1.10.tar.gz" | tar -xz && ( cd "File-Rename-1.10"; perl "Makefile.PL"; make && make install )

rm -f "$W_TMP"/*
mkdir -p "$W_TMP"
curl -o "$W_TMP"/VC_redist.x64.exe https://download.visualstudio.microsoft.com/download/pr/11100230/15ccb3f02745c7b206ad10373cbca89b/VC_redist.x64.exe
cabextract -q --directory="$W_TMP" "$W_TMP"/VC_redist.x64.exe
cabextract -q --directory="$W_TMP" "$W_TMP/a10"
cabextract -q --directory="$W_TMP" "$W_TMP/a11"
cd "$W_TMP"
/usr/local/bin/rename 's/_/\-/g' *.dll
cp "$W_TMP"/*.dll "$W_SYSTEM64_DLLS"/

mkdir -p /src/ && ln -s /src /wine/drive_c/src
mkdir -p /wine/drive_c/tmp

# update pip for windows
(/usr/win64/bin/pip install -U pip || true)

# install latest pyinstaller for windows
/usr/win64/bin/pip install pyinstaller
echo 'wine '\'"C:\Python$MAJMINNODOT\Scripts\pyinstaller.exe"\'' "$@"' > /usr/win64/bin/pyinstaller
chmod +x /usr/win64/bin/pyinstaller

build_cpythons $CPYTHON_VERSION

# pick latest python version
for dir in /opt/python/cp$MAJMINNODOT-*; do
    LATEST_PY="$dir";
done
echo "$LATEST_PY" > /latest_py

# update pip for linux
($LATEST_PY/bin/pip install -U pip || true)

# install latest pyinstaller for linux
$LATEST_PY/bin/pip install pyinstaller

# Now we can delete our built OpenSSL headers/static libs since we've linked everything we need
rm -rf /usr/local/ssl

# Clean up development headers and other unnecessary stuff for
# final image
yum -y erase \
    avahi \
    bitstream-vera-fonts \
    gettext \
    gtk2 \
    hicolor-icon-theme \
    wireless-tools \
    cabextract \
    flex \
    xz \
    perl-ExtUtils-MakeMaker \
    ${PYTHON_COMPILE_DEPS} > /dev/null 2>&1
yum -y install ${MANYLINUX2010_DEPS}
yum -y clean all > /dev/null 2>&1
yum list installed

# we don't need libpython*.a, and they're many megabytes
find /opt/_internal -name '*.a' -print0 | xargs -0 rm -f

# Strip what we can -- and ignore errors, because this just attempts to strip
# *everything*, including non-ELF files:
find /opt/_internal -type f -print0 \
    | xargs -0 -n1 strip --strip-unneeded 2>/dev/null || true
find /usr/local -type f -print0 \
    | xargs -0 -n1 strip --strip-unneeded 2>/dev/null || true

for PYTHON in /opt/python/*/bin/python; do
    # Smoke test to make sure that our Pythons work, and do indeed detect as
    # being manylinux compatible:
    $PYTHON $MY_DIR/manylinux-check.py
    # Make sure that SSL cert checking works
    $PYTHON $MY_DIR/ssl-check.py
done

# We do not need the Python test suites, or indeed the precompiled .pyc and
# .pyo files. Partially cribbed from:
#    https://github.com/docker-library/python/blob/master/3.4/slim/Dockerfile
find /opt/_internal -depth \
     \( -type d -a -name test -o -name tests \) \
  -o \( -type f -a -name '*.pyc' -o -name '*.pyo' \) | xargs rm -rf

# Fix libc headers to remain compatible with C99 compilers.
find /usr/include/ -type f -exec sed -i 's/\bextern _*inline_*\b/extern __inline __attribute__ ((__gnu_inline__))/g' {} +

# remove useless things that have been installed by devtoolset-8
rm -rf /opt/rh/devtoolset-8/root/usr/share/man
find /opt/rh/devtoolset-8/root/usr/share/locale -mindepth 1 -maxdepth 1 -not \( -name 'en*' -or -name 'locale.alias' \) | xargs rm -rf
rm -rf /usr/share/backgrounds
# if we updated glibc, we need to strip locales again...
localedef --list-archive | grep -v -i ^en_US.utf8 | xargs localedef --delete-from-archive
mv -f /usr/lib/locale/locale-archive /usr/lib/locale/locale-archive.tmpl
build-locale-archive
find /usr/share/locale -mindepth 1 -maxdepth 1 -not \( -name 'en*' -or -name 'locale.alias' \) | xargs rm -rf
find /usr/local/share/locale -mindepth 1 -maxdepth 1 -not \( -name 'en*' -or -name 'locale.alias' \) | xargs rm -rf
rm -rf /usr/local/share/man
