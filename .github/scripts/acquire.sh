#!/bin/bash

# Check if resource name, lifetime, and wait are provided as command-line arguments
if [ $# -ne 3 ]; then
  echo "Usage: $0 <resource_name> <lifetime> <wait>"
  exit 1
fi

# Set the BASE_URL for your server from the environment variable RDLM_URL
BASE_URL="$RDLM_URL"

# Set the resource name and other parameters from the command-line arguments
RESOURCE_NAME="$1"
LIFETIME="$2"
WAIT="$3"

# Prepare the lock dictionary in JSON format with provided lifetime and wait
LOCK_DICT='{
  "title": "'"$RESOURCE_NAME"'",
  "lifetime": '"$LIFETIME"',
  "wait": '"$WAIT"'
}'

# Make the POST request using curl and capture the HTTP status code
HTTP_STATUS=$(curl -o /dev/null -sw "%{http_code}" -X POST -H "Content-Type: application/json" -d "$LOCK_DICT" "$BASE_URL/locks/$RESOURCE_NAME")

# Check if the lock was acquired (HTTP status code 201) or not
if [ "$HTTP_STATUS" -eq 201 ]; then
  echo "Lock acquired"
  exit 0
else
  echo "Lock not acquired"
  exit 1
fi
