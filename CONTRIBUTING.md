# Contributing

## Code Formatting

### QML

QML files should be formatted using the `qmlformat` tool.

```bash
qmlformat -i path/to/file.qml
```

## Development Resources

### API Documentation

- [KDE Frameworks API reference](https://api.kde.org/)
- [Kirigami style colors](https://develop.kde.org/docs/getting-started/kirigami/style-colors/)
- [KWin scripting API](https://develop.kde.org/docs/plasma/kwin/api/)

### Examples and source code

- [Example KWin scripts](https://invent.kde.org/plasma/kwin/-/tree/master/src/plugins)
- [KWin scripting API source code](https://invent.kde.org/plasma/kwin/-/tree/master/src/scripting)

## KWin debugging

Script configurations are saved inside: `~/.config/kwinrc`

Live script code is stored here: `~/.local/share/kwin/scripts`

Run nested kwin: `dbus-run-session startplasma-wayland`

## Tips

- You can edit the configuration UI (`src/contents/ui/config.ui`) using [Qt Widgets Designer](https://doc.qt.io/qt-6/qtdesigner-manual.html), which is part of the Qt development tools.
- The makefile contains some handy commands to test and run the script, either by loading it directly or in a nested Plasma session.
