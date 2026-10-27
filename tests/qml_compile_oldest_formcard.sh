#!/usr/bin/env bash
# Compile every QML file against the FormCard QML of the oldest Kirigami Addons we support
# (Debian 13 ships 1.7, Debian 14 1.12). A property or handler that only newer FormCard delegates
# have fails a whole settings page there (it showed up blank). Downloads the FormCard sources from
# KDE's GitLab.
set -euo pipefail

VERSION="${KIRIGAMI_ADDONS_VERSION:-v1.7.0}"
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
MODULE="$WORK/org/kde/kirigamiaddons/formcard"
mkdir -p "$MODULE/private"

API="https://invent.kde.org/api/v4/projects/libraries%2Fkirigami-addons/repository/tree"
RAW="https://invent.kde.org/libraries/kirigami-addons/-/raw/$VERSION"
for dir in src/formcard src/formcard/private; do
	curl -sSf "$API?path=$dir&ref=$VERSION&per_page=100" \
		| python3 -c 'import json, sys; [print(x["path"]) for x in json.load(sys.stdin) if x["type"] == "blob" and x["path"].endswith(".qml")]' \
		| while read -r path; do
			target="$MODULE/${path#src/formcard/}"
			curl -sSfL "$RAW/$path" -o "$target"
		done
done

# No C++ plugin: the QML types only, the rest of Kirigami Addons comes from the installed version.
{
	echo "module org.kde.kirigamiaddons.formcard"
	for file in "$MODULE"/*.qml; do
		name=$(basename "$file" .qml)
		echo "$name 1.0 $name.qml"
	done
} > "$MODULE/qmldir"

QML_IMPORT_PATH="$WORK${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" bash "$ROOT/tests/qml_compile.sh"
