#!/bin/sh
# Holt neue Versionen von ForeverPlus automatisch (macOS): ein Hintergrundauftrag
# fuehrt alle 30 Sekunden "git pull --ff-only" im Addon-Ordner aus. Danach genuegt /rl im Spiel.
#
#   sh tools/autopull.sh install     einrichten (einmalig, im Addon-Ordner ausfuehren)
#   sh tools/autopull.sh status      zeigt, ob der Auftrag laeuft, und die letzten Zeilen des Protokolls
#   sh tools/autopull.sh uninstall   entfernt den Auftrag
#
# "--ff-only" aendert nie lokale Aenderungen: gibt es welche, die in Konflikt stehen, bricht der Pull ab
# (Meldung im Protokoll) und es passiert sonst nichts.
set -eu

DIR="$(cd "$(dirname "$0")/.." && pwd)"
LABEL="com.foreverplus.autopull"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/ForeverPlus-autopull.log"
BRANCH="${FP_BRANCH:-main}"

case "${1:-}" in
install)
	[ -d "$DIR/.git" ] || { echo "Kein Git-Ordner: $DIR"; exit 1; }
	mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
	cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key><string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>/bin/sh</string>
		<string>-c</string>
		<string>cd "$DIR" &amp;&amp; /usr/bin/git pull --ff-only --quiet origin $BRANCH</string>
	</array>
	<key>StartInterval</key><integer>30</integer>
	<key>RunAtLoad</key><true/>
	<key>StandardOutPath</key><string>$LOG</string>
	<key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
EOF
	launchctl unload "$PLIST" 2>/dev/null || true
	launchctl load "$PLIST"
	echo "Eingerichtet: alle 30 s wird $BRANCH in $DIR geholt. Protokoll: $LOG"
	;;
uninstall)
	launchctl unload "$PLIST" 2>/dev/null || true
	rm -f "$PLIST"
	echo "Entfernt."
	;;
status)
	if launchctl list | grep -q "$LABEL"; then echo "Laeuft ($LABEL)."; else echo "Nicht eingerichtet."; fi
	[ -f "$LOG" ] && tail -n 5 "$LOG" || true
	;;
*)
	echo "Aufruf: sh tools/autopull.sh install | status | uninstall"
	exit 1
	;;
esac
