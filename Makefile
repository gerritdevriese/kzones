NAME=kzones
PKGFILE = $(NAME).kwinscript
PKGDIR = pkg

.NOTPARALLEL: all

all: build install clean reload enable

build: $(PKGDIR)
	cp -rf src/metadata.json $(PKGDIR)/
	cp -rf src/contents/* $(PKGDIR)/contents/
	zip -r $(PKGFILE) $(PKGDIR)

install:
	kpackagetool6 --type=KWin/Script -i $(PKGFILE) || kpackagetool6 --type=KWin/Script -u $(PKGFILE)

clean:
	rm -r $(PKGDIR)
	rm $(PKGFILE)

reload:
	if [ "$$XDG_SESSION_TYPE" = "x11" ]; then \
		kwin_x11 --replace & disown; \
	elif [ "$$XDG_SESSION_TYPE" = "wayland" ]; then \
		kwin_wayland --replace & disown; \
	else \
		echo "Unknown session type"; \
	fi

enable:
	kwriteconfig6 --file kwinrc --group Plugins --key $(NAME)Enabled true
	qdbus org.kde.KWin /KWin reconfigure

$(PKGDIR):
	mkdir -p $(PKGDIR)
	mkdir -p $(PKGDIR)/contents/code
	mkdir $(PKGDIR)/contents/config
	mkdir $(PKGDIR)/contents/ui
