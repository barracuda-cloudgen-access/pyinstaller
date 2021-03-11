#!/bin/bash
# Top-level build script called from Dockerfile

# Get script directory
MY_DIR=$(dirname "${BASH_SOURCE[0]}")

# Get build utilities
source $MY_DIR/build_utils.sh

# pinned to winetricks 20201206
curl -fsSLo /manylinux-rootfs/usr/local/bin/winetricks https://raw.githubusercontent.com/Winetricks/winetricks/20201206/src/winetricks
chmod +x /manylinux-rootfs/usr/local/bin/winetricks

export PATH=/manylinux-rootfs/usr/local/bin:$PATH
export WINEARCH=win64
export WINEDEBUG=fixme-all
export WINEPREFIX=/manylinux-rootfs/wine

export W_DRIVE_C=/manylinux-rootfs/wine/drive_c
export W_WINDIR_UNIX="$W_DRIVE_C/windows"
export W_SYSTEM64_DLLS="$W_WINDIR_UNIX/system32"
export W_TMP="$W_DRIVE_C/windows/temp/_"
mkdir -p "$W_TMP"

winetricks win7
wineboot -r

MAJMINWITHDOT=${PYTHON_VERSION:0:3}
MAJMINNODOT="${PYTHON_VERSION:0:1}${PYTHON_VERSION:2:1}"

for msifile in echo core dev exe lib path tcltk tools; do
    curl -O "https://www.python.org/ftp/python/$PYTHON_VERSION/amd64/${msifile}.msi"
    wine64 msiexec /i "${msifile}.msi" /qn TARGETDIR=C:/Python$MAJMINNODOT ALLUSERS=1
    wineserver -w
    rm -f ${msifile}.msi
done

mkdir -p /manylinux-rootfs/usr/win64/bin/
echo 'wine64 '\'"C:\Python$MAJMINNODOT\python.exe"\'' "$@"' > /manylinux-rootfs/usr/win64/bin/python
echo 'wine64 '\'"C:\Python$MAJMINNODOT\Scripts\easy_install-$MAJMINWITHDOT.exe"\'' "$@"' > /manylinux-rootfs/usr/win64/bin/easy_install
echo 'wine64 '\'"C:\Python$MAJMINNODOT\Scripts\pip$MAJMINWITHDOT.exe"\'' "$@"' > /manylinux-rootfs/usr/win64/bin/pip
echo 'wine64 '\'"C:\Python$MAJMINNODOT\Scripts\pyinstaller.exe"\'' "$@"' > /manylinux-rootfs/usr/win64/bin/pyinstaller
echo 'assoc .py=PythonScript' | wine64 cmd
echo "ftype PythonScript=c:\Python$MAJMINNODOT\python.exe"' "%1" %*' | wine64 cmd
wineserver -w
chmod +x /manylinux-rootfs/usr/win64/bin/python /manylinux-rootfs/usr/win64/bin/easy_install /manylinux-rootfs/usr/win64/bin/pip /manylinux-rootfs/usr/win64/bin/pyinstaller

# install pip from the python distribution itself
/manylinux-rootfs/usr/win64/bin/python -m ensurepip

# update pip/certifi for windows
/manylinux-rootfs/usr/win64/bin/pip --no-cache-dir install -U pip || true
/manylinux-rootfs/usr/win64/bin/pip --no-cache-dir install -U certifi wheel setuptools auditwheel || true

# install latest pyinstaller for windows
/manylinux-rootfs/usr/win64/bin/pip --no-cache-dir install pyinstaller==$PYINSTALLER_VERSION

# Cleanup tmp folder
rm -f "$W_TMP"/*
