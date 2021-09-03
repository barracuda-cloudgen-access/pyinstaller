#!/bin/bash

# Stop at any error, show all commands
set -ex

source /opt/msvc/bin/x64/msvcenv.sh
export DISTUTILS_USE_SDK=1

REPRO_BUILD=${REPRO_BUILD:-yes}
if [[ "$REPRO_BUILD" == "yes" ]]; then
    export PYTHONHASHSEED=1
fi
export PYTHONDONTWRITEBYTECODE=1

PLATFORMS=${PLATFORMS:-win,linux,alpine}

WORKDIR=${SRCDIR:-/src}
pushd "$WORKDIR"

# taken from https://github.com/cdrx/docker-pyinstaller/blob/master/linux/py3/entrypoint.sh
PYPI_URL=${PYPI_URL:-"https://pypi.python.org/"}
PYPI_INDEX_URL=${PYPI_INDEX_URL:-"https://pypi.python.org/simple"}
mkdir -p /root/pip
mkdir -p /wine/drive_c/users/root/pip
echo "[global]" > /root/pip/pip.conf
echo "index = $PYPI_URL" >> /root/pip/pip.conf
echo "index-url = $PYPI_INDEX_URL" >> /root/pip/pip.conf
echo "trusted-host = $(echo $PYPI_URL | perl -pe 's|^.*?://(.*?)(:.*?)?/.*$|$1|')" >> /root/pip/pip.conf
ln /root/pip/pip.conf /wine/drive_c/users/root/pip/pip.ini

# Handy if you need to install libraries before running pyinstaller
SHELL_CMDS=${SHELL_CMDS:-}
if [[ "$SHELL_CMDS" != "" ]]; then
    /bin/bash -c "$SHELL_CMDS"
fi

if [ -f requirements.txt ]; then
    if [[ $PLATFORMS == *"linux"* ]]; then
        pip install -r requirements.txt
    fi
    if [[ $PLATFORMS == *"win"* ]]; then
        /usr/win64/bin/pip install -r requirements.txt
    fi
fi

echo "$@"

ret=0
if [[ $PLATFORMS == *"linux"* ]]; then
    pyinstaller --log-level=DEBUG \
        --clean --noupx \
        --noconfirm \
        --onefile \
        --distpath dist/linux \
        --workpath /tmp \
        -p . \
        --add-binary '/usr/local/lib/libcrypt.so.2:.' \
        --additional-hooks-dir '/hooks' \
        --hidden-import pkg_resources.py2_warn \
        $@
    ret=$?
fi

if [[ $PLATFORMS == *"win"* && $ret == 0 ]]; then
    /usr/win64/bin/pyinstaller --log-level=DEBUG \
        --clean --noupx \
        --noconfirm \
        --onefile \
        --distpath dist/windows \
        --workpath /tmp \
        -p . \
        --hidden-import win32timezone \
        --hidden-import pkg_resources.py2_warn \
        $@
    ret=$?

    if [[ $ret == 0 && $CODESIGN_KEYFILE != "" && $CODESIGN_PASS != "" ]]; then
        openssl pkcs12 -in $CODESIGN_KEYFILE -nocerts -nodes -password env:CODESIGN_PASS -out /dev/shm/key.pem
        openssl rsa -in /dev/shm/key.pem -outform PVK -pvk-none -out /dev/shm/authenticode.pvk
        openssl pkcs12 -in $CODESIGN_KEYFILE -nokeys -nodes  -password env:CODESIGN_PASS -out /dev/shm/cert.pem

        # if the user provides the certificateof the issuer, attach that one too
        if [[ $CODESIGN_EXTRACERT != "" ]]; then
            cat $CODESIGN_EXTRACERT >> /dev/shm/cert.pem
        fi

        openssl crl2pkcs7 -nocrl -certfile /dev/shm/cert.pem -outform DER -out /dev/shm/authenticode.spc

        for exefile in dist/windows/*.exe; do
            echo "Signing Windows binary $exefile"
            signcode \
                -spc /dev/shm/authenticode.spc \
                -v /dev/shm/authenticode.pvk \
                -a sha256 -$ commercial \
                -t http://timestamp.verisign.com/scripts/timstamp.dll \
                -tr 5 -tw 60 \
                "$exefile"
            mv "$exefile.bak" "$(dirname $exefile)/unsigned_$(basename $exefile)"
        done
    fi
fi

chown -R --reference=. dist
chown -R --reference=. *.spec
popd

if [[ $ret == 0 && $PLATFORMS == *"alpine"* ]]; then
    /switch_to_alpine.sh $@
fi
