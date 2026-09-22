#!/bin/sh
set -eu

# Builds the app bundle and launches it in demo mode (fake data, no network).
#
#   sh Scripts/demo.sh                      # launch demo
#   JIRA_TRACKER_SCREENSHOT=/tmp/pop.png \
#     sh Scripts/demo.sh                    # capture the popover to /tmp/pop.png

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
APP_BIN="$ROOT_DIR/dist/GitHub Jira Tracker.app/Contents/MacOS/GitHubJiraSystemTray"

sh "$ROOT_DIR/Scripts/build-app.sh"

pkill -f GitHubJiraSystemTray 2>/dev/null || true
sleep 1

JIRA_TRACKER_DEMO=1 "$APP_BIN"
