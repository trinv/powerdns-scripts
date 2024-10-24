#!/bin/bash

API_KEY="d367bce2-9bf3-49e6-b8a3-ea395a5e2865"
PDNS_SERVER="http://127.0.0.1:8081"
ZONE_NAME="23.34.45.in-addr.arpa."
NAMESERVERS=("ns1.example.com." "ns2.example.com.")

# Check if the zone exists
response=$(curl -s -o /dev/null -w "%{http_code}" -X GET \
  -H "X-API-Key: $API_KEY" \
  -H "Content-Type: application/json" \
  "$PDNS_SERVER/api/v1/servers/localhost/zones/$ZONE_NAME")

if [ "$response" -eq 404 ]; then
  echo "Zone does not exist. Creating zone..."
  
  # Create the zone
  ns_json=$(printf '"%s",' "${NAMESERVERS[@]}" | sed 's/,$//')  # Convert nameservers array to JSON format
  curl -s -X POST \
    -H "X-API-Key: $API_KEY" \
    -H "Content-Type: application/json" \
    -d '{
          "name": "'"$ZONE_NAME"'",
          "kind": "Master",
          "masters": [],
          "nameservers": ['"$ns_json"']
        }' \
    "$PDNS_SERVER/api/v1/servers/localhost/zones" > /tmp/create_zone_http-respcode.txt
  echo "Zone $ZONE_NAME created successfully."
else
  echo "Zone $ZONE_NAME already exists."
fi
