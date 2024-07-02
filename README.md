# KZones

<img align="right" width="125" height="75" src="./media/icon.png">

KDE KWin Script for snapping windows into zones. Handy when using a (super) ultrawide monitor, an alternative to PowerToys FancyZones and Windows 11 snap layouts.

## Features

### Zone Selector

The zone selector is a small widget that appears when you drag a window to the top of the screen. It allows you to snap the window to a zone regardless of the current layout.

![](./media/selector.gif)

### Zone Overlay

The zone overlay is a fullscreen overlay that appears when you move a window. It shows all zones from the current layout and the window will snap to the zone you drop it on.

![](./media/dragdrop.gif)

### Multiple Layouts

Create multiple layouts and cycle between them.

![](./media/layouts.gif)

### Shortcuts

KZones comes with a set of shortcuts to move your windows between zones and layouts.

![](./media/shortcuts.gif)

### Theming

By using the same colors as your selected color scheme, KZones will blend in perfectly with your desktop.

![](./media/theming.png)

## Installation

To install KZones you can either use the built-in script manager or clone the repo and build it yourself.

### KWin Script Manager

Navigate to `System Settings / Window Management / KWin Scripts / Get New…` and search for KZones.  

Depending on your Plasma version, one of these packages will be downloaded and installed:

- [KZones](https://store.kde.org/p/1909220)
- [KZones for Plasma 5](https://store.kde.org/p/2143914)

### Build it yourself

Make sure you have "zip" installed on your system before building.

```sh
git clone https://github.com/gerritdevriese/kzones
cd kzones && make
```

## Configuration

### General

#### Zone Selector

The zone selector is a small widget that appears when you drag a window to the top of the screen. It allows you to snap the window to a zone regardless of the current layout.

- Enable or disable the zone selector.
- Set the distance from the top of the screen at which the zone selector will start to appear.

#### Zone Overlay

The zone overlay is a fullscreen overlay that appears when you move a window. It shows all zones from the current layout and the window will snap to the zone you drop it on.

- Enable or disable the zone overlay.
- Choose whether the overlay should be shown when you start moving a window or when you press the toggle overlay shortcut.
- Choose where the cursor needs to be in order to highlight a zone, either in the center of the zone or anywhere inside the zone.

#### Remember and restore window geometries

The script will remember the geometry of each window when it's moved to a zone. When the window is moved out of the zone, it will be restored to it's original geometry.

- Enable or disable this behavior.

### Layouts

You can define your own layouts by modifying the JSON in the **Layouts** tab in the script settings, here are some examples to get you started:

#### Examples

<details open>
  <summary>Single layout</summary>

```json
[
    {
        "name": "Layout 1",
        "padding": 10,
        "zones": [
            {
                "name": "1",
                "x": 0,
                "y": 0,
                "height": 100,
                "width": 25
            },
            {
                "name": "2",
                "x": 25,
                "y": 0,
                "height": 100,
                "width": 50
            },
            {
                "name": "3",
                "x": 75,
                "y": 0,
                "height": 100,
                "width": 25
            }
        ]
    }
]
```

</details>

<details>
  <summary>Multiple layouts</summary>

```json
[
    {
        "name": "Layout 1",
        "padding": 0,
        "zones": [
            {
                "name": "1",
                "x": 0,
                "y": 0,
                "height": 100,
                "width": 25
            },
            {
                "name": "2",
                "x": 25,
                "y": 0,
                "height": 100,
                "width": 50
            },
            {
                "name": "3",
                "x": 75,
                "y": 0,
                "height": 100,
                "width": 25
            }
        ]
    },
    {
        "name": "Layout 2",
        "padding": 0,
        "zones": [
            {
                "name": "1",
                "x": 0,
                "y": 0,
                "height": 50,
                "width": 25
            },
            {
                "name": "2",
                "x": 0,
                "y": 50,
                "height": 50,
                "width": 25
            },
            {
                "name": "3",
                "x": 25,
                "y": 0,
                "height": 100,
                "width": 50
            },
            {
                "name": "4",
                "x": 75,
                "y": 0,
                "height": 50,
                "width": 25
            },
            {
                "name": "5",
                "x": 75,
                "y": 50,
                "height": 50,
                "width": 25
            }
        ]
    }
]
```

</details>

#### Explanation

The main array can contain as many layouts as you want:

Each **layout** object needs the following keys:

- `name`: The name of the layout, shown when cycling between layouts
- `padding`: The amount of space between the window and the zone in pixels
- `zones`: An array containing all zone objects for this layout

Each **zone** object needs the following keys:

- `x`, `y`: position of the top left corner of the zone in screen percentage
- `width`, `height`: size of the zone in screen percentage

### Filters

Stop certain windows from snapping to zones by adding them to the filter list.

- Select the filter mode, either **Include** or **Exclude**.
- Add window classes to the list seperated by a newline.

You can enable debug mode to see the window class of the active window.

### Advanced

#### Polling rate

The polling rate is the amount of time between each zone check when dragging a window. The default is 100ms, a faster polling rate is more accurate but will use more CPU. You can change this to your liking.

#### Debug mode

When debug mode is enabled, the script will log more information and show extra information in the overlay.

## Shortcuts

List of all available shortcuts:

| Shortcut                                                           | Default Binding  |
| ------------------------------------------------------------------ | ---------------- |
| Move active window to zone                                         | `Ctrl+Alt+[0-9]` |
| Move active window to previous zone                                | `Ctrl+Alt+Left`  |
| Move active window to next zone                                    | `Ctrl+Alt+Right` |
| Switch to previous window in current zone                          | `Ctrl+Alt+Down`  |
| Switch to next window in current zone                              | `Ctrl+Alt+Up`    |
| Cycle between layouts                                              | `Ctrl+Alt+D`     |
| Toggle zone overlay                                                | `Ctrl+Alt+C`     |

*To change the default bindings, go to `System Settings / Shortcuts` and search for KZones*

## Troubleshooting

### The script doesn't work

Check if your KDE Plasma version is at 6 or higher (for older versions, check the releases)  
Make sure there is at least one layout defined in the script settings and that it contains at least one zone.

### My settings are not saved

After changing settings, reload the script by disabling, saving and enabling it again.  
This is a known issue with the KWin Scripting API

### The screen turns black while moving a window

If you are using X11 make sure your compositor is enabled, as it is needed to draw transparent windows.  
You can find this setting in `System Settings / Display and Monitor / Compositor`

### Auto-update broke KZones on Plasma 5

Due to API changes in KWin 6, the newer versions of the script are not backwards compatible with Plasma 5.  
If you were already subscribed to KZones using the script manager and updated to the latest version by accident, you will need to uninstall the script and subscribe to "KZones for Plasma 5" instead.
