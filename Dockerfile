# Get from: https://github.com/docker-library/python/blob/master/3.9/alpine3.12/Dockerfile
ARG PYTHON_VERSION=3.9.2
ARG PYTHON_PIP_VERSION=21.0.1
ARG PYTHON_GET_PIP_URL=https://github.com/pypa/get-pip/raw/b60e2320d9e8d02348525bd74e871e466afdf77c/get-pip.py
ARG PYTHON_GET_PIP_SHA256=c3b81e5d06371e135fb3156dc7d8fd6270735088428c4a9a5ec1f342e2024565
ARG PYINSTALLER_VERSION=4.2
ARG OPENSSL_VERSION=1.1.1j
ARG OPENSSL_SHA256=aaf2fcb575cdf6491b98ab4829abf78a3dec8402b8b81efc8f23c00d443981bf
ARG GPG_KEY=E3FF2839C048B25C084DEBE9B26995E310250568
ARG DUMBINIT_VERSION=1.2.5
ARG BASEIMAGE=amd64/centos:7
ARG POLICY=manylinux2014
ARG PLATFORM=x86_64
ARG DEVTOOLSET_ROOTPATH="/opt/rh/devtoolset-9/root"
ARG LD_LIBRARY_PATH_ARG="${DEVTOOLSET_ROOTPATH}/usr/lib64:${DEVTOOLSET_ROOTPATH}/usr/lib:${DEVTOOLSET_ROOTPATH}/usr/lib64/dyninst:${DEVTOOLSET_ROOTPATH}/usr/lib/dyninst:/usr/local/lib64:/usr/local/lib"
ARG PREPEND_PATH="${DEVTOOLSET_ROOTPATH}/usr/bin:"

# Taken from https://github.com/mstorsjo/msvc-wine/
FROM ubuntu:20.04 AS vcbuilder

RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y python msitools python-simplejson python-six ca-certificates && \
    apt-get clean -y && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /opt/msvc
COPY msvc/vsdownload.py ./
RUN ./vsdownload.py --accept-license --dest /opt/msvc && \
    rm -f vsdownload.py && \
    rm -fr 'DIA SDK'
RUN find -iname arm -type d -exec rm -fr \{\} \; || true
RUN find -iname x86 -type d -exec rm -fr \{\} \; || true
RUN find -iname arm64 -type d -exec rm -fr \{\} \; || true


FROM alpine:3.7 AS python_builder
ARG PYTHON_VERSION
ARG PYTHON_PIP_VERSION
ARG PYTHON_GET_PIP_URL
ARG PYTHON_GET_PIP_SHA256
ARG OPENSSL_VERSION
ARG OPENSSL_SHA256
ARG GPG_KEY

ENV LANG C.UTF-8
ENV GPG_KEY $GPG_KEY
ENV PYTHON_VERSION $PYTHON_VERSION

# Based on https://github.com/docker-library/python/blob/master/3.9/alpine3.12/Dockerfile
RUN set -ex \
    && apk add --no-cache ca-certificates tzdata \
	&& apk add --no-cache --virtual .fetch-deps \
		gnupg \
		tar \
		xz

COPY ${GPG_KEY}.asc /
RUN set -ex \
	&& wget -O python.tar.xz "https://www.python.org/ftp/python/${PYTHON_VERSION%%[a-z]*}/Python-$PYTHON_VERSION.tar.xz" \
	&& wget -O python.tar.xz.asc "https://www.python.org/ftp/python/${PYTHON_VERSION%%[a-z]*}/Python-$PYTHON_VERSION.tar.xz.asc" \
	&& export GNUPGHOME="$(mktemp -d)" \
	&& gpg --batch --import "/${GPG_KEY}.asc" \
	&& gpg --batch --verify python.tar.xz.asc python.tar.xz \
	&& { command -v gpgconf > /dev/null && gpgconf --kill all || :; } \
	&& rm -rf "$GNUPGHOME" python.tar.xz.asc \
	&& mkdir -p /usr/src/python \
	&& tar -xJC /usr/src/python --strip-components=1 -f python.tar.xz \
	&& rm python.tar.xz \
    && rm "/${GPG_KEY}.asc"

RUN set -ex \
	&& apk add --no-cache --virtual .build-deps  \
		bluez-dev \
		bzip2-dev \
        libbz2 \
        libnsl-dev \
		coreutils \
        perl \
		dpkg-dev dpkg \
		expat-dev \
		findutils \
		gcc \
        g++ \
		gdbm-dev \
		libc-dev \
		libffi-dev \
		libtirpc-dev \
		linux-headers \
		make \
		ncurses-dev \
		pax-utils \
		readline-dev \
		sqlite-dev \
		tcl-dev \
		tk \
		tk-dev \
		util-linux-dev \
		xz-dev \
		zlib-dev \
# add build deps before removing fetch deps in case there's overlap
	&& apk del --no-network .fetch-deps

ENV OPENSSL_VERSION $OPENSSL_VERSION
ENV OPENSSL_SHA256 $OPENSSL_SHA256
RUN wget --no-check-certificate -O openssl-${OPENSSL_VERSION}.tar.gz https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz \
    && echo "$OPENSSL_SHA256  openssl-${OPENSSL_VERSION}.tar.gz" > sums \
    && sha256sum -c sums \
    && tar xzf openssl-${OPENSSL_VERSION}.tar.gz \
    && cd openssl-${OPENSSL_VERSION} \
    && perl ./Configure linux-x86_64 --prefix=/usr/local/ \
        --libdir=lib \
        --openssldir=/usr/local/etc/ssl \
        shared no-zlib enable-ec_nistp_64_gcc_128 \
        no-async no-comp no-idea no-mdc2 no-rc5 no-ec2m \
        no-sm2 no-sm4 no-ssl2 no-ssl3 no-seed \
        no-weak-ssl-ciphers \
        -fPIC -Wa,--noexecstack \
    && make \
    && make install_sw


RUN set -ex \
	&& cd /usr/src/python \
	&& gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)" \
	&& ./configure \
		--build="$gnuArch" \
        --enable-ipv6 \
		--enable-shared \
		--enable-optimizations \
        --with-lto \
		--without-ensurepip \
	&& make -j "$(nproc)" \
# set thread stack size to 1MB so we don't segfault before we hit sys.getrecursionlimit()
# https://github.com/alpinelinux/aports/commit/2026e1259422d4e0cf92391ca2d3844356c649d0
		EXTRA_CFLAGS="-DTHREAD_STACK_SIZE=0x100000" \
		LDFLAGS="-Wl,--strip-all" \
	&& make install \
	&& rm -rf /usr/src/python

RUN set -ex \
	&& find /usr/local -depth \
		\( \
			\( -type d -a \( -name test -o -name tests -o -name idle_test \) \) \
			-o \( -type f -a \( -name '*.pyc' -o -name '*.pyo' -o -name '*.a' \) \) \
		\) -exec rm -rf '{}' + \
	\
	&& find /usr/local -type f -executable -not \( -name '*tkinter*' \) -exec scanelf --needed --nobanner --format '%n#p' '{}' ';' \
		| tr ',' '\n' \
		| sort -u \
		| awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
		| xargs -rt apk add --no-cache --virtual .python-rundeps \
	&& apk del --no-network .build-deps \
	\
	&& python3 --version

# make some useful symlinks that are expected to exist
RUN cd /usr/local/bin \
	&& ln -s idle3 idle \
	&& ln -s pydoc3 pydoc \
	&& ln -s python3 python \
	&& ln -s python3-config python-config

# if this is called "PIP_VERSION", pip explodes with "ValueError: invalid truth value '<VERSION>'"
ENV PYTHON_PIP_VERSION $PYTHON_PIP_VERSION
# https://github.com/pypa/get-pip
ENV PYTHON_GET_PIP_URL $PYTHON_GET_PIP_URL
ENV PYTHON_GET_PIP_SHA256 $PYTHON_GET_PIP_SHA256

RUN set -ex; \
	\
	wget -O get-pip.py "$PYTHON_GET_PIP_URL"; \
	echo "$PYTHON_GET_PIP_SHA256 *get-pip.py" | sha256sum -c -; \
	\
	python get-pip.py \
		--disable-pip-version-check \
		--no-cache-dir \
		"pip==$PYTHON_PIP_VERSION" \
	; \
	pip --version; \
	\
	find /usr/local -depth \
		\( \
			\( -type d -a \( -name test -o -name tests -o -name idle_test \) \) \
			-o \
			\( -type f -a \( -name '*.pyc' -o -name '*.pyo' \) \) \
		\) -exec rm -rf '{}' +; \
	rm -f get-pip.py


# Heavily based on https://github.com/six8/pyinstaller-alpine/
FROM alpine:3.7 AS alpine_pyinstaller

ARG PYINSTALLER_VERSION
ENV PYINSTALLER_VERSION $PYINSTALLER_VERSION
ENV PATH /usr/local/bin:$PATH
ENV LANG C.UTF-8
ENV HOME /root

COPY --from=python_builder /usr/local /usr/local

RUN set -eux; \
    apk --update --no-cache add \
    zlib-dev \
    musl-dev \
    libc-dev \
    libffi-dev \
    bzip2-dev \
    libbz2 \
    libnsl-dev \
    gdbm-dev \
    libtirpc-dev \
    linux-headers \
    make \
    ncurses-dev \
    pax-utils \
    readline-dev \
    sqlite-dev \
    util-linux-dev \
    xz-dev \
    dpkg-dev dpkg \
    expat-dev \
    coreutils \
    findutils \
    gcc \
    g++ \
    git \
    pwgen \
    ca-certificates \
    tzdata \
    gettext \
    && pip install certifi pycrypto \
    && rm -rf /var/cache/apk/*

RUN wget -qO pyinstaller.tar.gz https://github.com/pyinstaller/pyinstaller/releases/download/v${PYINSTALLER_VERSION}/pyinstaller-${PYINSTALLER_VERSION}.tar.gz \
    && tar -C /tmp -xzf pyinstaller.tar.gz \
    && rm -f pyinstaller.tar.gz \
    && cd /tmp/pyinstaller*/bootloader \
    && CFLAGS="-Wno-stringop-overflow -Wno-stringop-truncation" python ./waf configure --no-lsb all \
    && pip install .. \
    && rm -Rf /tmp/pyinstaller \
    && rm -Rf /root/.cache

RUN wget -qO - https://sh.rustup.rs | sh -s -- -y

COPY alpine-bin/ /usr/local/bin
RUN chmod +x /usr/local/bin/*


# Based on https://github.com/pypa/manylinux/blob/master/docker/Dockerfile
# default to latest supported policy, x86_64
FROM $BASEIMAGE AS runtime_base
ARG POLICY
ARG PLATFORM
ARG DEVTOOLSET_ROOTPATH
ARG LD_LIBRARY_PATH_ARG
ARG PREPEND_PATH
LABEL maintainer="Barracuda Networks"

ENV AUDITWHEEL_POLICY=${POLICY} AUDITWHEEL_ARCH=${PLATFORM} AUDITWHEEL_PLAT=${POLICY}_${PLATFORM}
ENV LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 LANGUAGE=en_US.UTF-8
ENV DEVTOOLSET_ROOTPATH=${DEVTOOLSET_ROOTPATH}
ENV LD_LIBRARY_PATH=${LD_LIBRARY_PATH_ARG}
ENV PATH=${PREPEND_PATH}${PATH}
ENV PKG_CONFIG_PATH=/usr/local/lib/pkgconfig

# first copy the fixup mirrors script, keep the script around
COPY manylinux/docker/build_scripts/fixup-mirrors.sh /usr/local/sbin/fixup-mirrors

# setup entrypoint, this will wrap commands with `linux32` with i686 images
COPY manylinux/docker/build_scripts/install-entrypoint.sh manylinux/docker/build_scripts/update-system-packages.sh /build_scripts/
RUN bash /build_scripts/install-entrypoint.sh && rm -rf /build_scripts
COPY manylinux/docker/manylinux-entrypoint /usr/local/bin/manylinux-entrypoint
ENTRYPOINT ["manylinux-entrypoint"]

COPY manylinux/docker/build_scripts/install-runtime-packages.sh manylinux/docker/build_scripts/update-system-packages.sh /build_scripts/
RUN manylinux-entrypoint /build_scripts/install-runtime-packages.sh && rm -rf /build_scripts/

COPY manylinux/docker/build_scripts/build_utils.sh /build_scripts/

COPY manylinux/docker/build_scripts/install-autoconf.sh /build_scripts/
RUN export AUTOCONF_ROOT=autoconf-2.70 && \
    export AUTOCONF_HASH=f05f410fda74323ada4bdc4610db37f8dbd556602ba65bc843edb4d4d4a1b2b7 && \
    export AUTOCONF_DOWNLOAD_URL=http://ftp.gnu.org/gnu/autoconf && \
    manylinux-entrypoint /build_scripts/install-autoconf.sh

COPY manylinux/docker/build_scripts/install-automake.sh /build_scripts/
RUN export AUTOMAKE_ROOT=automake-1.16.3 && \
    export AUTOMAKE_HASH=ce010788b51f64511a1e9bb2a1ec626037c6d0e7ede32c1c103611b9d3cba65f && \
    export AUTOMAKE_DOWNLOAD_URL=http://ftp.gnu.org/gnu/automake && \
    manylinux-entrypoint /build_scripts/install-automake.sh

COPY manylinux/docker/build_scripts/install-libtool.sh /build_scripts/
RUN export LIBTOOL_ROOT=libtool-2.4.6 && \
    export LIBTOOL_HASH=e3bd4d5d3d025a36c21dd6af7ea818a2afcd4dfc1ea5a17b39d7854bcd0c06e3 && \
    export LIBTOOL_DOWNLOAD_URL=http://ftp.gnu.org/gnu/libtool && \
    manylinux-entrypoint /build_scripts/install-libtool.sh

COPY manylinux/docker/build_scripts/install-patchelf.sh /build_scripts/
RUN export PATCHELF_VERSION=0.12 && \
    export PATCHELF_HASH=3dca33fb862213b3541350e1da262249959595903f559eae0fbc68966e9c3f56 && \
    export PATCHELF_DOWNLOAD_URL=https://github.com/NixOS/patchelf/archive && \
    manylinux-entrypoint /build_scripts/install-patchelf.sh

COPY manylinux/docker/build_scripts/install-libxcrypt.sh /build_scripts/
RUN export LIBXCRYPT_VERSION=4.4.17 && \
    export LIBXCRYPT_HASH=7665168d0409574a03f7b484682e68334764c29c21ca5df438955a381384ca07 && \
    export LIBXCRYPT_DOWNLOAD_URL=https://github.com/besser82/libxcrypt/archive && \
    manylinux-entrypoint /build_scripts/install-libxcrypt.sh


FROM runtime_base AS build_base
COPY manylinux/docker/build_scripts/install-build-packages.sh /build_scripts/
RUN manylinux-entrypoint /build_scripts/install-build-packages.sh


FROM build_base AS build_git
COPY manylinux/docker/build_scripts/build-git.sh /build_scripts/
RUN export GIT_ROOT=git-2.30.0 && \
    export GIT_HASH=d24c4fa2a658318c2e66e25ab67cc30038a35696d2d39e6b12ceccf024de1e5e && \
    export GIT_DOWNLOAD_URL=https://www.kernel.org/pub/software/scm/git && \
    manylinux-entrypoint /build_scripts/build-git.sh


FROM build_base AS build_cmake
COPY manylinux/docker/build_scripts/build-cmake.sh /build_scripts/
RUN export CMAKE_VERSION=3.18.3 && \
    export CMAKE_HASH=2c89f4e30af4914fd6fb5d00f863629812ada848eee4e2d29ec7e456d7fa32e5 && \
    export CMAKE_DOWNLOAD_URL=https://github.com/Kitware/CMake/releases/download && \
    manylinux-entrypoint /build_scripts/build-cmake.sh


FROM build_base AS build_swig
COPY manylinux/docker/build_scripts/build-swig.sh /build_scripts/
RUN export SWIG_ROOT=swig-4.0.2 && \
    export SWIG_HASH=d53be9730d8d58a16bf0cbd1f8ac0c0c3e1090573168bfa151b01eb47fa906fc && \
    export SWIG_DOWNLOAD_URL=https://sourceforge.net/projects/swig/files/swig/${SWIG_ROOT} && \
    export PCRE_ROOT=pcre-8.44 && \
    export PCRE_HASH=aecafd4af3bd0f3935721af77b889d9024b2e01d96b58471bd91a3063fb47728 && \
    export PCRE_DOWNLOAD_URL=https://ftp.pcre.org/pub/pcre && \
    manylinux-entrypoint /build_scripts/build-swig.sh


FROM build_base AS build_cpython
COPY manylinux/docker/build_scripts/build-sqlite3.sh /build_scripts/
RUN export SQLITE_AUTOCONF_ROOT=sqlite-autoconf-3340000 && \
    export SQLITE_AUTOCONF_HASH=bf6db7fae37d51754737747aaaf413b4d6b3b5fbacd52bdb2d0d6e5b2edd9aee && \
    export SQLITE_AUTOCONF_DOWNLOAD_URL=https://www.sqlite.org/2020 && \
    manylinux-entrypoint /build_scripts/build-sqlite3.sh

COPY manylinux/docker/build_scripts/build-openssl.sh /build_scripts/
RUN export OPENSSL_ROOT=openssl-1.1.1j && \
    export OPENSSL_HASH=aaf2fcb575cdf6491b98ab4829abf78a3dec8402b8b81efc8f23c00d443981bf && \
    export OPENSSL_DOWNLOAD_URL=https://www.openssl.org/source && \
    manylinux-entrypoint /build_scripts/build-openssl.sh

COPY manylinux/docker/build_scripts/build-cpython.sh /build_scripts/
FROM build_cpython AS build_cpython39
COPY manylinux/docker/build_scripts/ambv-pubkey.txt /build_scripts/ambv-pubkey.txt
RUN manylinux-entrypoint gpg --import /build_scripts/ambv-pubkey.txt
# Change build script to use shared libraries
RUN sed -ie 's/--disable-shared/--enable-ipv6 --enable-shared --enable-optimizations --with-lto/g' /build_scripts/build-cpython.sh
ARG PYTHON_VERSION
RUN manylinux-entrypoint /build_scripts/build-cpython.sh $PYTHON_VERSION

FROM build_base AS build_wine
COPY build-wine.sh /build_scripts/
RUN export WINE_ROOT=wine-5.0.2 && \
    export WINE_HASH=c2c284f470874b35228327c3972bc29c3a9d8d98abd71dbf81c288b8642becbc && \
    export WINE_DOWNLOAD_URL=https://dl.winehq.org/wine/source/5.0 && \
    manylinux-entrypoint /build_scripts/build-wine.sh

FROM build_wine AS wine_python
ARG PYTHON_VERSION
ARG PYINSTALLER_VERSION
ENV PYTHON_VERSION $PYTHON_VERSION
ENV PYINSTALLER_VERSION $PYINSTALLER_VERSION
COPY install-python-wine.sh /build_scripts/
RUN manylinux-entrypoint /build_scripts/install-python-wine.sh


FROM runtime_base
ARG DUMBINIT_VERSION
ARG PYTHON_VERSION
ARG PYINSTALLER_VERSION

COPY --from=build_git /manylinux-rootfs /
COPY --from=build_cmake /manylinux-rootfs /
COPY --from=build_swig /manylinux-rootfs /
COPY --from=build_cpython /manylinux-rootfs /
COPY --from=wine_python /manylinux-rootfs /
COPY --from=build_cpython39 /opt/_internal /opt/_internal/

ENV LD_LIBRARY_PATH=/opt/_internal/cpython-$PYTHON_VERSION/lib:$LD_LIBRARY_PATH
ENV PATH=/opt/_internal/cpython-$PYTHON_VERSION/bin:$PATH
ENV SSL_CERT_FILE=/opt/_internal/certs.pem

ENV WINEARCH win64
ENV WINEDEBUG fixme-all
ENV WINEPREFIX /wine

ENV W_DRIVE_C=/wine/drive_c
ENV W_WINDIR_UNIX="$W_DRIVE_C/windows"
ENV W_SYSTEM64_DLLS="$W_WINDIR_UNIX/system32"
ENV W_TMP="$W_DRIVE_C/windows/temp/_"
ENV HOME=/root
ENV PATH $PATH:/Library/Frameworks/Mono.framework/Commands
ENV PYTHON_VERSION $PYTHON_VERSION
ENV PYINSTALLER_VERSION $PYINSTALLER_VERSION

COPY manylinux/docker/build_scripts/finalize.sh manylinux/docker/build_scripts/update-system-packages.sh manylinux/docker/build_scripts/python-tag-abi-tag.py manylinux/docker/build_scripts/requirements.txt manylinux/docker/build_scripts/requirements-tools.txt /build_scripts/
RUN sed -ie 's/cp37-cp37m/cp39-cp39/g' /build_scripts/finalize.sh
RUN sed -ie 's/hardlink -cv \/opt\/_internal//g' /build_scripts/finalize.sh
RUN manylinux-entrypoint /build_scripts/finalize.sh && rm -rf /build_scripts

# Install perl rename and gnutls for wine
RUN yum -y install perl-ExtUtils-MakeMaker gnutls
RUN curl -fsSLo - "https://search.cpan.org/CPAN/authors/id/R/RM/RMBARKER/File-Rename-1.10.tar.gz" | tar -xz && ( cd "File-Rename-1.10"; perl "Makefile.PL"; make && make install; cd ..; rm -fr "File-Rename-1.10" )

COPY 3fa7e0328081bff6a14da29aa6a19b38d3d831ef.asc /
RUN rpmkeys --import "/3fa7e0328081bff6a14da29aa6a19b38d3d831ef.asc" && rm -f /3fa7e0328081bff6a14da29aa6a19b38d3d831ef.asc
RUN curl https://download.mono-project.com/repo/centos7-stable.repo | tee /etc/yum.repos.d/mono-centos7-stable.repo
RUN yum -y install mono-devel krb5-devel && yum -y clean all && rm -f /anaconda-post.log

COPY msvc/ /msvc/
COPY --from=vcbuilder /opt/msvc /opt/msvc
RUN bash /msvc/install.sh /opt/msvc && rm -fr /msvc

COPY hooks/ /hooks/
COPY --from=alpine_pyinstaller / /alpine/

# update pip/certifi
RUN pip --no-cache-dir install -U pip certifi || true

# install pyinstaller
RUN pip --no-cache-dir install pyinstaller==$PYINSTALLER_VERSION

WORKDIR /src
COPY entrypoint.sh /entrypoint.sh
COPY switch_to_alpine.sh /switch_to_alpine.sh
RUN chmod +x /entrypoint.sh /switch_to_alpine.sh

RUN curl -L -o /usr/bin/dumb-init https://github.com/Yelp/dumb-init/releases/download/v${DUMBINIT_VERSION}/dumb-init_${DUMBINIT_VERSION}_x86_64 && \
    chmod +x /usr/bin/dumb-init

VOLUME /src
ENTRYPOINT ["/usr/bin/dumb-init", "--", "/entrypoint.sh"]
