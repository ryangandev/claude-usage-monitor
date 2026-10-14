#!/bin/sh
# Stop the monitor and remove its launchd agent. The data in state.db stays.
set -eu
LABEL="com.ryangan.claude-usage-monitor"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
echo "Stopped and removed $LABEL"
