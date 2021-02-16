#!/usr/bin/env bashio

API_TOKEN=$(bashio::config "api_token")
DOMAINS=$(bashio::config "domains")
CACHE_DIR="/tmp/do-ddns"
CACHE_TTL=180

cache_get() {
	local DOM; DOM="${1}"
	local TIM; TIM=$(date +%s)

	if [ -e "${CACHE_DIR}/${DOM}.cache" ]; then
		if [ -e "${CACHE_DIR}/${DOM}.ttl" ]; then
			local TTL; TTL=$(cat "${CACHE_DIR}/${DOM}.ttl")
			if [ "${TTL}" -gt "${TIM}" ]; then
				cat "${CACHE_DIR}/${DOM}.cache"
				return 0
			else
				bashio::log.debug "Cache for ${DOM} expired"
			fi
		else
			bashio::log.debug "TTL file for ${DOM} does not exist"
		fi
	else
		bashio::log.debug "Cache file for ${DOM} does not exist"
	fi

	# Return an invalid response if cache isn't valid
	echo "999.999.999.999"
}

cache_set() {
	local DOM; DOM="${1}"
	local REC; REC="${2}"
	local TIM; TIM=$(date +%s)

	if [ ! -d "${CACHE_DIR}" ]; then
		mkdir -p "${CACHE_DIR}"
	fi

	echo "${REC}" > "${CACHE_DIR}/${DOM}.cache"
	date --date="+${CACHE_TTL} seconds" +%s > "${CACHE_DIR}/${DOM}.ttl"
}

do_api_call() {
	local TYPE; TYPE="${1}"
	local DATA; DATA="${2}"
	local DOMN; DOMN="${3}"
	local SUFF; SUFF="${4}"
	local FILT; FILT="${5}"

	local RESPONSE; RESPONSE=$(curl -sSm 5 -X "${TYPE}" \
		-H "Content-Type: application/json" \
		-H "Authorization: Bearer ${API_TOKEN}" \
		-d "${DATA}" \
		"https://api.digitalocean.com/v2/domains/${DOMN}/records${SUFF}")
	bashio::log.trace "DO API response: ${RESPONSE}"
	jq -r "${FILT}" <<< "${RESPONSE}"
}

dot_query() {
	local DOM; DOM="${1}"
	curl -sSm 5 -X GET "https://9.9.9.9:5053/dns-query?name=${DOM}" | jq -r ".Answer[0].data"
}

while true; do
	CURRENT_IP=$(curl -sSm 5 -X GET "https://api.ipify.org") || {
			bashio::log.error "Failed to get current IP"
			sleep 5s
			continue
		}
	bashio::log.debug "Current IP: ${CURRENT_IP}"

	for DOMAIN in ${DOMAINS//,/ }; do
		TLD=$(echo "${DOMAIN}" | cut -d@ -f2)
		FQDN="${DOMAIN//@/.}"

		# Check record in cache
		CURRENT_RECORD=$(cache_get "${FQDN}")
		bashio::log.debug "Current CACHE record for ${FQDN}: ${CURRENT_RECORD}"
		if [ "${CURRENT_RECORD}" = "${CURRENT_IP}" ]; then
			continue
		fi

		# Check record through a DNS-over-HTTPS call
		CURRENT_RECORD=$(dot_query "${FQDN}") || {
				bashio::log.error "Failed to get DNS record"
				sleep 5s
				continue
			}
		bashio::log.debug "Current DNS record for ${FQDN}: ${CURRENT_RECORD}"
		if [ "${CURRENT_RECORD}" = "${CURRENT_IP}" ]; then
			cache_set "${FQDN}" "${CURRENT_IP}"
			continue
		fi

		# Check record through DO API
		CURRENT_RECORD=$(do_api_call "GET" "{}" "${TLD}" "?name=${FQDN}&type=A" ".domain_records[0].data") || {
				bashio::log.error "Failed to get API record"
				sleep 5s
				continue
			}
		bashio::log.debug "Current API record for ${FQDN}: ${CURRENT_RECORD}"
		if [ "${CURRENT_RECORD}" = "${CURRENT_IP}" ]; then
			cache_set "${FQDN}" "${CURRENT_IP}"
			continue
		fi

		# Update record through DO API
		bashio::log.info "Updating record for ${FQDN} (${CURRENT_RECORD}), because it is different from current IP (${CURRENT_IP})"
		DO_REC_ID=$(do_api_call "GET" "{}" "${TLD}" "?name=${FQDN}&type=A" ".domain_records[0].id") || {
				bashio::log.error "Failed to get record id"
				sleep 5s
				continue
			}
		CURRENT_RECORD=$(do_api_call "PUT" "{\"data\":\"$CURRENT_IP\"}" "${TLD}" "/${DO_REC_ID}" ".domain_record.data") || {
				bashio::log.error "Failed to update record"
				sleep 5s
				continue
			}
		if [ "${CURRENT_RECORD}" = "${CURRENT_IP}" ]; then
			cache_set "${FQDN}" "${CURRENT_IP}"
		else
			bashio::log.error "Error updating DNS record for ${FQDN} (${CURRENT_RECORD})"
		fi
	done

	sleep 5s
done
