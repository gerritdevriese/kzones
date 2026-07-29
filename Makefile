SCRIPT_NAME := kzones
PKGFILE := $(SCRIPT_NAME).kwinscript
SRC_DIR := src
EDITOR_SOURCE := tools/kzones-layout-editor.py
EDITOR_NAME := kzones-layout-editor
LOCAL_BIN := $(HOME)/.local/bin
LOCAL_APPLICATIONS := $(HOME)/.local/share/applications
SESSION_WIDTH := 1920
SESSION_HEIGHT := 1080
SESSION_OUTPUT_COUNT := 1
SESSION_VERBOSE := 0
SESSION_APPLICATIONS := # dolphin konsole kate

.NOTPARALLEL: all

.PHONY: all test build install install-editor editor check-editor uninstall clean enable disable start-session help

all: install clean

test: all start-session

build: $(PKGFILE)

$(PKGFILE): $(shell find $(SRC_DIR) -type f)
	@echo "Packaging $(SRC_DIR) into $(PKGFILE)..."
	@zip -rq $(PKGFILE) $(SRC_DIR)

install: build
	@echo "Installing $(PKGFILE)..."
	@kpackagetool6 --type=KWin/Script -i $(PKGFILE) || \
	kpackagetool6 --type=KWin/Script -u $(PKGFILE)
	@$(MAKE) --no-print-directory install-editor

install-editor:
	@echo "Installing KZones Layout Editor..."
	@install -Dm755 $(EDITOR_SOURCE) $(LOCAL_BIN)/$(EDITOR_NAME)
	@install -Dm644 resources/kzones-layout-editor.desktop $(LOCAL_APPLICATIONS)/kzones-layout-editor.desktop
	@update-desktop-database $(LOCAL_APPLICATIONS) 2>/dev/null || true

editor: install-editor
	@$(LOCAL_BIN)/$(EDITOR_NAME)

check-editor:
	@python3 -m py_compile $(EDITOR_SOURCE)

uninstall:
	@echo "Uninstalling $(SCRIPT_NAME)..."
	@kpackagetool6 --type=KWin/Script -r $(SCRIPT_NAME)
	@rm -f $(LOCAL_BIN)/$(EDITOR_NAME) $(LOCAL_APPLICATIONS)/kzones-layout-editor.desktop
	@update-desktop-database $(LOCAL_APPLICATIONS) 2>/dev/null || true

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
	    journalctl -f -t kwin_x11; \
	else \
	    journalctl --user -u plasma-kwin_wayland -f QT_CATEGORY=js QT_CATEGORY=qml QT_CATEGORY=kwin_scripting; \
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
	@echo "  install-editor - Install the visual layout editor and launcher"
	@echo "  editor         - Install and launch the visual layout editor"
	@echo "  check-editor   - Check the visual editor Python syntax"
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
