ARG ALPINE_TAG

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

FROM $ALPINE_TAG as alpine_build

FROM quay.io/pypa/manylinux2010_x86_64
LABEL maintainer="Fyde Inc"

ENV WINEARCH win64
ENV WINEDEBUG fixme-all
ENV WINEPREFIX /wine

ENV W_DRIVE_C=/wine/drive_c
ENV W_WINDIR_UNIX="$W_DRIVE_C/windows"
ENV W_SYSTEM64_DLLS="$W_WINDIR_UNIX/system32"
ENV W_TMP="$W_DRIVE_C/windows/temp/_$0"

ENV PATH $PATH:/Library/Frameworks/Mono.framework/Commands
ENV SSL_CERT_FILE=/opt/_internal/certs.pem

COPY build_scripts/ /build_scripts/
RUN bash /build_scripts/build.sh && rm -fr /build_scripts

COPY msvc/ /msvc/
COPY --from=vcbuilder /opt/msvc /opt/msvc
RUN bash /msvc/install.sh /opt/msvc && rm -fr /msvc

COPY hooks/ /hooks/

COPY --from=alpine_build / /alpine/

WORKDIR /src
COPY entrypoint.sh /entrypoint.sh
COPY switch_to_alpine.sh /switch_to_alpine.sh
RUN chmod +x /entrypoint.sh /switch_to_alpine.sh

ARG dumbinit_version=1.2.1
RUN curl -L -o /usr/bin/dumb-init https://github.com/Yelp/dumb-init/releases/download/v${dumbinit_version}/dumb-init_${dumbinit_version}_amd64 && \
    chmod +x /usr/bin/dumb-init

VOLUME /src
ENTRYPOINT ["/usr/bin/dumb-init", "--", "/entrypoint.sh"]
