# Get from: https://github.com/docker-library/python/blob/master/3.9/alpine3.12/Dockerfile
ARG PYTHON_VERSION=3.9.0
ARG PYTHON_PIP_VERSION=20.3.1
ARG PYTHON_GET_PIP_URL=https://github.com/pypa/get-pip/raw/91630a4867b1f93ba0a12aa81d0ec4ecc1e7eeb9/get-pip.py
ARG PYTHON_GET_PIP_SHA256=d48ae68f297cac54db17e4107b800faae0e5210131f9f386c30c0166bf8d81b7
ARG OPENSSL_VERSION=1.1.1h
ARG OPENSSL_SHA512=da50fd99325841ed7a4367d9251c771ce505a443a73b327d8a46b2c6a7d2ea99e43551a164efc86f8743b22c2bdb0020bf24a9cbd445e9d68868b2dc1d34033a
ARG GPG_KEY=E3FF2839C048B25C084DEBE9B26995E310250568
ARG DUMBINIT_VERSION=1.2.3

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
ARG OPENSSL_SHA512
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

RUN set -ex \
	&& wget -O python.tar.xz "https://www.python.org/ftp/python/${PYTHON_VERSION%%[a-z]*}/Python-$PYTHON_VERSION.tar.xz" \
	&& wget -O python.tar.xz.asc "https://www.python.org/ftp/python/${PYTHON_VERSION%%[a-z]*}/Python-$PYTHON_VERSION.tar.xz.asc" \
	&& export GNUPGHOME="$(mktemp -d)" \
	&& gpg --batch --keyserver ha.pool.sks-keyservers.net --recv-keys "$GPG_KEY" \
	&& gpg --batch --verify python.tar.xz.asc python.tar.xz \
	&& { command -v gpgconf > /dev/null && gpgconf --kill all || :; } \
	&& rm -rf "$GNUPGHOME" python.tar.xz.asc \
	&& mkdir -p /usr/src/python \
	&& tar -xJC /usr/src/python --strip-components=1 -f python.tar.xz \
	&& rm python.tar.xz

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
ENV OPENSSL_SHA512 $OPENSSL_SHA512
RUN wget -O openssl-${OPENSSL_VERSION}.tar.gz https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz \
    && echo "$OPENSSL_SHA512  openssl-${OPENSSL_VERSION}.tar.gz" > sums \
    && sha512sum -c sums \
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

ENV PATH /usr/local/bin:$PATH
ENV LANG C.UTF-8

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

RUN INFO="$(wget -qO - "https://api.github.com/repos/pyinstaller/pyinstaller/releases/latest")" \
    && wget -qO pyinstaller.tar.gz https://github.com/pyinstaller/pyinstaller/releases/download/$(echo "$INFO"|grep '"tag_name"'|cut -d'"' -f4)/$(echo "$INFO"|grep '"name"'|grep '.tar.gz"'|cut -d'"' -f4) \
    && tar -C /tmp -xzf pyinstaller.tar.gz \
    && cd /tmp/pyinstaller*/bootloader \
    && CFLAGS="-Wno-stringop-overflow -Wno-stringop-truncation" python ./waf configure --no-lsb all \
    && pip install .. \
    && rm -Rf /tmp/pyinstaller \
    && rm -Rf /root/.cache

COPY alpine-bin/ /usr/local/bin
RUN chmod +x /usr/local/bin/*


FROM quay.io/pypa/manylinux2010_x86_64
LABEL maintainer="Barracuda Networks"

ARG DUMBINIT_VERSION
ARG PYTHON_VERSION

ENV WINEARCH win64
ENV WINEDEBUG fixme-all
ENV WINEPREFIX /wine

ENV W_DRIVE_C=/wine/drive_c
ENV W_WINDIR_UNIX="$W_DRIVE_C/windows"
ENV W_SYSTEM64_DLLS="$W_WINDIR_UNIX/system32"
ENV W_TMP="$W_DRIVE_C/windows/temp/_$0"

ENV PATH $PATH:/Library/Frameworks/Mono.framework/Commands
ENV SSL_CERT_FILE=/opt/_internal/certs.pem
ENV PYTHON_VERSION=$PYTHON_VERSION

# Centos 6 is EOL and is no longer available from the usual mirrors, so switch
# to https://vault.centos.org
RUN sed -i 's/enabled=1/enabled=0/g' /etc/yum/pluginconf.d/fastestmirror.conf && \
    sed -i 's/^mirrorlist/#mirrorlist/g' /etc/yum.repos.d/*.repo && \
    sed -i 's;^#baseurl=http://mirror;baseurl=https://vault;g' /etc/yum.repos.d/*.repo

COPY build_scripts/ /build_scripts/
RUN bash /build_scripts/build.sh && rm -fr /build_scripts

COPY msvc/ /msvc/
COPY --from=vcbuilder /opt/msvc /opt/msvc
RUN bash /msvc/install.sh /opt/msvc && rm -fr /msvc

COPY hooks/ /hooks/

COPY --from=alpine_pyinstaller / /alpine/

WORKDIR /src
COPY entrypoint.sh /entrypoint.sh
COPY switch_to_alpine.sh /switch_to_alpine.sh
RUN chmod +x /entrypoint.sh /switch_to_alpine.sh

RUN curl -L -o /usr/bin/dumb-init https://github.com/Yelp/dumb-init/releases/download/v${DUMBINIT_VERSION}/dumb-init_${DUMBINIT_VERSION}_x86_64 && \
    chmod +x /usr/bin/dumb-init

VOLUME /src
ENTRYPOINT ["/usr/bin/dumb-init", "--", "/entrypoint.sh"]
