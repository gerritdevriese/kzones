import QtQuick
import org.kde.kirigami as Kirigami

Item {

    Kirigami.Theme.colorSet: Kirigami.Theme.View

    property var theme: {
        const brightness = Kirigami.ColorUtils.brightnessForColor(Kirigami.Theme.backgroundColor);
        return brightness === Kirigami.ColorUtils.Light ? "light" : "dark";
    }

    function getBorderColor(color) {
        if (theme === "light") return Kirigami.ColorUtils.tintWithAlpha(color, "black", 0.15)
        if (theme === "dark") return Kirigami.ColorUtils.tintWithAlpha(color, "white", 0.10)
    }

    function tintWithAlpha(color, tint, alpha) {
        return Kirigami.ColorUtils.tintWithAlpha(color, tint, alpha)
    }

    property var backgroundColor: {
        if (theme === "light") return Kirigami.ColorUtils.tintWithAlpha( Kirigami.Theme.backgroundColor, "white", 0.45)
        if (theme === "dark") return Kirigami.ColorUtils.tintWithAlpha( Kirigami.Theme.backgroundColor, "black", 0.30)
    }

    property var buttonColor: {
         if (theme === "light") return Kirigami.ColorUtils.tintWithAlpha( Kirigami.Theme.backgroundColor, "black", 0.15)
         if (theme=== "dark") return Kirigami.ColorUtils.tintWithAlpha( Kirigami.Theme.backgroundColor, "white", 0.10)
    }

    property var accentColor: {
        return Kirigami.Theme.hoverColor
    }

    property var textColor: {
        return Kirigami.Theme.textColor
    }
}

