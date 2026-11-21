#!/bin/sh
# Re-registers the menu-bar app with launchd so macOS accepts the newly installed version.
# Only restarting the old job makes macOS refuse the new app ("Launch Constraint Violation").
# Usage: reload-bar.sh <console uid> [delay seconds]
uid="$1"; delay="${2:-0}"
[ -n "$uid" ] && [ "$uid" != "0" ] || exit 0
sleep "$delay"
launchctl bootout "gui/$uid/com.calm.bar" 2>/dev/null
# bootout returns before the old app has fully stopped; bootstrapping too early fails silently.
for _ in 1 2 3 4 5 6 7 8 9 10; do
    launchctl print "gui/$uid/com.calm.bar" >/dev/null 2>&1 || break
    sleep 1
done
for _ in 1 2 3 4 5; do
    launchctl bootstrap "gui/$uid" /Library/LaunchAgents/com.calm.bar.plist 2>/dev/null && break
    launchctl print "gui/$uid/com.calm.bar" >/dev/null 2>&1 && break
    sleep 1
done
# When run as a one-off launchd job (after an in-app update), remove that job.
launchctl remove com.calm.bar-reload 2>/dev/null
exit 0
