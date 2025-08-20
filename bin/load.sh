#!/bin/sh

set -eu

SRC_DIR="${1-}"
SCRIPT_NAME="${2-}"

usage() {
	echo "Usage: $(basename "$0") <source_dir> <script_name>" >&2
	exit 1
}

[ -n "${SRC_DIR}" ] && [ -n "${SCRIPT_NAME}" ] || usage

if [ ! -d "${SRC_DIR}" ]; then
	echo "$(basename "$0"): Source directory does not exist: ${SRC_DIR}" >&2
	exit 1
fi

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

SRC_DIR_REAL="$(realpath "${SRC_DIR}")"
TEMP_DIR="$(mktemp -d ./src.XXXXXX)"
trap 'rm -rf "${TEMP_DIR}"' EXIT INT TERM
cp -a "${SRC_DIR_REAL}"/. "${TEMP_DIR}"/

MAIN_QML_REL="contents/ui/main.qml"
MAIN_QML_PATH="${TEMP_DIR}/${MAIN_QML_REL}"

if [ "$(is_loaded)" != "false" ]; then
	echo "$(basename "$0"): Script already loaded: ${SCRIPT_NAME}" >&2
	exit 1
fi

if [ ! -f "${MAIN_QML_PATH}" ]; then
	echo "$(basename "$0"): File does not exist: ${MAIN_QML_PATH}" >&2
	exit 1
fi

MAIN_QML_PATH_ABS="$(realpath "${MAIN_QML_PATH}")"
echo "Loading script: ${MAIN_QML_PATH_ABS}, ${SCRIPT_NAME}"
_invoke loadDeclarativeScript string:"${MAIN_QML_PATH_ABS}" string:"${SCRIPT_NAME}" > /dev/null
echo "Script loaded successfully"
_invoke start
echo "Script started successfully"

if [ "$(is_loaded)" = "false" ]; then
	echo "$(basename "$0"): Failed to load script: ${MAIN_QML_PATH_ABS}, ${SCRIPT_NAME}" >&2
	exit 1
fi

exit 0