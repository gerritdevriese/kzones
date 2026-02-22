import QtQuick
import org.kde.kirigami as Kirigami

Item {
    property var theme: {
        const brightness = Kirigami.ColorUtils.brightnessForColor(Kirigami.Theme.backgroundColor);
        return brightness === Kirigami.ColorUtils.Light ? "light" : "dark";
    }
    property var backgroundColor: {
        if (theme === "light")
            return Kirigami.ColorUtils.tintWithAlpha(Kirigami.Theme.backgroundColor, "white", 0.45);

        if (theme === "dark")
            return Kirigami.ColorUtils.tintWithAlpha(Kirigami.Theme.backgroundColor, "black", 0.3);

    }
    property var buttonColor: {
        if (theme === "light")
            return Kirigami.ColorUtils.tintWithAlpha(Kirigami.Theme.backgroundColor, "black", 0.15);

        if (theme === "dark")
            return Kirigami.ColorUtils.tintWithAlpha(Kirigami.Theme.backgroundColor, "white", 0.1);

    }
    property var accentColor: {
        return Kirigami.Theme.hoverColor;
    }
    property var textColor: {
        return Kirigami.Theme.textColor;
    }

    function getBorderColor(color) {
        if (theme === "light")
            return Kirigami.ColorUtils.tintWithAlpha(color, "black", 0.15);

        if (theme === "dark")
            return Kirigami.ColorUtils.tintWithAlpha(color, "white", 0.1);

    }

    function tintWithAlpha(color, tint, alpha) {
        return Kirigami.ColorUtils.tintWithAlpha(color, tint, alpha);
    }

    Kirigami.Theme.colorSet: Kirigami.Theme.View
}
