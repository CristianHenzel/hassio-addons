#!/usr/bin/env bashio

SHARE=$(bashio::config "share")
USERNAME=$(bashio::config "username")
PASSWORD=$(bashio::config "password")
SYNC_INTERVAL=$(bashio::config "sync_interval")

mkdir -p /share
echo -e "username=${USERNAME}\npassword=${PASSWORD}" > /etc/cifs.creds

sync() {
	mount -t cifs -o rw,credentials=/etc/cifs.creds "${SHARE}" /share || return 1
	rsync -a --delete /backup/ /share || return 1
	umount /share || return 1
	bashio::log.info "Sync finished successfully"
}

while true; do
	sync || bashio::log.error "Error copying backups to share"

	sleep "${SYNC_INTERVAL}"
done
