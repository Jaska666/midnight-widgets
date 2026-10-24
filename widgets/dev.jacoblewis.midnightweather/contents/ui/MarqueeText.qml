// MarqueeText — a Text that reveals its full contents by scrolling on hover.
//
// ⚠️ THERE ARE FOUR COPIES OF THIS FILE, one per Midnight plasmoid (radio / type /
// weather / mpv). Plasmoid packages cannot import across each other, and pointing an
// import at an absolute path outside the package is fragile, so the file is duplicated
// deliberately — the same call the weather widget already makes for WeatherPop.qml and
// Theme.js. FIX ONE, PORT TO THE OTHER THREE.
//
// Behaviour: when the text fits, this is an ordinary elided Text and nothing animates.
// When it does not fit, hovering scrolls it left to reveal the tail, pauses, and eases
// back. It never loops continuously — a permanently moving label on a desktop widget is
// exactly the kind of ambient motion this project keeps removing.
import QtQuick

Item {
    id: mq

    property string text: ""
    property color  color: "white"
    property string family: "Inter"
    property real   pixelSize: 14
    property bool   bold: false
    property bool   italic: false
    // 1px glyph outline (widget kit textOutline) so text reads on any wallpaper
    property color  outlineColor: "#000000"
    property real   letterSpacing: 0
    // Right-align while the text FITS (some callers, e.g. a quote attribution, are
    // right-aligned at rest). Ignored once it overflows, since the marquee has to start
    // from the left edge or the beginning of the string would never be readable.
    property bool   alignRight: false
    // Drive this from the surrounding MouseArea's containsMouse.
    property bool   hovered: false
    // ⚠️ WIDTH IS MEASURED OFF TextMetrics, NOT off the Text item. `inner` is elided
    // while at rest, and an elided Text reports the implicitWidth of the ELIDED string —
    // so measuring it would make `overflow` read 0 and the marquee could never trigger.
    TextMetrics {
        id: tm
        font: inner.font
        text: mq.text
    }
    // How far past the right edge the tail sits; 0 when the text fits.
    readonly property real overflow: Math.max(0, tm.width - width)
    readonly property bool truncated: overflow > 0.5
    // At rest the string is elided with a proper ellipsis; only while scrolling does it
    // render in full. A hard mid-glyph clip at rest looked like a rendering fault.
    readonly property bool scrolling: hovered && truncated

    clip: true
    implicitHeight: inner.implicitHeight

    Text {
        id: inner
        text: mq.text
        color: mq.color
        font.family: mq.family
        font.pixelSize: mq.pixelSize
        font.bold: mq.bold
        font.italic: mq.italic
        style: Text.Outline; styleColor: mq.outlineColor
        font.letterSpacing: mq.letterSpacing
        // Elided (with a real ellipsis) at rest; full width once scrolling, so the tail
        // has somewhere to travel. Measurement comes from `tm`, never from here.
        elide: mq.scrolling ? Text.ElideNone : Text.ElideRight
        width: mq.scrolling ? tm.width : mq.width
        y: 0
        // Resting position: flush left, or flush right when the caller asked for it and
        // the string still fits. The "scrolled" state overrides this while hovering.
        x: (mq.alignRight && !mq.truncated) ? (mq.width - tm.width) : 0

        Behavior on x {
            NumberAnimation {
                duration: Math.max(320, mq.overflow * 26)
                easing.type: Easing.InOutQuad
            }
        }
    }

    // NOTE: no right-edge fade. It would have to match whatever sits behind the text,
    // which differs per widget (pill fill, sheet fill, wallpaper), so a gradient here
    // would be wrong on at least one surface. The hard clip is honest and cheap.
    //
    // ⚠️ The scroll is driven by a state change, NOT by binding x to `hovered`. A plain
    // binding is destroyed the first time the Behavior animates x, after which the
    // marquee silently stops working on every subsequent hover.
    states: [
        State {
            name: "scrolled"
            when: mq.scrolling
            PropertyChanges { target: inner; x: -mq.overflow }
        }
    ]
}
