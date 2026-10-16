#!/usr/bin/env bash
# Compile every QML file under package/contents/ui with the installed Qt / KDE QML modules.
# Needs qml6 (or qml), Kirigami, Kirigami Addons, Plasma (workspace, nm, plasma5support),
# KNotifications, KCMUtils, KSvg, Qt5Compat and the qqc2-desktop-style.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
UI="$ROOT/package/contents/ui"
QML_BIN=$(command -v qml6 || command -v qml || true)
if [ -z "$QML_BIN" ]; then
	echo "qml6 not found" >&2
	exit 1
fi

mapfile -t FILES < <(cd "$UI" && find . -name '*.qml' | sed 's|^\./||' | sort)

export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-offscreen}"
export QT_QUICK_CONTROLS_STYLE="${QT_QUICK_CONTROLS_STYLE:-org.kde.desktop}"
export QT_FORCE_STDERR_LOGGING=1 # Otherwise console.log may go to the journal

LOG=$(mktemp)
trap 'rm -f "$LOG"' EXIT
status=0
timeout 300 "$QML_BIN" "$ROOT/tests/qml_compile.qml" -- "file://$UI/" "${FILES[@]}" >"$LOG" 2>&1 || status=$?
grep -E "^(qml: )?(ERROR|compiled)" "$LOG" || true
if [ "$status" -ne 0 ]; then
	echo "QML compile check failed (exit $status). Full log:" >&2
	cat "$LOG" >&2
fi
exit "$status"
