#!/bin/bash
###############################################################
#
# PowerDNS Helper Scripts
#
# Mass Update PTR and A Records
#
################################################################

set -e

# Cleanup any possible tmp files from previous failed or cancelled batches
rm -rf tmp

PTR_TEMPLATE="OverwriteAddPTR.template.json"
A_RECORD_TEMPLATE="OverwriteAddA.template.json"

########### Import config vars ###########
source pdns.conf

###### Create Temporary Directory ########
mkdir tmp

########## Define some functions ##########

gen_ip_list() {
  nmap -n -sL $IP_SUBNET | awk '/Nmap scan report/{print $NF}' > tmp/ip-list.txt
}


create_zone_ptr() {

# Check if the zone exists
response=$(curl -s -o /dev/null -w "%{http_code}" -X GET \
  -H "X-API-Key: $PDNS_API_KEY" \
  -H "Content-Type: application/json" \
  "$PDNS_API_URL/api/v1/servers/localhost/zones/$PDNS_ZONE_ID")

if [ "$response" -eq 404 ]; then
  echo "Zone does not exist. Creating zone..."
  
  # Create the zone
  ns_json=$(printf '"%s",' "${NAMESERVERS[@]}" | sed 's/,$//')  # Convert nameservers array to JSON format
  curl -s -X POST \
    -H "X-API-Key: $PDNS_API_KEY" \
    -H "Content-Type: application/json" \
    -d '{
          "name": "'"$PDNS_ZONE_ID"'",
          "kind": "Master",
          "masters": [],
          "nameservers": ['"$ns_json"']
        }' \
    "$PDNS_API_URL/api/v1/servers/localhost/zones" > /tmp/create_zone_http-respcode.txt
  echo "Zone $PDNS_ZONE_ID created successfully."
else
  echo "Zone $PDNS_ZONE_ID already exists."
fi

}

pdns_payload_generate_ptr() {
  source tmp/ip-var.txt
  cat payload-templates/$PTR_TEMPLATE | sed -e 's|ip_arpa|'"$ip_arpa"'|g' -e 's|rdns_entry|'"$rdns_entry"'|g' > tmp/curlPayloadPTRrecord.json
}

#pdns_payload_generate_a() {
#  source tmp/ip-var.txt
#  cat payload-templates/$A_RECORD_TEMPLATE | sed -e 's|a_record|'"$rdns_entry"'|g' -e 's|ip_address|'"$ip_address"'|g' > tmp/curlPayloadARecord.json

#}


pdns_payload_generate_a() {
  source tmp/ip-var.txt
  cat payload-templates/$A_RECORD_TEMPLATE | sed -e 's|a_record|'"$rdns_entry"'|g' -e 's|ip_address|'"$ip_address"'|g' > tmp/curlPayloadARecord.json

}

pdns_curl_ptr() {
    local payload_file=$1
    curl -s -S \
         -o /dev/null \
         -w '%{http_code}' \
         -H "X-API-Key: $PDNS_API_KEY" \
         -H "Content-Type: application/json" \
         -d @"$payload_file" \
         -X PATCH $PDNS_API_URL/api/v1/servers/localhost/zones/$PDNS_ZONE_ID > /tmp/http-respcode.txt
}


pdns_curl_a() {
    local payload_file=$1
    curl -s -S \
         -o /dev/null \
         -w '%{http_code}' \
         -H "X-API-Key: $PDNS_API_KEY" \
         -H "Content-Type: application/json" \
         -d @"$payload_file" \
         -X PATCH $PDNS_API_URL/api/v1/servers/localhost/zones/$ZONE_ID > /tmp/http-respcode.txt
}

push_payload() {
  iplist="tmp/ip-list.txt"
  ips=$(cat $iplist)
  for ip in $ips
  do
    echo "$ip" | awk -F . '{print "ip_arpa="""$4"."$3"."$2"."$1".in-addr.arpa."""}' > tmp/ip-var.txt
    echo "$ip" | awk -F . '{print "rdns_entry="""$4"-"$3"-"$2"-"$1".""'"$RDNS_DOMAIN"'"""}' >> tmp/ip-var.txt
    echo "$ip" | awk -F . '{print "ip_address="""$1"."$2"."$3"."$4""}' >> tmp/ip-var.txt

    # Debug variable substitution
    echo "===================================================="
    echo "Generating PTR and A record for IP: $ip"
    #echo "PTR: $(cat tmp/ip-var.txt)"

    # Generate and push PTR record
    pdns_payload_generate_ptr
    pdns_curl_ptr tmp/curlPayloadPTRrecord.json
    http_code=$(cat /tmp/http-respcode.txt)
    if [[ $http_code -eq 204 ]]; then
      echo "Set PTR record for IP $ip successfully"
    else
      echo "Error: Response code for PTR record: $http_code"
      exit 1
    fi

    # Generate and push A record
    pdns_payload_generate_a
    pdns_curl_a tmp/curlPayloadARecord.json
    http_code=$(cat /tmp/http-respcode.txt)
    if [[ $http_code -eq 204 ]]; then
      echo "Set A record for $ip successfully"
    else
      echo "Error: Response code for A record: $http_code"
      exit 1
    fi
  done
}

GREEN='\033[0;32m'
RED='\033[0;31m'
############## End functions ##############
############# Generate IP List ############
gen_ip_list
############# Create revert zone ############

create_zone_ptr

############## Push Payload ###############
push_payload

###### Remove Temporary Directory #########
rm -rf tmp
