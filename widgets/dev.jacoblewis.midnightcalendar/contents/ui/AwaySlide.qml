// AwaySlide — slides its target off the nearest screen edge while you are away
// (mlive.mode, from Live.qml), back in on the first input (2026-10-07).
// ⚠️ NO HALO. A soft dark pool behind each widget was tried the same day and REMOVED
// (user: "afraid of burn-in") — a static darker patch on this WOLED ages its pixels
// differently from the rest of the panel. Do not re-add a backdrop here.
// ⚠️ IDENTICAL COPY IN EVERY MIDNIGHT DESKTOP WIDGET. `md5sum */contents/ui/AwaySlide.qml`.
// Usage, as the FIRST child of the representation's root item:
//     AwaySlide { id: away; target: <root id>; mode: mlive.mode }
//     transform: Translate { x: away.dx; y: away.dy }
//     opacity: away.fade
import QtQuick
import QtQuick.Window

Item {
    id: aw
    property Item target
    property string mode: "here"
    // force an exit edge ("top"/"bottom"/"left"/"right"); "" = the nearest one. The top
    // panel sets "top": inside its own window the pill sits at x 0, so "nearest" lies.
    property string edge: ""
    readonly property bool away: mode === "away"
    property real dx: 0
    property real dy: 0
    property real fade: 1

    // ── the slide ───────────────────────────────────────────────────────────
    // Nearest screen edge, and the distance that takes the whole widget past it.
    function exitVector() {
        if (!target) return Qt.point(0, 0)
        var p = target.mapToGlobal(0, 0)
        var w = target.width, h = target.height
        var sw = Screen.width, sh = Screen.height
        var gaps = [ { g: p.x,          v: Qt.point(-(p.x + w + 96), 0) },
                     { g: sw - p.x - w, v: Qt.point(sw - p.x + 96, 0) },
                     { g: p.y,          v: Qt.point(0, -(p.y + h + 96)) },
                     { g: sh - p.y - h, v: Qt.point(0, sh - p.y + 96) } ]
        var sides = ["left", "right", "top", "bottom"]
        if (edge !== "") return gaps[sides.indexOf(edge)].v
        gaps.sort(function (a, b) { return a.g - b.g })
        return gaps[0].v
    }

    onAwayChanged: {
        back.stop(); out.stop()
        if (away) {
            var v = exitVector()
            outX.to = v.x; outY.to = v.y
            out.start()
        } else {
            back.start()
        }
    }

    ParallelAnimation {
        id: out
        NumberAnimation { id: outX; target: aw; property: "dx"; duration: 900; easing.type: Easing.InOutCubic }
        NumberAnimation { id: outY; target: aw; property: "dy"; duration: 900; easing.type: Easing.InOutCubic }
        NumberAnimation { target: aw; property: "fade"; to: 0; duration: 900; easing.type: Easing.InQuad }
    }
    ParallelAnimation {
        id: back
        NumberAnimation { target: aw; property: "dx"; to: 0; duration: 520; easing.type: Easing.OutCubic }
        NumberAnimation { target: aw; property: "dy"; to: 0; duration: 520; easing.type: Easing.OutCubic }
        NumberAnimation { target: aw; property: "fade"; to: 1; duration: 380; easing.type: Easing.OutQuad }
    }
}
