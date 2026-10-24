import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page

    property alias cfg_iconSize: iconSize.value
    property alias cfg_maxZoom: maxZoom.value
    property alias cfg_influence: influence.value
    property alias cfg_iconSpacing: iconSpacing.value
    property alias cfg_showLabels: showLabels.checked
    property alias cfg_showPreviews: showPreviews.checked
    property alias cfg_ownBackground: ownBackground.checked
    property alias cfg_groupWindows: groupWindows.checked

    QQC2.SpinBox {
        id: iconSize
        Kirigami.FormData.label: i18n("Icon size:")
        from: 16
        to: 128
        stepSize: 2
    }

    RowLayout {
        Kirigami.FormData.label: i18n("Magnification:")
        QQC2.Slider {
            id: maxZoom
            from: 100
            to: 300
            stepSize: 5
            Layout.preferredWidth: Kirigami.Units.gridUnit * 12
        }
        QQC2.Label {
            text: (maxZoom.value / 100).toFixed(2) + "x"
        }
    }

    RowLayout {
        Kirigami.FormData.label: i18n("Spread:")
        QQC2.Slider {
            id: influence
            from: 100
            to: 600
            stepSize: 10
            Layout.preferredWidth: Kirigami.Units.gridUnit * 12
        }
        QQC2.Label {
            text: i18n("%1 icons", (influence.value / 100).toFixed(1))
        }
    }

    QQC2.Label {
        text: i18n("How many neighbouring icons ripple with the cursor.")
        font: Kirigami.Theme.smallFont
        opacity: 0.7
    }

    Item { Kirigami.FormData.isSection: true }

    QQC2.SpinBox {
        id: iconSpacing
        Kirigami.FormData.label: i18n("Spacing:")
        from: 0
        to: 40
    }

    QQC2.CheckBox {
        id: showLabels
        Kirigami.FormData.label: i18n("Labels:")
        text: i18n("Show app name above the magnified icon")
    }

    QQC2.CheckBox {
        id: showPreviews
        Kirigami.FormData.label: i18n("Previews:")
        text: i18n("Live window previews on hover")
    }

    QQC2.CheckBox {
        id: groupWindows
        Kirigami.FormData.label: i18n("Grouping:")
        text: i18n("Group windows of the same application")
    }

    Item { Kirigami.FormData.isSection: true }

    QQC2.CheckBox {
        id: ownBackground
        Kirigami.FormData.label: i18n("Dock bar:")
        text: i18n("Draw the dock bar and hide the panel's own background")
    }

    QQC2.Label {
        text: i18n("Required for icons to magnify above the bar. Turning this off\nreturns the panel's native background and clips the effect.")
        font: Kirigami.Theme.smallFont
        opacity: 0.7
    }
}
