#!/usr/bin/with-contenv bashio

BACKUP_KEEP_DAYS=$(bashio::config "backup_keep_days")
NOW=$(date -Iseconds)
BACKUPS=$(bashio::api.supervisor "GET" "/backups" false ".backups[]")

createbackup() {
	local BACKUPNAME; BACKUPNAME="full-$(date -I)"

	while read -r line; do
		NAME=$(bashio::jq "${line}" ".name")
		if [ "${NAME}" = "${BACKUPNAME}" ]; then
			bashio::log.info "Skipping backup creation because backup for current date already exists"
			return
		fi
	done <<< "${BACKUPS}"

	bashio::log.info "Creating new backup"
	name=$(bashio::var.json name "${BACKUPNAME}")
	bashio::api.supervisor "POST" "/backups/new/full" "${name}"
}

cleanup() {
	if [ "${BACKUP_KEEP_DAYS}" = "0" ]; then
		return
	fi

	while read -r line; do
		SLUG=$(bashio::jq "${line}" ".slug")
		NAME=$(bashio::jq "${line}" ".name")
		DATE=$(bashio::jq "${line}" ".date")
		AGE=$(datediff "${NOW}" "${DATE}")
		if [ -z "${NAME}" ]; then
			FULLNAME="${SLUG}"
		else
			FULLNAME="$NAME (${SLUG})"
		fi

		if [ "${AGE}" -gt "${BACKUP_KEEP_DAYS}" ]; then
			bashio::log.info "Deleting backup ${FULLNAME}, because it is ${AGE} days old"
			bashio::api.supervisor "DELETE" "/backups/${SLUG}"
		else
			bashio::log.info "Skipping backup deletion of ${FULLNAME}, because it is only ${AGE} days old"
		fi
	done <<< "${BACKUPS}"
}

datediff() {
	d1=$(date -d "$1" +%s)
	d2=$(date -d "$2" +%s)
	echo $(( (d1 - d2) / 86400 ))
}

while true; do
	NOW=$(date -Iseconds)
	BACKUPS=$(bashio::api.supervisor "GET" "/backups" false ".backups[]")

	createbackup
	cleanup
	sleep 3h
done
