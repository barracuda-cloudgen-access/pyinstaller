# Manylinux/Windows Pyinstaller Docker Image

This container is based on the official [Python Manylinux](https://github.com/pypa/manylinux/) manylinux2014 docker image, which sets an entire build environment based on a very old linux version in a way such that when you build a python binary module on it, it is assured to work on any modern (glibc based) Linux and also Alpine 3.x (musl libc based) Linux.

We had to rebuild Python inside this container using shared libraries (only latest Python 3 where PyInstaller works is supported)
to be able to use it with the [Pyinstaller project](https://pyinstaller.org) and on top of that, the image also has a working Wine 5 installed (Wine is a Microsoft Windows emulator) with Python for windows, pip, etc. added to be able to create Pyinstaller Windows executables too. The idea for building Windows binaries using Wine was taken from [here](https://github.com/cdrx/docker-pyinstaller), but improved, based on manylinux and made polyglot, ie. the same container does both Linux and Windows.

The goal of this project then is to be able to produce single-file binaries for Linux x68-64 that only depend on a very basic (read old) libc and for x86-64 Microsoft Windows (Windows 7 and up).

# Use mode

To build the binary, you need to mount your source code folder into the container in the `/src` folder and any extra command line argument will be sent to Pyinstaller.

The resulting binaries will be located in `dist/linux`, `dist/alpine`, and `dist/windows` respectively, and a `.spec` file as used by Pyinstaller will be created. Also, you can provide such `.spec` file to Pyinstaller instead of a python module and it will follow the instructions from it. Please refer to the [Pyinstaller documentation](https://pyinstaller.readthedocs.io/en/stable/spec-files.html) for more information.

If there is a `requirements.txt` file present at the root of the source code folder it will be installed using `pip install` before running Pyinstaller.

## Minimal example
```
$ echo 'print("Hello World")' > helloworld.py
$ docker run \
    -v "$(pwd):/src" \
    fydeinc/pyinstaller \
    helloworld.py
$ docker run -it -v "$(pwd):/mnt" centos /mnt/dist/linux/helloworld
Hello World
```

## Bit more convoluted
```
$ echo 'requests' > requirements.txt
$ cat > example.py <<EOF
import requests
print(requests.get("http://example.org").text)
EOF
$ docker run \
    -v "$(pwd):/src" \
    -e "PLATFORMS=linux" \
    fydeinc/pyinstaller \
    --name you-can-send-opts-to-pyinstaller \
    example.py
$ docker run -it -v "$(pwd):/mnt" centos /mnt/dist/linux/you-can-send-opts-to-pyinstaller
<!doctype html>
<html>
<head>
    <title>Example Domain</title>
...
```

# Environment variables

Some behavior can be changed by changing the environment of the container.

| Key | Default value | Description |
|-----|---------------|-------------|
|REPRO_BUILD|yes|Create a [reproducible builds](https://pyinstaller.readthedocs.io/en/stable/advanced-topics.html#creating-a-reproducible-build) (ie. same python code will generate same binaries).|
|PLATFORMS|win,linux,alpine|Select what kind of binaries to produce.|
|SRCDIR|/src|Folder inside the container where the source code is mounted. CI runners might need to change this.|
|PYPI_URL|https://pypi.python.org/|URL for the pypi package repositories, useful if you're using internal package caches.|
|PYPI_INDEX_URL|https://pypi.python.org/simple|URL for the pypi index.|
|SHELL_CMDS||Runs the given shell commands before calling pyinstaller. Useful if you need to change the build environment in some way before building the binaries. You can also use a `.spec` file for that, since it is a Python script afterall.|
|ALPINE_SHELL_CMDS||Runs the given shell commands before calling pyinstaller. Useful if you need to change the build environment in some way before building the binaries. You can also use a `.spec` file for that, since it is a Python script afterall.|
|CODESIGN_KEYFILE||If present, it must be a password-protected PFX keyfile with te Authenticode code signing certificate to use to sign the generated Windows executables. Reminder: It must be reachable from the container.|
|CODESIGN_PASS||Password for the CODESIGN_KEYFILE.|
|CODESIGN_EXTRACERT||Optional extra file in PEM format with the certificate chain to append to the signature. Useful to make certain tools (like signtool.exe) verify OK.|
