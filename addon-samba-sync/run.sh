#!/usr/bin/env bashio

SHARE=$(bashio::config "share")
USERNAME=$(bashio::config "username")
PASSWORD=$(bashio::config "password")
SYNC_INTERVAL=$(bashio::config "sync_interval")

echo -e "username=${USERNAME}\npassword=${PASSWORD}" > /etc/cifs.creds
echo "/cifs /etc/auto.cifs" > /etc/auto.master
echo "share -fstype=cifs,rw,credentials=/etc/cifs.creds :${SHARE}" > /etc/auto.cifs
/usr/sbin/automount --pid-file /run/autofs.pid

while true; do
	rsync -a --delete /backup/ /cifs/share || bashio::log.error "Error copying backups to share"

	sleep "${SYNC_INTERVAL}"
done
