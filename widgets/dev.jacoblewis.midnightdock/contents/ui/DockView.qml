/*
 * The dock's visuals + fisheye math, deliberately free of any Plasmoid/TasksModel
 * dependency so it can be rendered headlessly by tools/harness.qml. Feed it any
 * model exposing `decoration` (or `icon`) and `IsLauncher`.
 */
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Item {
    id: view

    // The panel sizes an applet from these, not from implicitWidth alone. Without
    // them the row is wider than the applet and gets clipped to a square-edged stub.
    Layout.preferredWidth: implicitWidth
    Layout.minimumWidth: implicitWidth
    Layout.maximumWidth: implicitWidth
    Layout.preferredHeight: implicitHeight
    Layout.minimumHeight: implicitHeight

    onWidthChanged: if (debug) console.warn("MidnightDock geom: width=" + width
        + " implicitW=" + implicitWidth + " count=" + count
        + " rowW=" + layout.width.toFixed(1) + " height=" + height)
    property bool debug: false

    property var taskModel: null
    property int count: 0

    // Badge count per row, indexed the same as taskModel (arr[i] for row i).
    // Optional -- the harness never sets it, and an absent/short array just
    // means no task shows a badge. Owned by main.qml, which is where the real
    // AppId-matching against the Unity bridge's JSON lives; DockView stays
    // free of that so it keeps rendering headlessly under tools/harness.qml.
    property var badgeCounts: []

    property int base: 40
    property real maxScale: 1.9
    property real influencePx: 104
    property int gap: 12
    property bool showLabels: true
    property bool ownBackground: true

    signal activated(int index, int button)
    // Right-click. Emitted with view-local coordinates so the owner can pop a menu
    // there; the view itself stays free of any model/Plasmoid knowledge.
    signal menuRequested(int index, real x, real y)

    // Reserving the widest possible row means magnifying never resizes the panel.
    implicitWidth: maxRowWidth + barPad * 2
    implicitHeight: barH + headroom + bottomMargin

    // ---- bar geometry ------------------------------------------------------
    readonly property int barPad: Math.round(base * 0.2)
    readonly property int barH: base + barPad * 2
    readonly property int bottomMargin: 6
    readonly property int labelH: 22
    readonly property int headroom: Math.ceil(base * maxScale) - base + labelH + 8
    // The largest an icon ever renders. Icons are rasterised at this size once and
    // scaled down — see the delegate's `face`.
    readonly property int iconMax: Math.ceil(base * maxScale)

    readonly property real barTop: height - bottomMargin - barH
    // Every icon's bottom edge rests on this line, so magnification grows upward.
    readonly property real iconBaseline: barTop + barPad + base

    // ---- fisheye -----------------------------------------------------------
    readonly property string iid: Math.random().toString(36).substr(2, 4)
    property real _lastLogY: -999
    property real restCursor: -1e6
    property bool zoomActive: false
    readonly property real zoom: zoomActive ? 1 : 0

    // ⚠️ NO ARM BAND. This used to require the pointer to be at/below the bar's top
    // edge before engaging, which made the dock behave differently depending on the
    // direction you approached from: entering at the bottom edge is instantly past
    // that line, but coming down from above you cross ~50px of headroom with nothing
    // happening — and that headroom is exactly where the magnified icons and the
    // preview tooltip sit. Step into the tooltip and come back down and you re-enter
    // ABOVE the line, so it stayed dead. The applet's own bounds are the right
    // hover region; the panel is only as wide as the dock and mostly headroom.
    function updateHover(mx, my) {
        if (debug && Math.abs(my - _lastLogY) > 2) {
            _lastLogY = my;
            console.warn("DOCK[" + iid + "] move y=" + my.toFixed(0) + " h=" + height
                + " zoom=" + zoomActive + " tip=" + previewShowing + " idx=" + hoveredIndex);
        }
        zoomActive = true;
        restCursor = toRest(mx - rowX);
    }

    // Force a state without a real pointer (used by tools/harness.qml). Addressed
    // in *resting* space, so it doesn't depend on the current magnified layout.
    function setHoverIndex(i, on) {
        zoomActive = on;
        restCursor = (on && i >= 0) ? i * (base + gap) + base / 2 : -1e6;
    }

    // The hovered row, or -1. Exposed so the owner can anchor a tooltip window to
    // the icon without reaching into the layout.
    readonly property int hoveredIndex: zoomAnim > 0.5 ? restIndex() : -1

    // Set by the owner while a preview tooltip is up, so the name pill stands down.
    property bool previewShowing: false

    // Draw a divider AFTER this row (the last pinned launcher). -1 = no divider.
    // The owner computes it; the view only draws.
    property int separatorAfter: -1

    // macOS bounces a launcher while its app starts. Feedback, not decoration —
    // which is the bar this stack sets for keeping motion at all.
    function bounce(i) {
        const it = (i >= 0 && i < rep.count) ? rep.itemAt(i) : null;
        if (it) {
            it.startBounce();
        }
    }

    // The delegate Item for a row — a tooltip's visualParent has to be the icon
    // itself, or it will not follow the icon as the row re-lays out under the zoom.
    function iconItemAt(i) {
        return (i >= 0 && i < rep.count) ? rep.itemAt(i) : null;
    }

    // Which icon the cursor is over, in resting space. Deriving this from
    // restCursor rather than a raw pointer x keeps it correct mid-animation.
    function restIndex() {
        if (restCursor < -1e5 || count === 0) {
            return -1;
        }
        const i = Math.floor(restCursor / (base + gap));
        if (i < 0 || i >= count) {
            return -1;
        }
        // Between two icons: no label rather than a wrong one.
        return (restCursor - i * (base + gap)) <= base ? i : -1;
    }

    Behavior on zoomAnim {
        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
    }
    property real zoomAnim: 0
    onZoomChanged: zoomAnim = zoom

    // Each icon's scale falls off with distance from the cursor; widths are then
    // summed so neighbours are pushed aside instead of overlapped.
    function solve(cursor, amount) {
        const n = view.count;
        const items = [];
        let x = 0;
        for (let i = 0; i < n; ++i) {
            const restCenter = i * (base + gap) + base / 2;
            let s = 1;
            if (amount > 0) {
                const t = Math.min(1, Math.abs(restCenter - cursor) / influencePx);
                // cos falloff: peak at the cursor, exactly 1 at the edge of influence.
                s = 1 + (maxScale - 1) * Math.cos(t * Math.PI / 2) * amount;
            }
            const w = base * s;
            items.push({ x: x, w: w, s: s });
            x += w + gap;
        }
        return { items: items, width: Math.max(0, x - gap) };
    }

    readonly property var layout: solve(restCursor, zoomAnim)
    readonly property real rowX: (width - layout.width) / 2

    // Invert the current layout to recover the cursor's position in *resting*
    // coordinates. Using the raw x would feed magnified positions back into the
    // distance term and oscillate.
    function toRest(cx) {
        const L = layout.items;
        const n = L.length;
        if (n === 0) {
            return -1e6;
        }
        if (cx <= L[0].x) {
            return cx - L[0].x;
        }
        for (let i = 0; i < n; ++i) {
            const it = L[i];
            if (cx <= it.x + it.w) {
                return i * (base + gap) + ((cx - it.x) / it.w) * base;
            }
            if (cx < it.x + it.w + gap) {
                return i * (base + gap) + base + (cx - it.x - it.w);
            }
        }
        const last = L[n - 1];
        return (n - 1) * (base + gap) + base + (cx - last.x - last.w);
    }

    function indexAt(cx) {
        const L = layout.items;
        for (let i = 0; i < L.length; ++i) {
            if (cx >= L[i].x && cx <= L[i].x + L[i].w) {
                return i;
            }
        }
        return -1;
    }

    // Widest the row can ever get, so magnifying never resizes the panel.
    readonly property real maxRowWidth: {
        const n = view.count;
        if (n === 0) {
            return 0;
        }
        let best = 0;
        for (let i = 0; i < n; ++i) {
            const w = solve(i * (base + gap) + base / 2, 1).width;
            if (w > best) {
                best = w;
            }
        }
        return best;
    }

    // Works for both QAbstractItemModel (the real TasksModel) and ListModel
    // (the harness), so the shipped component is what gets rendered in tests.
    function nameAt(i) {
        if (!taskModel || i < 0) {
            return "";
        }
        if (typeof taskModel.get === "function") {
            const o = taskModel.get(i);
            return (o && (o.display || o.name)) || "";
        }
        if (typeof taskModel.index === "function") {
            return taskModel.data(taskModel.index(i, 0), Qt.DisplayRole) || "";
        }
        return "";
    }

    // ---- visuals -----------------------------------------------------------
    Kirigami.ShadowedRectangle {
        id: bar

        x: view.rowX - view.barPad
        y: view.barTop
        width: view.layout.width + view.barPad * 2
        height: view.barH
        radius: Math.round(view.barH * 0.31)

        // Matches the desktop widgets' pills: theme `panel` at .62, not --bg at .82.
        // ⚠️ These mirror design/tokens.json (panel #1D2336). The dock is not yet a
        // gen-theme.py target, so a palette regen will NOT update it — see the note
        // in CLAUDE.md about never hand-editing palette values.
        color: Qt.rgba(0.114, 0.137, 0.212, 0.86)   // --panel #1D2336 @ .86 — dock + top pill share it; at .62 the
        // wallpaper decided their colour, so the two bars never matched (2026-10-06)
        border.width: 1
        border.color: Qt.rgba(0.220, 0.241, 0.306, 0.96)   // --panel + 12% white, opaque: same edge on any wallpaper

        shadow.size: 18
        shadow.yOffset: 4
        shadow.color: Qt.rgba(0, 0, 0, 0.45)

        visible: view.ownBackground && view.count > 0

        // The pills' two-tone edge: a dark ring OUTSIDE the white hairline, so the
        // bar still reads against a bright wallpaper. A hairline alone is not the
        // house look.
        Rectangle {
            anchors.fill: parent
            anchors.margins: -1
            radius: parent.radius + 1
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(0.02, 0.024, 0.04, 0.85)
            antialiasing: true
        }
    }

    // Minimal divider between pinned launchers and running apps, in the gap the
    // layout already leaves between them — so it needs no space of its own and
    // rides the fisheye along with the icons either side.
    Rectangle {
        id: divider

        readonly property var a: (view.separatorAfter >= 0)
            ? view.layout.items[view.separatorAfter] : null
        readonly property var b: (view.separatorAfter >= 0)
            ? view.layout.items[view.separatorAfter + 1] : null

        visible: a !== null && a !== undefined && b !== null && b !== undefined
        width: 1
        height: Math.round(view.base * 0.52)
        radius: 0.5
        color: Qt.rgba(1, 1, 1, 0.16)
        antialiasing: true

        x: visible ? Math.round(view.rowX + (a.x + a.w + b.x) / 2) : 0
        y: Math.round(view.iconBaseline - view.base / 2 - height / 2)
    }

    Repeater {
        id: rep
        model: view.taskModel

        delegate: Item {
            id: task

            required property int index
            required property var model

            readonly property var cell: view.layout.items[index]
                ?? ({ x: 0, w: view.base, s: 1 })

            x: view.rowX + cell.x
            y: view.iconBaseline - cell.w - bounceY
            width: cell.w
            height: cell.w

            // ⚠️ transform/opacity ONLY. CLAUDE.md records the radio page's pulse
            // genuinely dropping frames because it animated box-shadow, a PAINT
            // property with no compositor acceleration.
            property real bounceY: 0
            property real press: 1

            function startBounce() {
                bounceAnim.restart();
            }

            SequentialAnimation {
                id: bounceAnim
                NumberAnimation { target: task; property: "bounceY"; to: view.base * 0.42
                                  duration: 260; easing.type: Easing.OutQuad }
                NumberAnimation { target: task; property: "bounceY"; to: 0
                                  duration: 300; easing.type: Easing.OutBounce }
            }

            Behavior on press { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }

            // Scale about the icon's BOTTOM: it sits on the bar's baseline, so
            // scaling about the centre would lift it off the line.
            transform: Scale {
                origin.x: task.width / 2
                origin.y: task.height
                xScale: task.press
                yScale: task.press
            }

            // New icons arrive rather than pop — something changed, and that is
            // worth a beat of motion.
            opacity: 0
            Component.onCompleted: appear.start()
            NumberAnimation {
                id: appear
                target: task; property: "opacity"; from: 0; to: 1
                duration: 180; easing.type: Easing.OutCubic
            }

            // ⚠️⚠️ THE ICON IS RENDERED ONCE, AT ITS LARGEST, AND SHRUNK BY A TRANSFORM.
            // It used to be `anchors.fill: parent` on an item whose size the fisheye
            // rewrites every frame — and Kirigami.Icon re-requests (and re-rasterises the
            // SVG for) its pixmap whenever its size crosses an icon-size bucket, so a
            // hover sweep was re-rendering icons on the CPU mid-animation. Now `face` is
            // a fixed iconMax square that only ever SCALES (a GPU transform), the pixmap
            // is loaded exactly once. The badge rides inside it, so its text is laid out once too
            // instead of re-shaped at a new pixel size every frame.
            // ⚠️ NO `layer` here: a mipmapped layer on the icon CLIPPED its top half under
            // the scale transform (measured in tools/harness). Plain bilinear from the
            // 1.9x pixmap is already crisp at the resting size.
            Item {
                id: face
                width: view.iconMax
                height: view.iconMax
                x: (task.width - width) / 2
                y: task.height - height
                transformOrigin: Item.Bottom
                scale: task.width / view.iconMax

                Kirigami.Icon {
                    anchors.fill: parent
                    source: task.model.decoration ?? task.model.icon ?? ""
                    smooth: true
                }

                // Unread/badge count from Unity LauncherEntry (Proton Mail, Discord, ...),
            // bridged in by tools/unity-badge-daemon.py. It scales UNIFORMLY with the
            // face, so it never distorts — it is just drawn once at the largest size.
            readonly property int badge: {
                const arr = view.badgeCounts;
                // Explicit range check + `|| 0` coercion: task.index can read as
                // undefined for one binding pass before Repeater finishes assigning
                // its required properties, and a bare arr[task.index] would then
                // itself read back undefined -- which QML refuses to coerce into
                // this `int` property (logged, not fatal, but noisy every tick).
                if (!arr || task.index < 0 || task.index >= arr.length) {
                    return 0;
                }
                return arr[task.index] || 0;
            }

            // ── NEW-MAIL / UNREAD ARRIVAL (2026-10-06, user: "enhance my protonmail
            // notification / new mail indicator"). A count that GOES UP pulses the badge
            // (three rings + a pop) so new mail is seen without a second notification on
            // top of the app's own; the badge then stays FRESH (larger, brighter rim)
            // until that app is focused or its count drops. Works for every badged app.
            property int  lastBadge: -1
            property bool fresh: false
            readonly property bool appActive: task.model.IsActive === true
            onAppActiveChanged: if (appActive) face.fresh = false
            onBadgeChanged: {
                if (face.lastBadge >= 0 && face.badge > face.lastBadge) {
                    face.fresh = !face.appActive
                    arrival.restart()
                }
                if (face.badge < face.lastBadge || face.badge === 0) face.fresh = false
                face.lastBadge = face.badge
            }

            Repeater {
                model: 3
                delegate: Rectangle {
                    id: ring
                    required property int index
                    visible: face.badge > 0
                    width: badgeDot.height; height: width; radius: width / 2
                    x: badgeDot.x + badgeDot.width - width / 2 - badgeDot.height / 2
                    y: badgeDot.y
                    color: "transparent"
                    border.width: 2; border.color: Qt.rgba(0, 0.898, 0.690, 1)
                    opacity: 0; scale: 1
                    SequentialAnimation {
                        id: ringAnim
                        PauseAnimation { duration: ring.index * 420 }
                        ParallelAnimation {
                            NumberAnimation { target: ring; property: "scale"; from: 1; to: 2.3; duration: 900; easing.type: Easing.OutCubic }
                            NumberAnimation { target: ring; property: "opacity"; from: 0.85; to: 0; duration: 900; easing.type: Easing.OutCubic }
                        }
                    }
                    Connections { target: arrival; function onStarted() { ringAnim.restart() } }
                }
            }
            SequentialAnimation {
                id: arrival
                NumberAnimation { target: badgeDot; property: "scale"; to: 1.35; duration: 140; easing.type: Easing.OutBack }
                NumberAnimation { target: badgeDot; property: "scale"; to: face.fresh ? 1.12 : 1; duration: 260; easing.type: Easing.OutCubic }
            }

            Rectangle {
                id: badgeDot
                visible: face.badge > 0
                scale: face.fresh ? 1.12 : 1
                transformOrigin: Item.Center
                Behavior on scale { enabled: !arrival.running; NumberAnimation { duration: 200 } }

                readonly property string label: face.badge > 99 ? "99+" : String(face.badge)

                width: Math.max(height, badgeLabel.implicitWidth + 7 * view.iconMax / view.base)
                height: Math.round(face.width * 0.40)
                radius: height / 2

                x: face.width - width * 0.62
                y: -height * 0.22

                // Mirrors the CardBadge/Jellyfin countIndicator spec verbatim (near-
                // solid --pop, top sheen, pale text, --pop rim) rather than a fresh
                // design -- CLAUDE.md is explicit that an eyeballed near-miss here is
                // exactly how the count-badge look drifts across surfaces.
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(0.20, 0.949, 0.729, 0.98) }
                    GradientStop { position: 0.6; color: Qt.rgba(0, 0.898, 0.690, 0.95) }
                }
                // fresh = a brighter, thicker rim: "this arrived since you last looked"
                border.width: face.fresh ? 2 : 1
                border.color: face.fresh ? "#F8FAFE" : Qt.rgba(0, 0.898, 0.690, 0.60)   // --pale / --pop @ .60
                antialiasing: true

                Text {
                    id: badgeLabel
                    anchors.centerIn: parent
                    text: badgeDot.label
                    color: "#F8FAFE"   // --pale
                    font.pixelSize: Math.max(9, Math.round(parent.height * 0.6))
                    font.bold: true
                    font.family: "Inter"
                    style: Text.Raised
                    styleColor: Qt.rgba(0, 0, 0, 0.5)
                }
            }

            }

            // macOS-style running dot, in the bar's padding under the icon.
            Rectangle {
                width: 4
                height: 4
                radius: 2
                color: Qt.rgba(1, 1, 1, 0.85)
                x: (task.width - width) / 2
                y: view.iconBaseline - task.y + view.barPad / 2 - height / 2
                visible: task.model.IsLauncher === false
            }

            MouseArea {
                id: hit
                anchors.fill: parent
                hoverEnabled: false   // the tracker above owns hover
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                onPressed: task.press = 0.88
                onReleased: task.press = 1
                onCanceled: task.press = 1
                onClicked: mouse => {
                    if (mouse.button === Qt.RightButton) {
                        // Anchor the menu to the icon's top-centre rather than the
                        // pointer, so it doesn't jump around as the icon magnifies.
                        const p = hit.mapToItem(view, task.width / 2, 0);
                        view.menuRequested(task.index, p.x, p.y);
                    } else {
                        view.activated(task.index, mouse.button);
                    }
                }
            }
        }
    }

    // Name pill above the magnified icon — macOS's own affordance. Live window
    // previews are a separate tooltip WINDOW owned by main.qml: a ~130px card
    // cannot fit inside a ~118px panel, and growing the panel to hold it would
    // turn that whole strip into an input dead zone over the desktop.
    //
    // The pill stands down while a preview is showing, so the two never stack.
    Item {
        id: labelHolder

        readonly property int idx: view.hoveredIndex
        readonly property var cell: idx >= 0 ? view.layout.items[idx] : null

        visible: view.showLabels && cell !== null && cell !== undefined
            && !view.previewShowing
        opacity: visible ? view.zoomAnim : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }

        Rectangle {
            x: labelHolder.cell
                ? view.rowX + labelHolder.cell.x + labelHolder.cell.w / 2 - width / 2
                : 0
            y: labelHolder.cell
                ? view.iconBaseline - labelHolder.cell.w - height - 8
                : 0
            width: labelText.implicitWidth + 18
            height: view.labelH
            radius: height / 2
            color: Qt.rgba(0.055, 0.067, 0.106, 0.94)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.14)

            Text {
                id: labelText
                anchors.centerIn: parent
                text: view.nameAt(labelHolder.idx)
                color: "#F2F5FF"
                font.pixelSize: 12
                font.family: "Inter"
            }
        }
    }

    // Hover tracker. Takes no buttons, so the per-icon MouseAreas still get
    // clicks while this owns the cursor position driving the magnification.
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton

        // Entering can be the ONLY event we get — a pointer that warps in and stops
        // fires onEntered with no onPositionChanged, and the zoom never engaged.
        onEntered: {
            if (view.debug) console.warn("DOCK[" + view.iid + "] ENTER y=" + mouseY.toFixed(0)
                + " tip=" + view.previewShowing);
            // A re-entry within the grace window is churn, not a real return: keep
            // whatever zoom state we had instead of demanding a re-arm.
            leaveGrace.stop();
            view.updateHover(mouseX, mouseY);
        }
        onPositionChanged: mouse => view.updateHover(mouse.x, mouse.y)
        // ⚠️ Do NOT drop the zoom here. MEASURED: the applet emits spurious
        // EXIT/ENTER pairs while the pointer moves across it — the pointer never
        // actually left. Resetting on each one meant that approaching from ABOVE,
        // the re-entry landed above the arm line, nothing re-armed, and the zoom
        // died; from below it always re-entered inside the bar so it looked fine.
        // Deferring the reset absorbs the churn and keeps the real leave working.
        onExited: {
            if (view.debug) console.warn("DOCK[" + view.iid + "] EXIT tip=" + view.previewShowing);
            leaveGrace.restart();
        }

        Timer {
            id: leaveGrace
            interval: 180
            repeat: false
            onTriggered: view.zoomActive = false
        }
    }
}
