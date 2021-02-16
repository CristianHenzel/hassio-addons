#!/usr/bin/env bashio

S3_ACCESSKEY=$(bashio::config "s3_accesskey")
S3_BUCKET=$(bashio::config "s3_bucket")
S3_ENDPOINT=$(bashio::config "s3_endpoint")
S3_FLAGS_STR=$(bashio::config "s3_flags")
S3_OUTPUT_FILTER=$(bashio::config "s3_output_filter")
S3_REGION=$(bashio::config "s3_region")
S3_SECRETKEY=$(bashio::config "s3_secretkey")
SYNC_INTERVAL=$(bashio::config "sync_interval")

read -ra S3_FLAGS <<< "${S3_FLAGS_STR}"

aws configure set default.s3.signature_version s3v4
aws configure set aws_access_key_id "${S3_ACCESSKEY}"
aws configure set aws_secret_access_key "${S3_SECRETKEY}"
aws configure set region "${S3_REGION}"

while true; do
	bashio::log.info "Synchronizing to S3 bucket"
	aws --endpoint-url "${S3_ENDPOINT}" "${S3_FLAGS[@]}" s3 sync /backup/ "s3://${S3_BUCKET}/" 2>&1 | grep -v "${S3_OUTPUT_FILTER}" || true

	sleep "${SYNC_INTERVAL}"
done
