// Live — one feed per desktop widget: are you away, and what colour is the album?
// (2026-10-07). Sits at the PlasmoidItem root (id: live) so both the root's own
// colour properties and the representation can read it.
//   live.mode    "here" / "away"       <- midnight-away.service
//   live.accent  the album's accent while the Midnight app PLAYS, else --accent.
//                Hue from the sleeve, lightness guaranteed >= 4.5:1 by the app's own
//                ambient.accent_from (midnight-hue.service) — safe for TEXT.
//   live.album / live.album2   the sleeve's two lead colours (fills, rims, glows)
// ⚠️ IDENTICAL COPY IN EVERY MIDNIGHT DESKTOP WIDGET (packages cannot import across
// each other). Fix one, copy to all; `md5sum */contents/ui/Live.qml` must agree.
// ⚠️ The executable engine is SHARED by every applet in plasmashell and keys sources
// by command text — the per-instance tag stops five widgets collapsing into one
// waiter (measured: 1 process instead of 5 before the tag).
import QtQuick
import org.kde.plasma.plasma5support as Plasma5Support
import "Midnight.js" as M

Item {
    id: live
    visible: false
    width: 0; height: 0

    property string mode: "here"
    property bool playing: false
    property color accent: M.accent
    property color album: M.accent
    property color album2: M.accentDeep
    // the accent at an alpha. ⚠️ M.a(hex, a) from Midnight.js takes a HEX STRING and
    // throws on a colour object ("slice is not a function") — use this for live colours.
    function a(alpha) { return Qt.rgba(accent.r, accent.g, accent.b, alpha) }
    Behavior on accent { ColorAnimation { duration: 1800; easing.type: Easing.InOutQuad } }
    Behavior on album  { ColorAnimation { duration: 1800; easing.type: Easing.InOutQuad } }
    Behavior on album2 { ColorAnimation { duration: 1800; easing.type: Easing.InOutQuad } }

    property string known: "none"
    property int seq: 0
    readonly property string tag: String(Math.floor(Math.random() * 1e9))

    function apply(text) {
        known = Qt.md5(text)
        try {
            var d = JSON.parse(text)
            mode = d.away === "away" ? "away" : "here"
            var h = d.hue || {}
            playing = !!h.on
            if (playing && h.accent) {
                accent = h.accent
                album  = (h.c && h.c[0]) || h.accent
                album2 = (h.c && h.c[1]) || album
            } else {
                // not playing: back to the house colours, as the wallpaper does
                accent = M.accent; album = M.accent; album2 = M.accentDeep
            }
        } catch (e) { }
    }
    function arm() {
        seq++
        src.connectSource("python3 '" + Qt.resolvedUrl("../code/wait-live.py").toString().replace("file://", "") + "' " + known
                          + " 600 " + tag + "-" + seq)
    }
    Plasma5Support.DataSource {
        id: src
        engine: "executable"
        onNewData: function (source, data) {
            disconnectSource(source)
            var s = String(data["stdout"] || "").trim()
            if (s.length) live.apply(s)
            rearm.restart()
        }
    }
    // A short gap so a waiter that fails instantly cannot spin.
    Timer { id: rearm; interval: 250; onTriggered: live.arm() }
    Component.onCompleted: arm()
}
