SCRIPT_NAME := kzones
PKGFILE := $(SCRIPT_NAME).kwinscript
SRC_DIR := src
SESSION_WIDTH := 1920
SESSION_HEIGHT := 1080
SESSION_OUTPUT_COUNT := 1

.NOTPARALLEL: all

.PHONY: all test build install uninstall clean enable disable start-session

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

start-session:
	@echo "Starting nested Wayland session..."
	@sh -c '\
		unset LD_PRELOAD; \
		NESTED_DIR="$$XDG_RUNTIME_DIR/nested_plasma"; \
		mkdir -p "$$NESTED_DIR"; \
		WRAPPER="$$NESTED_DIR/kwin_wayland_wrapper"; \
		printf "#!/bin/sh\n/usr/bin/kwin_wayland_wrapper --width $(SESSION_WIDTH) --height $(SESSION_HEIGHT) --no-lockscreen --output-count $(SESSION_OUTPUT_COUNT) \\\$$@\n" > "$$WRAPPER"; \
		chmod a+x "$$WRAPPER"; \
		export PATH="$$NESTED_DIR:$$PATH"; \
		dbus-run-session startplasma-wayland; \
		rm -f "$$WRAPPER"'
