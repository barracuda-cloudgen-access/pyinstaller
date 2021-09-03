#!/bin/sh

# Stop at any error, show all commands
set -ex

WORKDIR=${SRCDIR:-/src}
cd "$WORKDIR"

# taken from https://github.com/cdrx/docker-pyinstaller/blob/master/linux/py3/entrypoint.sh
PYPI_URL=${PYPI_URL:-"https://pypi.python.org/"}
PYPI_INDEX_URL=${PYPI_INDEX_URL:-"https://pypi.python.org/simple"}
mkdir -p /root/pip
echo "[global]" > /root/pip/pip.conf
echo "index = $PYPI_URL" >> /root/pip/pip.conf
echo "index-url = $PYPI_INDEX_URL" >> /root/pip/pip.conf
echo "trusted-host = $(echo $PYPI_URL | sed -Ee 's|^.*?:\/\/(.*?)(:.*?)?\/.*$|\1|')" >> /root/pip/pip.conf

# Handy if you need to install libraries before running pyinstaller
ALPINE_SHELL_CMDS=${ALPINE_SHELL_CMDS:-}
if [[ "$ALPINE_SHELL_CMDS" != "" ]]; then
    /bin/sh -c "$ALPINE_SHELL_CMDS"
fi

if [ -f requirements.txt ]; then
    pip install -r requirements.txt
fi

pyinstaller --log-level=DEBUG \
    --clean --noupx \
    --noconfirm \
    --onefile \
    --distpath dist/alpine \
    --workpath /tmp \
    -p . \
    --additional-hooks-dir '/hooks' \
    --hidden-import pkg_resources.py2_warn \
    $@

chown -R $(stat -c %u:%g .) dist
chown -R $(stat -c %u:%g .) *.spec
