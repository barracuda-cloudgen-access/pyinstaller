#!/bin/sh

rm -fr /bin /lib /sbin /etc/init.d /etc/ssl/certs /var/lock
cp -af --remove-destination -t / /alpine/* 2>/dev/null
/usr/local/bin/entrypoint-alpine.sh $@
