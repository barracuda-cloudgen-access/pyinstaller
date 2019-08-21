#!/bin/bash

# Stop at any error, show all commands
set -ex

REPRO_BUILD=${REPRO_BUILD:-yes}
if [[ "$REPRO_BUILD" == "yes" ]]; then
    PYTHONHASHSEED=1
    export PYTHONHASHSEED
fi

PLATFORMS=${PLATFORMS:-win,linux}

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

if [ -f requirements.txt ]; then
    if [[ $PLATFORMS == *"linux"* ]]; then
        pip install -r requirements.txt
    fi
    if [[ $PLATFORMS == *"win"* ]]; then
        /usr/win64/bin/pip install -r requirements.txt
    fi
fi

# Handy if you need to install libraries before running pyinstaller
if [[ $PLATFORMS == *"linux"* ]]; then
    SHELL_CMDS=${SHELL_CMDS:-}
    if [[ "$SHELL_CMDS" != "" ]]; then
        /bin/bash -c "$SHELL_CMDS"
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
        $@
fi

chown -R --reference=. dist
chown -R --reference=. *.spec
popd
