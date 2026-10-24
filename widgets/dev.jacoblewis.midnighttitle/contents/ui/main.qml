/*
 * Midnight Title — the active application's name, pinned to the centre of the SCREEN.
 *
 * ⚠️ WHY THIS EXISTS RATHER THAN [spacer][title][spacer].
 * Two Expanding spacers centre the title in the LEFTOVER space, not on the screen.
 * With a left group (launcher + global menu) of width L and a right group (tray +
 * clock + media) of width R, the title's centre lands at (W + L - R) / 2 — off by
 * (L - R) / 2. Worse, R changes whenever the clock's text or the tray's icon count
 * changes, so the title visibly drifts. Exactly the same trap as equal-stretch
 * centring in the Midnight app's player bar.
 *
 * So: this applet takes ALL the leftover width itself and positions its content at
 * the screen's true midpoint, which no neighbour's width can perturb.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Window

import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.taskmanager as TaskManager

PlasmoidItem {
    id: root

    preferredRepresentation: fullRepresentation
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    TaskManager.TasksModel {
        id: tasks
        filterByVirtualDesktop: true
        filterByActivity: true
        filterByScreen: false
        groupMode: TaskManager.TasksModel.GroupDisabled
    }

    // activeTask is a live QModelIndex, so these re-evaluate on focus change. A title
    // change (a new Firefox tab) does NOT move activeTask, so dataChanged bumps `rev`,
    // which every read below references to re-run.
    property int rev: 0
    Connections { target: tasks; function onDataChanged() { root.rev++ } }
    readonly property var activeIdx: tasks.activeTask
    readonly property bool hasWindow: activeIdx && activeIdx.valid
    readonly property string appName: hasWindow
        ? (tasks.data(activeIdx, TaskManager.AbstractTasksModel.AppName) || "")
        : ""
    // The window title (2026-10-14, user: "display window titles name like what firefox
    // tab"). Apps append their own name ("Page — Mozilla Firefox"); with the app name
    // already shown in semibold beside it, that tail is stripped. A title that IS the
    // app name shows nothing extra.
    readonly property string winTitle: {
        root.rev;   // dependency only: re-read when the model's data changes
        if (!hasWindow) return "";
        let t = String(tasks.data(activeIdx, Qt.DisplayRole) || "").trim();
        const a = appName.toLowerCase();
        const m = t.match(/^(.*\S)\s+[—–-]\s+([^—–]+)$/);
        if (m && a && m[2].toLowerCase().indexOf(a) >= 0) t = m[1];
        if (!t || t.toLowerCase() === a) return "";
        return t;
    }
    readonly property var appIcon: hasWindow ? tasks.data(activeIdx, Qt.DecorationRole) : null

    // ── THE ISLAND BACKDROP (2026-10-06, user: "give my top island the same backdrop as
    // our dock"). Same mechanism the dock uses on ITS panel: switch the containment's
    // theme background off, then draw our own. ⚠️ NOT a Plasma theme — a generated
    // "Midnight" theme was tried and REVERTED because it left half the dock dead to
    // clicks. The backdrop is a child of the panel's ContainmentItem (found by walking
    // up from this applet), z -1, so it sits behind EVERY applet in the pill.
    // Material = DockView's bar exactly: --panel @ .62, white .12 hairline, dark .45
    // ring outside it; the shadow is smaller than the dock's because the floating
    // panel's window only has an 8px margin to draw it in.
    Component {
        id: islandComp
        Kirigami.ShadowedRectangle {
            anchors.fill: parent
            z: -1
            radius: Math.round(height * 0.31)
            color: Qt.rgba(0.114, 0.137, 0.212, 0.86)   // --panel #1D2336 @ .86 — dock + top pill share it; at .62 the
        // wallpaper decided their colour, so the two bars never matched (2026-10-06)
            border.width: 1
            border.color: Qt.rgba(0.220, 0.241, 0.306, 0.96)   // --panel + 12% white, opaque: same edge on any wallpaper
            shadow.size: 7
            shadow.yOffset: 2
            shadow.color: Qt.rgba(0, 0, 0, 0.45)
            Rectangle {
                anchors.fill: parent; anchors.margins: -1
                radius: parent.radius + 1
                color: "transparent"
                border.width: 1; border.color: Qt.rgba(0.02, 0.024, 0.04, 0.85)
                antialiasing: true
            }
        }
    }
    property var island: null
    function installIsland() {
        const c = Plasmoid.containment
        if (!c) return false
        let p = root.parent
        while (p && String(p).indexOf("ContainmentItem") !== 0) p = p.parent
        if (!p) return false
        c.backgroundHints = PlasmaCore.Types.NoBackground
        if (!root.island) root.island = islandComp.createObject(p)
        if (root.island && !away.target) {
            // the WHOLE pill (island + every applet) leaves and returns as one piece
            away.target = p
            p.transform = [ slide ]
            p.opacity = Qt.binding(function () { return away.fade })
        }
        return root.island !== null
    }

    // ── AWAY (2026-10-23, user: "make [the top panel] fade away in the same way our
    // widgets do"). The same Live.qml feed and AwaySlide.qml motion the desktop widgets
    // use, applied to the panel's ContainmentItem — so the island backdrop and every
    // applet in the pill (menu, title, tray, clock) slide off the top edge and fade
    // together, and come back on the first input. The panel WINDOW stays put (its
    // DodgeWindows mode is untouched); only what it draws moves, clipped by its edge.
    // ⚠️ Live.qml / AwaySlide.qml / Midnight.js are the shared kit copies — keep them
    // identical (`md5sum */contents/ui/{Live,AwaySlide}.qml`); Midnight.js is generated
    // (this package is in gen-theme.py's WIDGET_KIT).
    Live { id: mlive }
    AwaySlide { id: away; mode: mlive.mode; edge: "top" }
    Translate { id: slide; x: away.dx; y: away.dy }
    // Plasmoid.containment / the parent chain are not ready at completion — retry.
    Timer { interval: 250; repeat: true; running: true
            onTriggered: if (root.installIsland()) stop() }

    fullRepresentation: Item {
        id: frame

        // Absorb every spare pixel between the left and right groups; the content
        // inside is what gets centred, not this item.
        Layout.fillWidth: true
        Layout.minimumWidth: 1
        // ⚠️ THE TOP BAR IS A FIT-TO-CONTENT FLOATING PILL NOW (2026-10-06). A fit panel
        // sizes itself from each applet's PREFERRED width and gives fillWidth nothing
        // extra, so with implicitWidth 1 the title simply vanished. Preferring the name's
        // own width keeps it in the pill; in a full-width panel fillWidth still wins and
        // the screen-centring below behaves exactly as before.
        //
        // ⚠️⚠️ AND IT CARRIES ITS OWN SPACERS (2026-10-06, user: "add spacers to our top pill
        // so window title remains centered"). Real spacer applets cannot do it in a fit
        // pill — they get zero width, exactly like this title did. The pill is centred on
        // the screen, so the title is centred only when the groups either side are EQUAL;
        // `imbalance` is |left - right| and is added as padding on the short side.
        // L and R do not depend on this item's own width (the pill grows around it), so
        // it settles in one step. Debounced, not bound, to stay clear of a binding loop
        // through the panel's own relayout.
        property real imbalance: 0
        implicitWidth: content.visible ? content.width + 28 + imbalance : 1
        Layout.preferredWidth: implicitWidth

        function measure() {
            const win = frame.Window.window;
            if (!win) return;
            const L = frame.mapToItem(null, 0, 0).x;
            const R = win.width - L - frame.width;
            const next = Math.round(Math.abs(L - R));
            if (Math.abs(next - imbalance) > 1) imbalance = next;
        }
        Timer { id: remeasure; interval: 60; onTriggered: frame.measure() }
        onXChanged: remeasure.restart()
        onWidthChanged: remeasure.restart()
        Connections {
            target: frame.Window.window
            function onWidthChanged() { remeasure.restart() }
        }
        Component.onCompleted: remeasure.restart()

        readonly property real screenCentre: Screen.virtualX + Screen.width / 2

        Row {
            id: content

            spacing: 6
            y: Math.round((frame.height - height) / 2)
            visible: root.appName !== ""

            // ⚠️ mapFromGlobal is not a reactive binding source. frame.x and frame.width
            // are referenced deliberately so the binding re-runs whenever the panel
            // layout moves or resizes us — which is precisely when the answer changes.
            // Centre on the WINDOW's midpoint — the panel is centred on the screen, so that
            // is the screen's midpoint in both a full-width bar and the floating pill.
            // frame.width / L / R are referenced so this re-runs on every relayout.
            x: {
                const win = frame.Window.window;
                if (!win) return 0;
                const L = frame.mapToItem(null, 0, 0).x + 0 * frame.x;
                const ideal = win.width / 2 - L - content.width / 2;
                // Never overlap a neighbour: stop at our own edge, as macOS does when
                // the menus grow wide, rather than sliding underneath them.
                return Math.round(Math.max(0, Math.min(frame.width - content.width, ideal)));
            }


            Kirigami.Icon {
                source: root.appIcon
                width: Math.round(frame.height * 0.62)
                height: width
                anchors.verticalCenter: parent.verticalCenter
                visible: root.appIcon !== null
                smooth: true
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.appName
                // macOS sets the active app's name in semibold; the rest of the bar
                // stays regular, which is what makes it read as the subject.
                font.family: "Inter"
                font.pixelSize: 12
                font.weight: Font.DemiBold
                color: Kirigami.Theme.textColor
                elide: Text.ElideRight
                width: Math.min(implicitWidth, Math.max(0, frame.width - 40))
            }

            // The window title, regular weight and dimmed, after a hairline dot: the app
            // name stays the subject, the title says which window. Capped so a long page
            // title cannot push the pill into its neighbours; it elides instead.
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.winTitle !== ""
                text: "·"
                font.family: "Inter"; font.pixelSize: 12
                color: Kirigami.Theme.disabledTextColor
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.winTitle !== ""
                text: root.winTitle
                font.family: "Inter"
                font.pixelSize: 12
                color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                               Kirigami.Theme.textColor.b, 0.72)
                elide: Text.ElideRight
                width: Math.min(implicitWidth, 520)
            }
        }
    }
}
