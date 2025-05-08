#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# Automatically update your CloudFlare DNS record to the IP, Dynamic DNS
# Can retrieve cloudflare Domain id and list zone's, because, lazy

# Installation:
# curl https://raw.githubusercontent.com/meepuru/cloudflare-api-v4-ddns-fix/master/cf-v4-ddns.sh > /usr/local/bin/cf-ddns.sh && chmod +x /usr/local/bin/cf-ddns.sh
# run `crontab -e` and add next line:
# */1 * * * * /usr/local/bin/cf-ddns.sh >/dev/null 2>&1
# or you need log:
# */1 * * * * /usr/local/bin/cf-ddns.sh >> /var/log/cf-ddns.log 2>&1


# Usage:
# cf-ddns.sh -k Cloudflare account owned tokens \
#            -h host.example.com \     # fqdn of the record you want to update
#            -z example.com \          # will show you all zones if forgot, but you need this
#            -t A|AAAA                 # specify ipv4/ipv6, default: ipv4

# Optional flags:
#            -f false|true \           # force dns update, disregard local stored ip
#            -u user@example.com \     # Global API Key related setting, when provided, CFKEY or -k will be assumed as a Global API Key, be careful to use
#            -? \                      # show usage

# default config
HELP=false

# Warn: Deprecated, use account owned tokens instead, see https://dash.cloudflare.com/profile/api-tokens
# Fill in this field will result in $CFKEY assuming as a Global API Key
CFUSER=

# Account owned tokens / API tokens by defalut, see https://dash.cloudflare.com/profile/api-tokens,
# incorrect token results in error
CFKEY=

# Zone name, eg: example.com
CFZONE_NAME=

# Hostname to update, eg: homeserver.example.com
CFRECORD_NAME=

# Record type, A(IPv4)|AAAA(IPv6), default IPv4
CFRECORD_TYPE=A

# Cloudflare TTL for record, between 60 and 86400 seconds, 0 for automatically, default 0
CFTTL=0

# Ignore local file, update ip anyway, default false.
FORCE=false

WANIPSITE="https://api-ipv4.kyaru.xyz/myip"

# get parameter
while getopts k:h:z:t:f:u:"?" opts; do
  case ${opts} in
    k) CFKEY=${OPTARG} ;; # Cloudflare API token
    h) CFRECORD_NAME=${OPTARG} ;; # Hostname to update (FQDN)
    z) CFZONE_NAME=${OPTARG} ;; # Zone name (e.g., example.com)
    t) CFRECORD_TYPE=${OPTARG} ;; # Record type (A for IPv4, AAAA for IPv6)
    f) 
      if [[ "${OPTARG}" != "false" && "${OPTARG}" != "true" ]]; then
        echo "Invalid value for -f flag. Accepted values are 'false' or 'true'."
        exit 2
      fi
      FORCE=${OPTARG} ;; # Force DNS update, ignoring local stored IP
    u) CFUSER=${OPTARG} ;; # Cloudflare account email (for Global API Key)
    "?") HELP=true ;; # Show help message
    *) 
      echo "Invalid option: -${OPTARG}" 
      exit 1 
      ;; # Handle invalid options
  esac
done

if [ $HELP == true ]; then
  echo "Usage:"
  echo "    ${0} \\"
  echo "        -k token \\                # Cloudflare account owned tokens"
  echo "        -h host.example.com \\     # fqdn of the record you want to update"
  echo "        -z example.com \\          # will show you all zones if forgot, but you need this"
  echo "        -t A|AAAA \\               # specify ipv4/ipv6, default: ipv4"
  echo "Optional flags:"
  echo "        -f false|true \\           # force dns update, disregard local stored ip"
  echo "        -u user@example.com \\     # Global API Key related setting, when provided, CFKEY or -k will be assumed as a Global API Key, be careful to use"
  echo "        -? \\                      # show this help"
  exit 0
fi

# Site to retrieve WAN ip, other examples are: bot.whatismyipaddress.com, https://api.ipify.org/ ...
if [ "$CFRECORD_TYPE" = "A" ]; then
  :
elif [ "$CFRECORD_TYPE" = "AAAA" ]; then
  WANIPSITE="https://api-ipv6.kyaru.xyz/myip"
else
  echo "$CFRECORD_TYPE specified is invalid, CFRECORD_TYPE can only be A(for IPv4)|AAAA(for IPv6)"
  exit 2
fi

# If required settings are missing just exit
if [ "$CFKEY" = "" ]; then
  echo "Missing API token, get at: https://dash.cloudflare.com/profile/api-tokens"
  echo "and save in ${0} or using the -k flag"
  echo "for full usage, run ${0} -?"
  exit 2
fi
if [ "$CFRECORD_NAME" = "" ]; then 
  echo "Missing hostname, what host do you want to update?"
  echo "save in ${0} or using the -h flag"
  echo "for full usage, run ${0} -?"
  exit 2
fi

# If the hostname is not a FQDN
if [ "$CFRECORD_NAME" != "$CFZONE_NAME" ] && ! [ -z "${CFRECORD_NAME##*$CFZONE_NAME}" ]; then
  CFRECORD_NAME="$CFRECORD_NAME.$CFZONE_NAME"
  echo " => Hostname is not a FQDN, assuming $CFRECORD_NAME"
fi

# Get current and old WAN ip
# Test if WANIPSITE is reachable
if ! curl -s --head --fail ${WANIPSITE} > /dev/null; then
  echo "Error: Unable to reach WAN IP site: ${WANIPSITE}, please check your internet connection or change the WANIPSITE in ${0}."
  exit 1
fi
# Retrieve WAN IP
WAN_IP=`curl -s ${WANIPSITE}`

# Add support for dual stack IPv4/IPv6
WAN_IP_FILE=${HOME}/.cf-wan_ip_${CFRECORD_NAME}_${CFRECORD_TYPE}.txt
if [ -f $WAN_IP_FILE ]; then
  OLD_WAN_IP=`cat $WAN_IP_FILE`
else
  echo "Can't find WAN IP file, creating one"
  OLD_WAN_IP=""
fi

# If WAN IP is unchanged and without an -f flag, exit here
if [ "$WAN_IP" = "$OLD_WAN_IP" ] && [ "$FORCE" = false ]; then
  echo "WAN IP Unchanged, to update anyway use flag -f true"
  exit 0
fi

# Get zone_identifier & record_identifier
ID_FILE=$HOME/.cf-id_$CFRECORD_NAME.txt
if [ -f $ID_FILE ] && [ $(wc -l $ID_FILE | cut -d " " -f 1) == 4 ] \
  && [ "$(sed -n '3,1p' "$ID_FILE")" == "$CFZONE_NAME" ] \
  && [ "$(sed -n '4,1p' "$ID_FILE")" == "$CFRECORD_NAME" ]; then
    CFZONE_ID=$(sed -n '1,1p' "$ID_FILE")
    CFRECORD_ID=$(sed -n '2,1p' "$ID_FILE")
elif [ "$CFUSER" != "" ]; then
# If CFUSER is set, assume using Global API Key
    echo "Warning: Using Global API Key, not account owned tokens. If you want to use account owned tokens, please remove CFUSER from the script."
    echo "This is deprecated, please use account owned tokens instead."
    echo "See https://dash.cloudflare.com/profile/api-tokens for more information."
    # Get zone_identifier & record_identifier using Global API Key
    echo "Updating zone_identifier & record_identifier using Global API Key anyway"
    CFZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$CFZONE_NAME" -H "X-Auth-Email: $CFUSER" -H "X-Auth-Key: $CFKEY" -H "Content-Type: application/json" | grep -Po '(?<="id":")[^"]*' | head -1 )
    CFRECORD_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CFZONE_ID/dns_records?name=$CFRECORD_NAME" -H "X-Auth-Email: $CFUSER" -H "X-Auth-Key: $CFKEY" -H "Content-Type: application/json"  | grep -Po '(?<="id":")[^"]*' | head -1 )
    echo "$CFZONE_ID" > $ID_FILE
    echo "$CFRECORD_ID" >> $ID_FILE
    echo "$CFZONE_NAME" >> $ID_FILE
    echo "$CFRECORD_NAME" >> $ID_FILE
else
    echo "Updating zone_identifier & record_identifier"
    CFZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$CFZONE_NAME" -H "Authorization: Bearer $CFKEY" -H "Content-Type: application/json" | grep -Eo '"id":"[^"]*'|sed 's/"id":"//' | head -1 )
    CFRECORD_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CFZONE_ID/dns_records?name=$CFRECORD_NAME" -H "Authorization: Bearer $CFKEY" -H "Content-Type: application/json"  | grep -Eo '"id":"[^"]*'|sed 's/"id":"//' | head -1 )
    echo "$CFZONE_ID" > $ID_FILE
    echo "$CFRECORD_ID" >> $ID_FILE
    echo "$CFZONE_NAME" >> $ID_FILE
    echo "$CFRECORD_NAME" >> $ID_FILE
fi

# If WAN is changed, update cloudflare
echo "Updating DNS to $WAN_IP"
if [ "$CFUSER" != "" ]; then
  echo "Warning: Using Global API Key, not account owned tokens. If you want to use account owned tokens, please remove CFUSER from the script."
  echo "This is deprecated, please use account owned tokens instead."
  echo "See https://dash.cloudflare.com/profile/api-tokens for more information."
  # Update DNS record using Global API Key
  echo "Updating DNS record using Global API Key anyway"
  RESPONSE=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$CFZONE_ID/dns_records/$CFRECORD_ID" \
    -H "X-Auth-Email: $CFUSER" \
    -H "X-Auth-Key: $CFKEY" \
    -H "Content-Type: application/json" \
    --data "{\"id\":\"$CFZONE_ID\",\"type\":\"$CFRECORD_TYPE\",\"name\":\"$CFRECORD_NAME\",\"content\":\"$WAN_IP\", \"ttl\":$CFTTL}")
else
  RESPONSE=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$CFZONE_ID/dns_records/$CFRECORD_ID" \
    -H "Authorization: Bearer $CFKEY" \
    -H "Content-Type: application/json" \
    --data "{\"id\":\"$CFZONE_ID\",\"type\":\"$CFRECORD_TYPE\",\"name\":\"$CFRECORD_NAME\",\"content\":\"$WAN_IP\", \"ttl\":$CFTTL}")
fi

if [ "$RESPONSE" != "${RESPONSE%success*}" ] && [ "$(echo $RESPONSE | grep "\"success\":true")" != "" ]; then
  echo "Updated succesfuly!"
  echo $WAN_IP > $WAN_IP_FILE
  exit
else
  echo 'Something went wrong :('
  echo "Response: $RESPONSE"
  exit 1
fi
