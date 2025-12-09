#!/bin/sh

# rclone-fail-handler.sh
# 
# This script is called by the rclone-fail.service.
# It stops the rclone.timer to prevent further scheduled runs, inspects recent logs for known failure patterns,
# and attempts automated recovery steps such as running a resync or restarting services.
# If recovery is successful, it restarts the timer/service; otherwise, it provides instructions for manual intervention.

# Function to restart the rclone.timer and service using the rclone4gdrive helper script.
restart_services() {
  echo "Restarting rclone.timer and service via rclone4gdrive..."
  `dirname "$0"`/rclone4gdrive restart || {
    echo "Failed to restart rclone.timer/service automatically. Please run manually."
    exit 1
  }
  echo "Timer and service restarted."
  exit 0
}

# Stop the timer immediately to avoid further scheduled runs while we handle the failure.
systemctl --user stop rclone.timer || true

# Collect recent journal lines for the rclone service (last 10 lines).
JOURNAL_OUTPUT=`journalctl --user -u rclone.service -n 10 --no-pager 2>/dev/null || true`

# --- OAuth/token error handling block ---
if echo "$JOURNAL_OUTPUT" | grep -E -q "couldn't fetch token|invalid_grant|Token has been expired or revoked|couldn't find root directory ID"; then
  echo "Detected invalid token in logs. Attempting refresh..."
  if `dirname "$0"`/refresh_token.sh; then
    restart_services
  else
    echo "refresh token failed."
  fi
fi

# Check for the "Must run --resync to recover." error in the logs.
if echo "$JOURNAL_OUTPUT" | grep -q "Must run --resync to recover."; then
  echo "Detected 'Must run --resync to recover.' in logs. Attempting resync..."
  # Attempt to recover by running rclone with --resync.
  if /usr/bin/rclone bisync gdrive: "$HOME/gdrive/" --resync --min-size 0 --log-level=ERROR; then
    restart_services
  else
    echo "rclone --resync failed."
  fi
else
  # No known recoverable error found; inform the user and exit.
  echo "No OAuth/token error or resync required detected in recent logs. Timer has been stopped as part of failure handling."
  exit 0
fi
