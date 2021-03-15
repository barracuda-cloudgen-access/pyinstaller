#!/bin/sh

unalias rm mv 2>/dev/null
unset LD_LIBRARY_PATH

# copy /lib first so we can use alpine binaries linked to musl
rm -f /lib && mv -f -t / /alpine/lib

export PATH=/alpine/bin:/alpine/usr/local/sbin:/alpine/usr/local/bin:/alpine/usr/sbin:/alpine/usr/bin:/alpine/sbin:/alpine/bin:/alpine/root/.cargo/bin
rm -fr /bin /etc /home /lib64 /media /mnt /opt /root /run /sbin /srv /usr /var
rm -fr /alpine/etc/hosts /alpine/etc/hostname /alpine/etc/resolv.conf /alpine/sys /alpine/dev /alpine/tmp
cp -af --remove-destination -t / /alpine/*

export SSL_CERT_FILE="$(python -c "import site; print(site.getsitepackages()[0])")/certifi/cacert.pem"

/usr/local/bin/entrypoint-alpine.sh "$@"
