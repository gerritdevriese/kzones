#!/bin/sh

set -eu

SCRIPT_NAME="${1-}"

usage() {
    echo "Usage: $(basename "$0") <script_name>" >&2
    exit 1
}

[ -n "${SCRIPT_NAME}" ] || usage

BUS_DEST="org.kde.KWin"
BUS_PATH="/Scripting"
BUS_IFACE="org.kde.kwin.Scripting"

_invoke() {
    method="$1"; shift 1
    dbus-send --session --print-reply=literal \
        --dest="${BUS_DEST}" "${BUS_PATH}" "${BUS_IFACE}.${method}" "$@"
}

is_loaded() {
    _invoke isScriptLoaded string:"${SCRIPT_NAME}" | awk '{ print $2 }'
}

unload() {
    _invoke unloadScript string:"${SCRIPT_NAME}" > /dev/null
}

if [ "$(is_loaded)" = "false" ]; then
    echo "Script not loaded: ${SCRIPT_NAME}" >&2
    exit 0
fi

echo "Unloading script: ${SCRIPT_NAME}"
unload

if [ "$(is_loaded)" = "false" ]; then
    echo "Script unloaded successfully"
    exit 0
fi

echo "$(basename "$0"): Failed to unload script: ${SCRIPT_NAME}" >&2
exit 1
