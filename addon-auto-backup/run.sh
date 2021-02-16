#!/usr/bin/env bashio

SNAPSHOT_KEEP_DAYS=$(bashio::config "snapshot_keep_days")
NOW=$(date -Iseconds)
SNAPSHOTS=$(bashio::api.supervisor "GET" "/snapshots" false ".snapshots[]")

createsnapshot() {
	local SNAPSHOTNAME; SNAPSHOTNAME="full-$(date -I)"

	while read -r line; do
		NAME=$(bashio::jq "${line}" ".name")
		if [ "${NAME}" = "${SNAPSHOTNAME}" ]; then
			bashio::log.info "Skipping snapshot creation because snapshot for current date already exists"
			return
		fi
	done <<< "${SNAPSHOTS}"

	bashio::log.info "Creating new snapshot"
	name=$(bashio::var.json name "${SNAPSHOTNAME}")
	bashio::api.supervisor "POST" "/snapshots/new/full" "${name}"
}

cleanup() {
	if [ "${SNAPSHOT_KEEP_DAYS}" = "0" ]; then
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

		if [ "${AGE}" -gt "${SNAPSHOT_KEEP_DAYS}" ]; then
			bashio::log.info "Deleting snapshot ${FULLNAME}, because it is ${AGE} days old"
			bashio::api.supervisor "DELETE" "/snapshots/${SLUG}"
		else
			bashio::log.info "Skipping snapshot deletion of ${FULLNAME}, because it is only ${AGE} days old"
		fi
	done <<< "${SNAPSHOTS}"
}

datediff() {
	d1=$(date -d "$1" +%s)
	d2=$(date -d "$2" +%s)
	echo $(( (d1 - d2) / 86400 ))
}

while true; do
	NOW=$(date -Iseconds)
	SNAPSHOTS=$(bashio::api.supervisor "GET" "/snapshots" false ".snapshots[]")

	createsnapshot
	cleanup
	sleep 3h
done
