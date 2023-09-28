#!/bin/bash

# Check if a resource name is provided as a command-line argument
if [ $# -ne 1 ]; then
  echo "Usage: $0 <resource_name>"
  exit 1
fi

# Set the BASE_URL for your server from the environment variable RDLM_URL
BASE_URL="$RDLM_URL"

# Set the resource name from the command-line argument
RESOURCE_NAME="$1"

# Get the response JSON from the URL using curl and extract the LOCK_URL using jq
LOCK_RESPONSE=$(curl -X GET -s "$BASE_URL/resources/$RESOURCE_NAME")
LOCK_URL=$(echo "$LOCK_RESPONSE" | jq -r '._embedded.locks[0]._links.self.href')

# Check if lock URL is empty or null
if [ -z "$LOCK_URL" ] || [ "$LOCK_URL" == "null" ]; then
  echo "No lock found for resource $RESOURCE_NAME"
  exit 0
fi

# Release the lock using curl and capture the HTTP status code
HTTP_STATUS=$(curl -o /dev/null -sw "%{http_code}" -X DELETE "$BASE_URL$LOCK_URL")

# Check if the lock was released (HTTP status code 204) or not
if [ "$HTTP_STATUS" -eq 204 ]; then
  echo "Lock released"
  exit 0
else
  echo "Lock not released | Error Code : $HTTP_STATUS"
  exit 1
fi

