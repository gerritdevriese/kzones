SCRIPT_NAME := kzones
PKGFILE := $(SCRIPT_NAME).kwinscript
SRC_DIR := src
SESSION_WIDTH := 1920
SESSION_HEIGHT := 1080
SESSION_OUTPUT_COUNT := 1
SESSION_VERBOSE := 0
SESSION_APPLICATIONS := # dolphin konsole kate

.NOTPARALLEL: all

.PHONY: all test build install uninstall clean enable disable start-session help

all: install clean

test: all start-session

build: $(PKGFILE)

$(PKGFILE): $(shell find $(SRC_DIR) -type f)
	@echo "Packaging $(SRC_DIR) into $(PKGFILE)..."
	@zip -rq $(PKGFILE) $(SRC_DIR)

install:
	@$(MAKE) clean
	@$(MAKE) build
	@set -eu; \
	if [ "$$(qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.isScriptLoaded $(SCRIPT_NAME))" = "true" ]; then \
		echo "Unloading running $(SCRIPT_NAME) script..."; \
		qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript $(SCRIPT_NAME) >/dev/null; \
	fi; \
	if kpackagetool6 --type=KWin/Script --show $(SCRIPT_NAME) >/dev/null 2>&1; then \
		kpackagetool6 --type=KWin/Script --upgrade $(PKGFILE); \
	else \
		kpackagetool6 --type=KWin/Script --install $(PKGFILE); \
	fi; \
	if [ "$$(kreadconfig6 --file kwinrc --group Plugins --key $(SCRIPT_NAME)Enabled)" = "true" ]; then \
		PACKAGE_PATH="$$(kpackagetool6 --type=KWin/Script --show $(SCRIPT_NAME) | sed -n 's/^[[:space:]]*Path[[:space:]]*:[[:space:]]*//p')"; \
		SCRIPT_PATH="$$PACKAGE_PATH/contents/ui/main.qml"; \
		if [ ! -f "$$SCRIPT_PATH" ]; then \
			echo "Installed script entry point not found: $$SCRIPT_PATH" >&2; \
			exit 1; \
		fi; \
		echo "Loading updated $(SCRIPT_NAME) script into KWin..."; \
		qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadDeclarativeScript "$$SCRIPT_PATH" $(SCRIPT_NAME) >/dev/null; \
		qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.start; \
		if [ "$$(qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.isScriptLoaded $(SCRIPT_NAME))" != "true" ]; then \
			echo "KWin did not load $(SCRIPT_NAME) successfully" >&2; \
			exit 1; \
		fi; \
		echo "$(SCRIPT_NAME) updated and running"; \
	else \
		echo "$(SCRIPT_NAME) installed; it is disabled in KWin settings"; \
	fi

uninstall:
	@echo "Uninstalling $(SCRIPT_NAME)..."
	@kpackagetool6 --type=KWin/Script -r $(SCRIPT_NAME)

clean:
	@echo "Cleaning up $(PKGFILE)..."
	@rm -f $(PKGFILE)

enable:
	@echo "Enabling $(SCRIPT_NAME)..."
	@kwriteconfig6 --file kwinrc --group Plugins --key $(SCRIPT_NAME)Enabled true
	@qdbus org.kde.KWin /KWin reconfigure

disable:
	@echo "Disabling $(SCRIPT_NAME)..."
	@kwriteconfig6 --file kwinrc --group Plugins --key $(SCRIPT_NAME)Enabled false
	@qdbus org.kde.KWin /KWin reconfigure

restart-kwin:
	if [ "$$XDG_SESSION_TYPE" = "x11" ]; then \
		kwin_x11 --replace & \
	elif [ "$$XDG_SESSION_TYPE" = "wayland" ]; then \
		kwin_wayland --replace & \
	else \
		echo "Unknown session type"; \
	fi

logs:
	@if [ "${XDG_SESSION_TYPE}" = "x11" ]; then \
	    journalctl -n 0 -f -t kwin_x11 | grep --line-buffered -i "KZones"; \
	else \
	    journalctl --user -n 0 -u plasma-kwin_wayland -f | grep --line-buffered -i "KZones"; \
	fi


start-session:
	@echo "Starting nested Wayland session..."
	@sh -c '\
		unset LD_PRELOAD; \
		NESTED_DIR="$$XDG_RUNTIME_DIR/nested_plasma"; \
		mkdir -p "$$NESTED_DIR"; \
		WRAPPER="$$NESTED_DIR/kwin_wayland_wrapper"; \
		printf "#!/bin/sh\n/usr/bin/kwin_wayland_wrapper --width $(SESSION_WIDTH) --height $(SESSION_HEIGHT) --no-lockscreen --output-count $(SESSION_OUTPUT_COUNT) $(SESSION_APPLICATIONS) \\\$$@\n" > "$$WRAPPER"; \
		chmod a+x "$$WRAPPER"; \
		export PATH="$$NESTED_DIR:$$PATH"; \
		if [ "$(SESSION_VERBOSE)" = "1" ]; then \
			dbus-run-session startplasma-wayland; \
		else \
			dbus-run-session startplasma-wayland 2>&1 | grep -E "qml"; \
		fi; \
		rm -f "$$WRAPPER"'

load:
	bin/load.sh "$(SRC_DIR)" "$(SCRIPT_NAME)-test"

unload:
	bin/unload.sh "$(SCRIPT_NAME)-test"

reload: unload load

help:
	@echo "Makefile commands:"
	@echo "  all            - Build and install the script (default)"
	@echo "  test           - Build, install, and start a nested session"
	@echo "  build          - Package the script into a .kwinscript file"
	@echo "  install        - Install the script"
	@echo "  uninstall      - Uninstall the script"
	@echo "  clean          - Remove the packaged .kwinscript file"
	@echo "  enable         - Enable the script in KWin"
	@echo "  disable        - Disable the script in KWin"
	@echo "  restart-kwin   - Restart KWin to apply changes"
	@echo "  logs           - View KWin logs for debugging"
	@echo "  start-session  - Start a nested Wayland session for testing"
	@echo "  load           - Load the script for testing"
	@echo "  unload         - Unload the test script"
	@echo "  reload         - Reload the test script"