pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import org.kde.kirigami.layouts as KirigamiLayouts
import "Weather.js" as Wx

KirigamiLayouts.FormLayout {
    id: form
    anchors.fill: parent

    property alias  cfg_zip: zipField.text
    property alias  cfg_metric: metricBox.checked
    // Written by the ZIP lookup rather than typed directly — a coordinate pair
    // is not something anyone should have to enter by hand.
    property alias  cfg_placeLabel: form.placeKey
    property alias  cfg_latitude: form.latKey
    property alias  cfg_longitude: form.lonKey

    property string placeKey: plasmoid.configuration.placeLabel
    property real   latKey: plasmoid.configuration.latitude
    property real   lonKey: plasmoid.configuration.longitude
    property string lookupState: ""
    property string lastResolvedZip: plasmoid.configuration.zip

    RowLayout {
        KirigamiLayouts.FormData.label: i18n("US ZIP code")
        QC.TextField {
            id: zipField
            text: plasmoid.configuration.zip
            inputMethodHints: Qt.ImhDigitsOnly
            maximumLength: 5
            Layout.preferredWidth: 100
            placeholderText: "10001"
            onTextChanged: zipDebounce.restart()
            onAccepted: form.lookupZip()
        }
        QC.Button {
            text: i18n("Look up")
            onClicked: form.lookupZip()
        }
        QC.Label {
            text: form.lookupState
            opacity: 0.75
        }
    }

    QC.Label {
        KirigamiLayouts.FormData.label: i18n("Resolved")
        text: form.placeKey + "   (" + form.latKey.toFixed(4) + ", " + form.lonKey.toFixed(4) + ")"
        opacity: 0.8
    }

    QC.CheckBox {
        id: metricBox
        KirigamiLayouts.FormData.label: i18n("Units")
        text: i18n("Metric (°C, km/h)")
        checked: plasmoid.configuration.metric
    }

    // Debounced so typing 10001 does not fire five lookups (6, 63, 633, ...).
    Timer {
        id: zipDebounce
        interval: 600
        onTriggered: {
            var z = zipField.text.trim();
            if (/^\d{5}$/.test(z) && z !== form.lastResolvedZip) form.lookupZip();
        }
    }

    // zippopotam.us, keyless — the same resolver the wallpaper uses.
    function lookupZip() {
        var z = zipField.text.trim();
        if (!/^\d{5}$/.test(z)) { form.lookupState = i18n("Enter 5 digits"); return; }
        form.lookupState = i18n("Looking up…");
        Wx.getJson(Wx.zipUrl(z), function (err, js) {
            if (err || !js || !js.places || !js.places.length) {
                form.lookupState = i18n("Not found");
                return;
            }
            var pl = js.places[0];
            form.latKey = parseFloat(pl.latitude);
            form.lonKey = parseFloat(pl.longitude);
            form.placeKey = pl["place name"] + ", " + pl["state abbreviation"];
            form.lastResolvedZip = z;
            form.lookupState = "✓ " + form.placeKey;
        });
    }
}
