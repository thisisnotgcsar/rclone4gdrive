#!/usr/bin/env bash

# refresh_token.sh
#
# Purpose: Refresh the Google Drive OAuth access token in rclone.conf using the stored refresh token.
# This script is intended to be called manually or by automation when the rclone token is expired or near expiry.
# It extracts credentials from rclone.conf, requests a new access token, updates the config, and verifies the result using rclone4gdrive.

# --- CONFIG ---
REMOTE="gdrive"
RCLONE_CONF="${HOME}/.config/rclone/rclone.conf"

# --- EXTRACT VALUES FROM rclone.conf ---
# Extract client_id from the config file
CLIENT_ID=$(awk -F= '$1 ~ /client_id/ {gsub(/[ \t]/, "", $2); print $2; exit}' "$RCLONE_CONF")
# Extract client_secret from the config file
CLIENT_SECRET=$(awk -F= '$1 ~ /client_secret/ {gsub(/[ \t]/, "", $2); print $2; exit}' "$RCLONE_CONF")
# Extract refresh_token from the token JSON in the config file
REFRESH_TOKEN=$(awk -F= '$1 ~ /token/ {print $2; exit}' "$RCLONE_CONF" | jq -r '.refresh_token')

# --- CHECK ---
# Ensure all required credentials were extracted
if [[ -z "$CLIENT_ID" || -z "$CLIENT_SECRET" || -z "$REFRESH_TOKEN" ]]; then
  echo "Error: Failed to extract OAuth credentials from rclone.conf"
  exit 1
fi

# --- REQUEST NEW ACCESS TOKEN ---
# Request a new access token from Google's OAuth2 endpoint
TOKEN=$(curl -s \
  -d client_id="$CLIENT_ID" \
  -d client_secret="$CLIENT_SECRET" \
  -d refresh_token="$REFRESH_TOKEN" \
  -d grant_type=refresh_token \
  https://oauth2.googleapis.com/token)

# Extract access_token and expiry from the response
ACCESS_TOKEN=$(echo "$TOKEN" | jq -r '.access_token')
EXPIRY=$(echo "$TOKEN" | jq -r '.expires_in')

# --- CHECK ---
# Ensure the access token and expiry were obtained
if [[ -z "$ACCESS_TOKEN" || -z "$EXPIRY" ]]; then
  echo "Error: Failed to obtain access token or expiry from OAuth response"
  exit 1
fi

# --- BUILD EXPIRY STRING IN RCLONE FORMAT ---
# Calculate expiry in seconds since epoch (now + 3600)
EXPIRY_EPOCH=$(($(date +%s) + 3600))
# Format expiry as ISO 8601 with fractional seconds and local timezone
EXPIRY=$(date --date="@$EXPIRY_EPOCH" +"%Y-%m-%dT%H:%M:%S.%N%:z")

# --- BUILD JSON FOR RCLONE TOKEN FIELD ---
# Construct the new token JSON for rclone.conf
NEW_TOKEN=$(jq -nc \
  --arg at "$ACCESS_TOKEN" \
  --arg rt "$REFRESH_TOKEN" \
  --arg exp "$EXPIRY" \
  '{"access_token": $at,"token_type": "Bearer","refresh_token": $rt,"expiry": $exp}')

# --- BACKUP CONFIG ---
# Backup the current rclone.conf before making changes
cp "$RCLONE_CONF" "$RCLONE_CONF.bak" || {
  echo "Error: Failed to create backup of rclone.conf"
  exit 1
}

# --- UPDATE TOKEN IN RCLONE CONFIG ---
# Replace the token line in the remote section with the new token JSON
sed -i "/^\[${REMOTE}\]/,/^\[/ s|^token =.*|token = ${NEW_TOKEN}|" "$RCLONE_CONF" || {
  echo "Error: Failed to update token in rclone.conf"
  mv "$RCLONE_CONF.bak" "$RCLONE_CONF"
  exit 1
}

# --- TEST CONFIG WITH DRY-RUN ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Run a dry-run sync to verify the new token works
if "$SCRIPT_DIR/rclone4gdrive" dry-run; then
  echo "Dry-run succeeded. Configuration updated."
  rm -f "$RCLONE_CONF.bak"
else
  echo "Dry-run failed! Restoring previous configuration."
  mv "$RCLONE_CONF.bak" "$RCLONE_CONF"
  exit 1
fi