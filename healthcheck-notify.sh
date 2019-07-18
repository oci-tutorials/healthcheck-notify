#!/bin/sh

# Version: 1.0
# Usage:
# 1) Edit the variables in the "TODO" section below
# 2) Make healthcheck-notify.sh executable: chmod u+x healthcheck-notify.sh
# 3) Run healthcheck-notify.sh in the background: nohup ./healthcheck-notify.sh &

# TODO: update these values to your own
# Tenancy and auth details
homeRegion="eu-frankfurt-1"
topicRegion="uk-london-1" # this needs to match the region where the notification topic is created (can be same as homeRegion)
tenancyId="ocid1.tenancy.oc1..aaaaaaaacvifcvXXXXXXXXXXXXXXXXXXXXXXXXXvo4viia5spdthmwwtje2a";
authUserId="ocid1.user.oc1..aaaaaaaaxdbdn57aXXXXXXXXXXXXXXXXXXXXXXXXXbrplechz5ezx56j4bza";
keyFingerprint="4d:93:57:b2:XX:XX:XX:XX:XX:XX:XX:XX:b2:d3:01:f5";
privateKeyPath="/path/to/private_key";

# Probe details
PROBE_ID="ocid1.pingmonitor.oc1..aaaaaaaaeroi23XXXXXXXXXXXXXXXXXXXXXXXXXvsoz3uhttdcdbdwmxp3nq"
PROBE_TYPE="ping" # this can be "ping" or "http"
CHECK_INTERVAL=30 # this should be equal or greater than the probe "interval" property

# Notification topic details
TOPIC_ID="ocid1.onstopic.oc1.uk-london-1.aaaaaaaav252wgiXXXXXXXXXXXXXXXXXXXXXXXXXtd5ma2dqqkkl22whawxq"
KEEP_SENDING_NOTIFICATIONS=false # if true, notifications will be sent periodically until the probe becomes healthy again
# END TODO





function oci_curl {
  local alg=rsa-sha256
  local sigVersion="1"
  local now="$(LC_ALL=C \date -u "+%a, %d %h %Y %H:%M:%S GMT")"
  local host=$1
  local method=$2
  local extra_args
  local keyId="$tenancyId/$authUserId/$keyFingerprint"

  case $method in

    "get" | "GET")
    local target=$3
    extra_args=("${@: 4}")
    local curl_method="GET";
    local request_method="get";
    ;;

    "delete" | "DELETE")
    local target=$3
    extra_args=("${@: 4}")
    local curl_method="DELETE";
    local request_method="delete";
    ;;

    "head" | "HEAD")
    local target=$3
    extra_args=("--head" "${@: 4}")
    local curl_method="HEAD";
    local request_method="head";
    ;;

    "post" | "POST")
    local body=$3
    local target=$4
    extra_args=("${@: 5}")
    local curl_method="POST";
    local request_method="post";
    local content_sha256="$(openssl dgst -binary -sha256 < $body | openssl enc -e -base64)";
    local content_type="application/json";
    local content_length="$(wc -c < $body | xargs)";
    ;;

    "put" | "PUT")
    local body=$3
    local target=$4
    extra_args=("${@: 5}")
    local curl_method="PUT"
    local request_method="put"
    local content_sha256="$(openssl dgst -binary -sha256 < $body | openssl enc -e -base64)";
    local content_type="application/json";
    local content_length="$(wc -c < $body | xargs)";
    ;;

    *) echo "invalid method"; return;;
esac

# This line will url encode all special characters in the request target except "/", "?", "=", and "&", since those characters are used
# in the request target to indicate path and query string structure. If you need to encode any of "/", "?", "=", or "&", such as when
# used as part of a path value or query string key or value, you will need to do that yourself in the request target you pass in.

local escaped_target="$(echo $( rawurlencode "$target" ))"
local request_target="(request-target): $request_method $escaped_target"
local date_header="date: $now"
local host_header="host: $host"
local content_sha256_header="x-content-sha256: $content_sha256"
local content_type_header="content-type: $content_type"
local content_length_header="content-length: $content_length"
local signing_string="$request_target\n$date_header\n$host_header"
local headers="(request-target) date host"
local curl_header_args
curl_header_args=(-H "$date_header")
local body_arg
body_arg=()

if [ "$curl_method" = "PUT" -o "$curl_method" = "POST" ]; then
  signing_string="$signing_string\n$content_sha256_header\n$content_type_header\n$content_length_header"
  headers=$headers" x-content-sha256 content-type content-length"
  curl_header_args=("${curl_header_args[@]}" -H "$content_sha256_header" -H "$content_type_header" -H "$content_length_header")
  body_arg=(--data-binary @${body})
fi

local sig=$(printf '%b' "$signing_string" | \
      openssl dgst -sha256 -sign $privateKeyPath | \
      openssl enc -e -base64 | tr -d '\n')

curl "${extra_args[@]}" "${body_arg[@]}" -X $curl_method -sS https://${host}${escaped_target} "${curl_header_args[@]}" \
  -H "Authorization: Signature version=\"$sigVersion\",keyId=\"$keyId\",algorithm=\"$alg\",headers=\"${headers}\",signature=\"$sig\""
}
# url encode all special characters except "/", "?", "=", and "&"
function rawurlencode {
  local string="${1}"
  local strlen=${#string}
  local encoded=""
  local pos c o

  for (( pos=0 ; pos<strlen ; pos++ )); do
  c=${string:$pos:1}
  case "$c" in
    [-_.~a-zA-Z0-9] | "/" | "?" | "=" | "&" ) o="${c}" ;;
    * )               printf -v o '%%%02x' "'$c"
  esac
  encoded+="${o}"
  done

  echo "${encoded}"
}





PROBE_TYPE=`echo "$PROBE_TYPE" | awk '{print tolower($0)}'`
SENT=false

# Sequence to execute when timeout triggers.
trigger_cmd() {
  timestamp=$(date)
  echo ""
  echo "Checking probe at $timestamp"

  # Retrieve latest probe response
  # More info below: 
  # https://docs.cloud.oracle.com/iaas/api/#/en/healthchecks/20180501/PingProbeResultSummary/ListPingProbeResults
  # https://docs.cloud.oracle.com/iaas/api/#/en/healthchecks/20180501/HttpProbeResultSummary/ListHttpProbeResults
  probeResponse=`oci_curl healthchecks."$homeRegion".oraclecloud.com get "/20180501/${PROBE_TYPE}ProbeResults/$PROBE_ID?limit=1&sortOrder=DESC"`
  
  probeURL="https://console.$homeRegion.oraclecloud.com/healthchecks/$PROBE_ID"
  isHealthy=`echo "$probeResponse" | jq -r ".[0].isHealthy"`
  target=`echo "$probeResponse" | jq -r ".[0].target"`
  protocol=`echo "$probeResponse" | jq -r ".[0].protocol"`
  port=`echo "$probeResponse" | jq -r ".[0].connection.port"`

  if ! $isHealthy; then
    echo "Probe is unhealthy"
    
    if ! $KEEP_SENDING_NOTIFICATIONS && $SENT; then
      echo "Notification already sent for current probe failure"
      return 
    fi

    # Prepare JSON payload for notification
    JSON_STRING=$( jq -n \
                  "{ \
                     title: \"Alarm notification for $target\", \
                     body: \"Probe is unhealthy\\n\\nProtocol: $protocol\\nTarget: $target\\nPort: $port\\n\\nTimestamp: $timestamp\\n\\nURL: $probeURL\" \
                   }")

    echo $JSON_STRING > /tmp/jsonPayload

    echo "Sending a notification"
    # More info https://docs.cloud.oracle.com/iaas/api/#/en/notification/20181201/NotificationTopic/PublishMessage
    oci_curl cp.notification."$topicRegion".oraclecloud.com post /tmp/jsonPayload "/20181201/topics/$TOPIC_ID/messages"
    SENT=true

    rm /tmp/jsonPayload
  else
    echo "Probe is healthy"
    if $SENT; then
      # Prepare JSON payload for notification
      JSON_STRING=$( jq -n \
                    "{ \
                       title: \"Alarm notification for $target\", \
                       body: \"Probe is healthy\\n\\nProtocol: $protocol\\nTarget: $target\\nPort: $port\\n\\nTimestamp: $timestamp\\n\\nURL: $probeURL\" \
                     }")

      echo $JSON_STRING > /tmp/jsonPayload

      echo "Sending a notification"
      # More info https://docs.cloud.oracle.com/iaas/api/#/en/notification/20181201/NotificationTopic/PublishMessage
      oci_curl cp.notification."$topicRegion".oraclecloud.com post /tmp/jsonPayload "/20181201/topics/$TOPIC_ID/messages"
      
      rm /tmp/jsonPayload
    fi 
    SENT=false
  fi
}

echo "Started at $(date)"

while sleep $CHECK_INTERVAL; do
  trigger_cmd
done

echo "Finished at $(date)"
