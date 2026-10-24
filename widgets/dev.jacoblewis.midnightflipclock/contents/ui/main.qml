// Midnight Flip Clock — KDE plasmoid
//
// The flip clock lifted OUT of the flip-clock wallpaper and made a movable widget,
// so it is no longer tied to which wallpaper is set. FlipUnit.qml, FlipLeaf.qml and
// Theme.js are copied VERBATIM from the wallpaper (self-contained split-flap
// rendering); only this shell is new. Prism palette, NoBackground so it floats on
// the wallpaper like the other Midnight pills. If a fix lands in FlipUnit/FlipLeaf,
// port it to the wallpaper's originals too.
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import QtCore
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import "Theme.js" as Theme
import "Midnight.js" as M

PlasmoidItem {
    id: root
    // album colour + away state for this widget (Live.qml)
    Live { id: mlive }
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    preferredRepresentation: fullRepresentation

    Settings {
        id: prefs
        category: "MidnightFlipClock"
        property bool hour24: false
        property bool showDate: true
        property bool showSeconds: false
    }

    // ---- Prism palette (from Theme.js — single "glass" palette) -------------
    // ⚠️ Theme.pal() returns STRINGS. Assigning a string to a `color` parses it,
    // but reading .r/.g/.b off the string is undefined and Qt.rgba(undefined,…)
    // is transparent — so the alpha tints derive from real `color` props below.
    readonly property var   p:        Theme.pal("glass")
    readonly property color cAccent:  mlive.accent
    readonly property color cDim:     p.d
    readonly property color cPale:    p.p
    readonly property color cPop:     p.pop
    readonly property color cPanel:   p.panel
    function accentA(a) { return Qt.rgba(cAccent.r, cAccent.g, cAccent.b, a) }
    function popA(a)    { return Qt.rgba(cPop.r,    cPop.g,    cPop.b,    a) }

    // Card colours — the SAME derivations as the wallpaper, so the two read as one
    // material: theme panel at 62%, white hairline, translucent seam + outline.
    readonly property real  cardOpacity: 62
    readonly property color cCard:      Qt.rgba(cPanel.r, cPanel.g, cPanel.b, cardOpacity / 100)
    // card rims take the album colour (the digits stay white)
    readonly property color cHair:      Qt.rgba(mlive.album.r, mlive.album.g, mlive.album.b, 0.55)
    readonly property color cSeam:      Qt.rgba(0, 0, 0, 0.45)
    readonly property color cSeamLight: Qt.rgba(1, 1, 1, 0.13)
    readonly property color cOutline:   Qt.rgba(0, 0, 0, 0.45)
    readonly property color cSheen:     Qt.rgba(1, 1, 1, 0.26)
    readonly property color cDigit:     M.text    // body copy is --text everywhere
    readonly property string fDisp:     M.fontDisplay
    readonly property string fMono:     M.fontMono

    // ---- clock state + self-correcting driver (verbatim from the wallpaper) --
    QtObject {
        id: clock
        property string hh: "00"
        property string mm: "00"
        property string ss: "00"
        property string dateLine: ""
    }
    function ordinal(n) {
        if (n % 100 >= 11 && n % 100 <= 13) return n + "th";
        if (n % 10 === 1) return n + "st";
        if (n % 10 === 2) return n + "nd";
        if (n % 10 === 3) return n + "rd";
        return n + "th";
    }
    function updateClock() {
        var d = new Date();
        var h = d.getHours();
        var dh = prefs.hour24 ? h : (h % 12 === 0 ? 12 : h % 12);
        clock.hh = String(dh);   // no leading zero on the hour (Fliqlo convention)
        clock.mm = (d.getMinutes() < 10 ? "0" : "") + d.getMinutes();
        clock.ss = (d.getSeconds() < 10 ? "0" : "") + d.getSeconds();
        clock.dateLine = Qt.formatDate(d, "dddd") + " the " + root.ordinal(d.getDate());
    }
    // Re-arms for the remainder of the current second, so the flip lands on the
    // boundary instead of drifting, and re-syncs instantly after a suspend.
    Timer {
        id: tick
        interval: 1000; repeat: false; running: true
        onTriggered: { root.updateClock(); interval = Math.max(40, 1000 - new Date().getMilliseconds()); restart(); }
    }
    Component.onCompleted: updateClock()

    // ---- the clock face -----------------------------------------------------
    fullRepresentation: Item {
        id: face
        // slide off the nearest edge while away (AwaySlide.qml)
        AwaySlide { id: away; target: face; mode: mlive.mode }
        transform: Translate { x: away.dx; y: away.dy }
        opacity: away.fade
        // ⚠️ This is the DISPLAY size, not a hint. The containment re-places any
        // applet whose stored geometry disagrees with its implicit size, which is
        // what kept throwing this clock back to the middle of the desktop.
        implicitWidth: 544
        implicitHeight: 368          // = the stored, grid-snapped height (2026-10-23)
        Layout.minimumWidth: 140
        Layout.minimumHeight: 100

        readonly property int  units:  prefs.showSeconds ? 3 : 2
        readonly property real aspect: 0.85
        // Fit to width, then clamp by height (reserving room for the date badge).
        // The date line is gone (2026-10-06, user: "remove the day info now that calendar
        // exist") — the calendar widget carries the day; the digits get the full height.
        readonly property real availH: height
        readonly property real cardH:  Math.max(30, Math.min(
            width / (units * aspect + 0.20 * (units - 1)), availH))
        readonly property real cardW:  cardH * aspect
        readonly property real gap:    cardH * 0.20
        // One glyph size for every unit, so a narrowed hour card keeps the minutes' size.
        readonly property real digitPx: Math.min(cardW * 0.70, cardH * 0.62)

        Column {
            anchors.centerIn: parent
            spacing: face.cardH * 0.09
            // the shared widget shadow under the cards
            layer.enabled: true
            // the shared widget shadow; blurMax scales with the clock's far larger glyphs
            layer.effect: MultiEffect { shadowEnabled: true; shadowColor: M.shadowColor; shadowOpacity: M.shadowOpacity; shadowBlur: M.shadowBlur; blurMax: M.shadowBlurMax * 1.7; shadowVerticalOffset: M.shadowY * 1.4; autoPaddingEnabled: true }

            Row {
                id: clockRow
                anchors.horizontalCenter: parent.horizontalCenter
                // side bearings put the INK 3px right of the row's box centre — measured
                // Cards restored (2026-10-06, user: "restore flipclock backdrop and flipping
                // visual") — the cards separate the units again, so no colon (Fliqlo).
                spacing: face.gap

                FlipUnit {
                    value: clock.hh
                    cardW: face.cardW; cardH: face.cardH
                    fontPx: face.digitPx
                    cardColor: root.cCard; edgeColor: root.cHair; sheenColor: root.cSheen
                    digitColor: root.cDigit; seamColor: root.cSeam
                    seamLight: root.cSeamLight; outlineColor: root.cOutline
                    displayFont: root.fDisp
                }
                FlipUnit {
                    value: clock.mm
                    cardW: face.cardW; cardH: face.cardH
                    fontPx: face.digitPx
                    cardColor: root.cCard; edgeColor: root.cHair; sheenColor: root.cSheen
                    digitColor: root.cDigit; seamColor: root.cSeam
                    seamLight: root.cSeamLight; outlineColor: root.cOutline
                    displayFont: root.fDisp
                }
                FlipUnit {
                    visible: prefs.showSeconds
                    value: clock.ss
                    cardW: face.cardW; cardH: face.cardH
                    cardColor: root.cCard; edgeColor: root.cHair; sheenColor: root.cSheen
                    // seconds read one step quieter (also the dimmest on OLED)
                    digitColor: Qt.rgba(root.cDigit.r, root.cDigit.g, root.cDigit.b, 0.62)
                    seamColor: root.cSeam
                    seamLight: root.cSeamLight; outlineColor: root.cOutline
                    displayFont: root.fDisp
                }
            }
        }
    }
}
