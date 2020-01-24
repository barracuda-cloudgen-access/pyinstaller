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

COPY build_scripts/* /build_scripts/
RUN bash /build_scripts/build.sh && rm -fr /build_scripts

WORKDIR /src
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ARG dumbinit_version=1.2.1
RUN curl -L -o /usr/bin/dumb-init https://github.com/Yelp/dumb-init/releases/download/v${dumbinit_version}/dumb-init_${dumbinit_version}_amd64 && \
    chmod +x /usr/bin/dumb-init

VOLUME /src
ENTRYPOINT ["/usr/bin/dumb-init", "--", "/entrypoint.sh"]
