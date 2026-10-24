/*
 * Midnight Dock — icons-only dock with macOS-style fisheye magnification.
 *
 * Built on org.kde.taskmanager's TasksModel (a real on-disk QML module) rather
 * than forking org.kde.plasma.taskmanager: that applet's QML lives in a QRC inside
 * its .so, and its Backend / SmartLauncherItem types only register when Plasma
 * itself instantiates the applet. A fork can have upstream's QML *or* its C++
 * types, never both — see CLAUDE.md.
 *
 * Horizontal (bottom/top edge) only. Magnification needs vertical headroom, so the
 * panel is taller than the visible bar and we draw the bar ourselves; the panel's
 * own background is switched off via the containment's backgroundHints, which
 * Panel.qml honours by dropping its FrameSvg imagePath.
 *
 * All visuals + the fisheye math live in DockView.qml so they can be rendered
 * headlessly by tools/harness.qml.
 */
import QtQuick
import QtCore

import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.pipewire as PipeWire
import org.kde.taskmanager as TaskManager

PlasmoidItem {
    id: root

    readonly property bool ownBackground: Plasmoid.configuration.ownBackground

    preferredRepresentation: fullRepresentation
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    TaskManager.TasksModel {
        id: tasksModel

        // Mirrors the stock icons-only task manager (sortingStrategy=4 + hidden activated
        // launchers), which is the ordering this dock replaced: pinned launchers in
        // configured order, then running windows. launchInPlace/SortManual were tried and
        // rejected: TasksModel seeds SortManual from insertion order, so windows that
        // already existed claim the front and the row order comes out scrambled.
        launchInPlace: false
        separateLaunchers: true
        hideActivatedLaunchers: true

        groupMode: Plasmoid.configuration.groupWindows
            ? TaskManager.TasksModel.GroupApplications
            : TaskManager.TasksModel.GroupDisabled
        sortMode: TaskManager.TasksModel.SortActivity

        filterByVirtualDesktop: false
        filterByActivity: false
        filterByScreen: false

        onLauncherListChanged: Plasmoid.configuration.launchers = launcherList

        // Assigned once, deliberately NOT bound. Binding launcherList to the config
        // key makes the model's own start-up churn write back through the binding:
        // it briefly reports an empty list, that empties the config key, the binding
        // re-reads the now-empty key, and the stored launchers are gone for good.
        // Upstream does the same one-shot assignment for exactly this reason.
        Component.onCompleted: launcherList = Plasmoid.configuration.launchers
    }

    // away state for the dock (Live.qml, the shared kit feed)
    Live { id: mlive }

    fullRepresentation: DockView {
        id: view
        // ── AWAY (2026-10-23, user: "do the same with our dock"): the dock slides off the
        // bottom edge and fades with the desktop widgets and the top pill after 30s idle,
        // back on first input. Whole view = bar backdrop + icons + badges move as one.
        AwaySlide { id: away; target: view; mode: mlive.mode; edge: "bottom" }
        transform: Translate { x: away.dx; y: away.dy }
        opacity: away.fade
        // the panel's input region must follow the dock's width (see root.remask)
        onWidthChanged: remaskTimer.restart()

        taskModel: tasksModel
        count: tasksModel.count

        base: Plasmoid.configuration.iconSize
        maxScale: Plasmoid.configuration.maxZoom / 100
        influencePx: Plasmoid.configuration.iconSize * Plasmoid.configuration.influence / 100
        gap: Plasmoid.configuration.iconSpacing
        showLabels: Plasmoid.configuration.showLabels
        ownBackground: root.ownBackground

        // Launchers are contiguous and first in this sort, so the boundary is simply
        // the last one. Recomputed on any model change: an app starting hides its
        // launcher and appends a window, which moves the boundary without
        // necessarily changing the row count.
        separatorAfter: {
            const R = TaskManager.AbstractTasksModel;
            const _n = tasksModel.count + view.modelRevision;
            let last = -1;
            for (let i = 0; i < tasksModel.count; ++i) {
                if (tasksModel.data(tasksModel.makeModelIndex(i), R.IsLauncher)) {
                    last = i;
                } else {
                    break;
                }
            }
            return (last >= 0 && last < tasksModel.count - 1) ? last : -1;
        }

        property int modelRevision: 0

        // ⚠️ ROLE-FILTERED (2026-10-06). separatorAfter and badgeCounts walk every row,
        // and TasksModel emits dataChanged constantly for roles neither reads — window
        // titles (a browser retitles on every tab switch), IsActive on every focus
        // change, demands-attention, geometry. Each of those used to rebuild both arrays
        // and re-evaluate every row's badge. Only a change to a role they actually read
        // (or an unspecified-roles change) counts now.
        //
        // ⚠️ AND MOVES COUNT. SortActivity reorders rows with rowsMoved/layoutChanged,
        // which the old handler ignored entirely — so after a reorder the separator and
        // the badges were indexed against the PREVIOUS row order until something else
        // happened to fire.
        readonly property var revRoles: [TaskManager.AbstractTasksModel.IsLauncher,
                                         TaskManager.AbstractTasksModel.AppId]
        Connections {
            target: tasksModel
            function onDataChanged(tl, br, roles) {
                // a plain loop: `roles` is a QList sequence, not a guaranteed JS Array
                let hit = !roles || roles.length === 0;
                for (let i = 0; !hit && i < roles.length; ++i) {
                    hit = view.revRoles.indexOf(roles[i]) >= 0;
                }
                if (hit) {
                    view.modelRevision++;
                }
            }
            function onRowsInserted() { view.modelRevision++; }
            function onRowsRemoved() { view.modelRevision++; }
            function onRowsMoved() { view.modelRevision++; }
            function onLayoutChanged() { view.modelRevision++; }
            function onModelReset() { view.modelRevision++; }
        }

        // ---- badges (Unity LauncherEntry + Steam friends-online) ----------------
        // Two daemons, two files, ONE WRITER EACH (tools/unity-badge-daemon.py writes
        // badges.json, tools/steam-friends-daemon.py writes steam-badge.json) — see
        // their docstrings for why a bridge is needed at all. Merged client-side in
        // badgeCounts below.
        //
        // ⚠️⚠️ EVENT-DRIVEN, NOT POLLED (2026-10-06). This used to be TWO 3-second
        // timers, each spawning a `cat` through an executable DataSource — ~57,600
        // process spawns a day out of plasmashell, for files that change rarely: the
        // Steam daemon only writes once a minute and the Unity bridge only on an actual
        // count change. Both daemons write atomically (tmp + os.replace), which is a
        // directory change, so a FolderListModel (inotify via QFileSystemWatcher) sees
        // every write. The files are read ONCE per change, both in a single spawn.
        // A slow fallback poll stays in case the watch is ever lost.
        //
        // A plain XHR file:// read is blocked by Qt unless QML_XHR_ALLOW_FILE_READ=1
        // is set for the whole plasmashell process, which is why the read itself is
        // still a `cat` through the executable engine.
        property var badgesData: ({})
        property var steamBadgeData: ({})
        readonly property string badgeSep: "--MIDNIGHT-BADGE-SEP--"

        function parseBadges(txt, current) {
            const t = String(txt || "").trim();
            if (t === "" || t.charAt(0) !== "{") {
                return current;          // daemon not up yet / caught mid-write
            }
            try {
                const parsed = JSON.parse(t);
                // Unchanged content keeps the same object, so badgeCounts does not
                // recompute and no row repaints.
                return JSON.stringify(parsed) === JSON.stringify(current) ? current : parsed;
            } catch (e) {
                return current;
            }
        }

        Plasma5Support.DataSource {
            id: badgeRead
            engine: "executable"; connectedSources: []
            onNewData: function (source, data) {
                disconnectSource(source);
                const parts = String(data["stdout"] || "").split(view.badgeSep);
                view.badgesData = view.parseBadges(parts[0], view.badgesData);
                view.steamBadgeData = view.parseBadges(parts[1], view.steamBadgeData);
            }
        }

        function readBadges() {
            badgeRead.connectSource("cd ~/.cache/midnight-dock 2>/dev/null && "
                + "cat badges.json 2>/dev/null; echo '" + view.badgeSep + "'; "
                + "cat steam-badge.json 2>/dev/null");
        }

        // ⚠️ EVENT-DRIVEN VIA A BLOCKING WAITER, NOT FolderListModel. The daemons write
        // with os.replace and a directory watch never reported the new content, so
        // counts only moved on the 60s fallback (found 2026-10-06 testing the new-mail
        // pulse). tools/wait-badges.py blocks on inotify and returns the instant a
        // badge file lands; we read, then re-arm it. One sleeping python process.
        Plasma5Support.DataSource {
            id: badgeWait
            engine: "executable"; connectedSources: []
            onNewData: function (source, data) {
                disconnectSource(source)
                badgeKick.restart()
                badgeRearm.restart()
            }
        }
        readonly property string waiterCmd: "python3 " + Qt.resolvedUrl("../../tools/wait-badges.py")
                                            .toString().replace("file://", "") + " 300"
        // running at start = the first arm; every return restarts it
        Timer { id: badgeRearm; interval: 50; running: true; onTriggered: badgeWait.connectSource(view.waiterCmd) }

        // Coalesces a burst (temp write + rename) into one read.
        Timer { id: badgeKick; interval: 120; onTriggered: view.readBadges() }

        Timer {
            interval: 60000          // fallback only; the watcher does the real work
            running: true
            repeat: true
            triggeredOnStart: true
            onTriggered: view.readBadges()
        }

        // Row-indexed, matching taskModel: badgeCounts[i] is the badge for row i,
        // 0 when that row's AppId has none. A BINDING to the property DockView
        // already declares (like separatorAfter below), not a redeclaration --
        // DockView owns badgeCounts as part of its public, harness-testable API.
        // Recomputed on any model OR badge-data change; view.modelRevision forces
        // re-evaluation the same way separatorAfter's own binding does.
        badgeCounts: {
            const R = TaskManager.AbstractTasksModel;
            const _n = tasksModel.count + view.modelRevision;
            const _u = view.badgesData;
            const _s = view.steamBadgeData;
            const arr = [];
            for (let i = 0; i < tasksModel.count; ++i) {
                const appId = tasksModel.data(tasksModel.makeModelIndex(i), R.AppId) || "";
                // The two sources never share an AppId (Steam never appears in the
                // Unity bridge's file, since it never calls that API) -- a plain
                // fallback chain is enough, no need to actually add the two.
                arr.push(_u[appId] || _s[appId] || 0);
            }
            return arr;
        }

        onActivated: (index, button) => {
            const idx = tasksModel.makeModelIndex(index);
            if (button === Qt.MiddleButton) {
                tasksModel.requestNewInstance(idx);
                return;
            }
            const isLauncher = tasksModel.data(idx, TaskManager.AbstractTasksModel.IsLauncher);
            const isActive = tasksModel.data(idx, TaskManager.AbstractTasksModel.IsActive);
            const isMinimized = tasksModel.data(idx, TaskManager.AbstractTasksModel.IsMinimized);

            if (!isLauncher && isActive && !isMinimized) {
                tasksModel.requestToggleMinimized(idx);
            } else {
                // Only a real launch bounces. Raising a window that already exists is
                // not a launch, and bouncing there would be noise.
                if (isLauncher) {
                    view.bounce(index);
                }
                tasksModel.requestActivate(idx);
            }
        }

        // ---- right-click menu ------------------------------------------------
        // The row's flags are SNAPSHOT when the menu opens rather than bound to
        // the model: tasksModel.data() is not a reactive binding source, so a
        // bound item would show whatever was true the first time it evaluated.
        property int ctxIndex: -1
        property bool ctxIsLauncher: false
        property bool ctxHasLauncher: false
        property bool ctxClosable: false
        property bool ctxGroup: false
        // ⚠️⚠️ requestAddLauncher / requestRemoveLauncher TAKE A QUrl, NOT A MODEL
        // INDEX — `Q_INVOKABLE bool requestAddLauncher(const QUrl &url)`. Handing them
        // makeModelIndex() threw "Passing incompatible arguments to C++ functions from
        // JavaScript is not allowed" and pin/unpin silently did nothing: the menu item
        // closed as though it had worked. Every OTHER request* call on this model does
        // take an index, which is exactly why this reads as correct.
        property url ctxLauncherUrl: ""
        // ⚠️ REMOVE MATCHES ON THE WITHOUT-ICON FORM. The stored launcher list holds
        // URLs without the fallback icon query, so removing with the decorated URL
        // matches nothing and the launcher stays pinned. Upstream splits these two the
        // same way.
        property url ctxLauncherUrlNoIcon: ""

        onMenuRequested: (index, mx, my) => {
            const R = TaskManager.AbstractTasksModel;
            const idx = tasksModel.makeModelIndex(index);
            view.ctxIndex = index;
            view.ctxIsLauncher = !!tasksModel.data(idx, R.IsLauncher);
            view.ctxHasLauncher = !!tasksModel.data(idx, R.HasLauncher);
            view.ctxClosable = !!tasksModel.data(idx, R.IsClosable);
            view.ctxGroup = !!tasksModel.data(idx, R.IsGroupParent);
            view.ctxLauncherUrl = tasksModel.data(idx, R.LauncherUrl) || "";
            view.ctxLauncherUrlNoIcon = tasksModel.data(idx, R.LauncherUrlWithoutIcon) || "";
            ctxMenu.visualParent = view;
            ctxMenu.open(mx, my);
        }

        PlasmaExtras.Menu {
            id: ctxMenu

            PlasmaExtras.MenuItem {
                text: view.ctxIsLauncher ? i18n("Open") : i18n("Open New Window")
                icon: "window-new"
                // An unpinned window with no launcher has nothing to launch.
                visible: view.ctxIsLauncher || view.ctxHasLauncher
                onClicked: {
                    const idx = tasksModel.makeModelIndex(view.ctxIndex);
                    if (view.ctxIsLauncher) {
                        tasksModel.requestActivate(idx);
                    } else {
                        tasksModel.requestNewInstance(idx);
                    }
                }
            }

            PlasmaExtras.MenuItem { separator: true }

            PlasmaExtras.MenuItem {
                readonly property bool pinned: view.ctxIsLauncher || view.ctxHasLauncher
                icon: pinned ? "window-unpin" : "window-pin"
                // ⚠️ DISABLED, NOT HIDDEN, when the window resolves to no launcher.
                // Hiding it made "I can't pin battle.net" look like a broken dock: the
                // item simply was not there and nothing said why. A greyed item with
                // the reason on it is the honest version — and the real cause is
                // always the app's .desktop StartupWMClass not matching the window.
                readonly property bool pinnable: pinned || String(view.ctxLauncherUrl) !== ""
                enabled: pinnable
                text: pinnable
                    ? (pinned ? i18n("Unpin from Dock") : i18n("Pin to Dock"))
                    : i18n("Can't pin — no launcher for this window")
                onClicked: {
                    if (pinned) {
                        tasksModel.requestRemoveLauncher(view.ctxLauncherUrlNoIcon);
                    } else {
                        tasksModel.requestAddLauncher(view.ctxLauncherUrl);
                    }
                }
            }

            PlasmaExtras.MenuItem {
                separator: true
                visible: view.ctxClosable
            }

            PlasmaExtras.MenuItem {
                text: view.ctxGroup ? i18n("Close All Windows") : i18n("Close")
                icon: "window-close"
                // A pinned-but-not-running launcher has no window to close.
                visible: view.ctxClosable
                onClicked: tasksModel.requestClose(tasksModel.makeModelIndex(view.ctxIndex))
            }
        }


        // ---- live window previews --------------------------------------------
        // ⚠️ These are real screencasts, not cached bitmaps — that is what makes
        // them accurate rather than a stale snapshot. Each holds a
        // ScreencastingRequest open for as long as it exists, so the row lives in a
        // Loader tied to the tooltip's visibility; leaving it built would keep a
        // PipeWire stream running for every window you ever hovered.
        // ⚠️ Assigned on index change, NOT a binding. As a `var` binding this returned
        // a FRESH ARRAY on every re-evaluation, so the Repeater's model changed
        // identity constantly, tearing down and rebuilding every ScreencastingRequest
        // and re-showing the Dialog mid-rebuild — 194 "empty dialog" warnings and a
        // thumbnail that never settled at its proper size.
        property var hoverWins: []

        // A beat before showing: lets the Loader build, and a tooltip that waits a
        // moment before appearing is the better behaviour anyway.

        Timer {
            id: tipDelay
            interval: 220
            repeat: false
            onTriggered: {
                if (Plasmoid.configuration.showPreviews && view.hoverWins.length > 0) {
                    previewTip.showToolTip();
                    view.tipShown = true;
                }
            }
        }

        // ⚠️ tipIndex, not hoveredIndex, drives the tooltip's CONTENT. Moving the
        // pointer off the dock and into the tooltip drops hoveredIndex to -1; if the
        // content followed that, the thumbnails would be torn down the instant you
        // reached for them and could never be clicked.
        property int tipIndex: -1

        function closeTip() {
            tipDelay.stop();
            tipGrace.stop();
            if (view.tipShown) {
                previewTip.hideImmediately();
                view.tipShown = false;
            }
            view.tipIndex = -1;
            view.hoverWins = [];
        }

        // ⚠️⚠️ THE TOOLTIP'S GRACE IS SEPARATE FROM THE ZOOM'S, AND LONGER ON PURPOSE.
        // DockView drops the magnification 180ms after the pointer leaves, which wants
        // to feel immediate. Reaching a thumbnail is a different act — you cross the
        // dead gap between the panel edge and the tooltip — and while the two shared
        // one deadline the tooltip inherited the wrong one: it was reachable, but only
        // if you hurried. Widening the zoom timer instead would leave the icons
        // magnified long after the pointer had gone. Two concerns, two timers.
        Timer {
            id: tipGrace
            interval: 600
            repeat: false
            onTriggered: {
                if (!previewTip.containsMouse && view.hoveredIndex < 0) {
                    view.closeTip();
                }
            }
        }

        onHoveredIndexChanged: {
            if (hoveredIndex < 0) {
                // Hold it open while the pointer is inside the tooltip itself, and give
                // it the grace window to get there.
                if (!previewTip.containsMouse) {
                    tipGrace.restart();
                }
                return;
            }
            // Back on the dock: whatever was pending is cancelled.
            tipGrace.stop();
            if (hoveredIndex === tipIndex) {
                return;
            }
            tipIndex = hoveredIndex;
            hoverWins = tasksModel.data(tasksModel.makeModelIndex(hoveredIndex),
                                        TaskManager.AbstractTasksModel.WinIdList) || [];
            if (view.tipShown) {
                previewTip.hideImmediately();
                view.tipShown = false;
            }
            if (hoverWins.length > 0 && Plasmoid.configuration.showPreviews) {
                tipDelay.restart();
            } else {
                tipDelay.stop();
            }
        }

        // Left the tooltip without returning to the dock: it may close — but through
        // the same grace, because leaving downward crosses that same gap on the way
        // back to the icons.
        Connections {
            target: previewTip
            function onContainsMouseChanged() {
                if (previewTip.containsMouse) {
                    tipGrace.stop();
                } else if (view.hoveredIndex < 0) {
                    tipGrace.restart();
                }
            }
        }

        previewShowing: tipShown
        property bool tipShown: false

        // ⚠️ ToolTipArea, NOT a raw PlasmaCore.Dialog. A Dialog makes the caller own
        // the sizing contract: it measures mainItem the instant it is told to show,
        // and every attempt to satisfy that by hand — data-derived implicit size, a
        // debounce — still left it settling at the wrong size or showing an empty
        // box. ToolTipArea owns sizing and placement itself, which was the problem.
        //
        // It anchors its window to ITSELF, so this invisible item is parked exactly
        // over the hovered icon and tracks it as the fisheye reflows the row.
        Item {
            id: tipAnchor

            readonly property var cell: view.tipIndex >= 0
                ? view.layout.items[view.tipIndex]
                : null

            // ⚠️ Anchored to the applet's TOP EDGE, not to the icon. Anchoring to the
            // icon's top put the tooltip's lower edge at y≈28 — INSIDE the panel — so it
            // covered the headroom the pointer crosses when approaching from above. The
            // tooltip stole the pointer, the dock got onExited, the zoom dropped, the
            // tooltip hid, hover came back, and it cycled: a visible flicker, and only
            // ever from above, because approaching from below keeps the pointer down at
            // y≈90-110 where the tooltip never reaches. Pinning the anchor to y=0 puts
            // the whole tooltip outside the applet, where it cannot take the pointer.
            x: cell ? view.rowX + cell.x : 0
            y: 0
            width: cell ? cell.w : 0
            height: 1

            PlasmaCore.ToolTipArea {
                id: previewTip

                anchors.fill: parent
                // Driven by hand: the dock's own tracker consumes hover, so this area
                // never sees the pointer and its automatic show would never fire.
                active: true
                // Interactive so the pointer can reach the thumbnails. Safe now that
                // the anchor is pinned to the applet's TOP EDGE — the tooltip sits
                // wholly outside the panel and cannot take the dock's own hover.
                interactive: true
                location: PlasmaCore.Types.BottomEdge

                mainItem: Item {
                    id: tipRoot

                    readonly property int n: Math.min(view.hoverWins.length, 3)
                    readonly property int thumbW: 176
                    readonly property int thumbH: 110

                    implicitWidth: Math.max(160, n * thumbW + Math.max(0, n - 1) * 8 + 16)
                    implicitHeight: (n > 0 ? thumbH + 6 : 0) + view.labelH + 12

                        Column {
                            id: tipCol
                            anchors.centerIn: parent
                            spacing: 6

                            Loader {
                                // ⚠️ NOT gated on previewTip.visible — that is circular. The
                                // Dialog refuses to show an empty mainItem, the mainItem is
                                // empty until this Loader builds, and the Loader was waiting
                                // on the Dialog being visible. It logged "trying to show an
                                // empty dialog" and nothing ever appeared. Gate on the hover
                                // state instead: same teardown, no cycle.
                                //
                                // ⚠️⚠️ tipIndex, NEVER hoveredIndex. Reaching for a thumbnail
                                // means leaving the icons, which drops hoveredIndex to -1 —
                                // gating on it DESTROYS the thumbnails the moment the pointer
                                // arrives, taking the MouseArea with them. The tell is
                                // "PipeWire remote error: -32 no more input formats": the
                                // screencast is torn down mid-negotiation. tipIndex is the
                                // state that spans icon AND tooltip, which is why it exists.
                                active: Plasmoid.configuration.showPreviews
                                    && view.tipIndex >= 0
                                    && view.hoverWins.length > 0
                                sourceComponent: Row {
                                    spacing: 8

                                    Repeater {
                                        // Capped: a browser with a dozen windows must not
                                        // open a dozen screencasts at once.
                                        model: view.hoverWins.slice(0, 3)

                                        delegate: Rectangle {
                                            id: thumb

                                            required property var modelData
                                            required property int index

                                            width: tipRoot.thumbW
                                            height: tipRoot.thumbH
                                            radius: 5
                                            color: Qt.rgba(1, 1, 1, thumbHit.containsMouse ? 0.10 : 0.05)
                                            border.width: 1
                                            border.color: thumbHit.containsMouse
                                                ? Qt.rgba(0.604, 0.549, 1.0, 0.85)   // --accent
                                                : Qt.rgba(1, 1, 1, 0.10)
                                            clip: true

                                            // A little lift, so it reads as a target.
                                            scale: thumbHit.containsMouse ? 1.03 : 1.0
                                            Behavior on scale {
                                                NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
                                            }

                                            MouseArea {
                                                id: thumbHit
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    // Several windows means the row is a
                                                    // group parent, so address the CHILD;
                                                    // with one, the row IS the window.
                                                    const idx = view.hoverWins.length > 1
                                                        ? tasksModel.makeModelIndex(view.tipIndex, thumb.index)
                                                        : tasksModel.makeModelIndex(view.tipIndex);
                                                    tasksModel.requestActivate(idx);
                                                    view.closeTip();
                                                }
                                            }

                                            TaskManager.ScreencastingRequest {
                                                id: cast
                                                uuid: modelData
                                            }

                                            PipeWire.PipeWireSourceItem {
                                                anchors.fill: parent
                                                anchors.margins: 1
                                                nodeId: cast.nodeId
                                                // `ready` flips on the first frame; fade in
                                                // rather than popping an empty box.
                                        opacity: ready ? 1 : 0
                                                Behavior on opacity { NumberAnimation { duration: 90 } }
                                            }
                                        }
                                    }
                                }
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                // Same reason as the Loader above: the label must not blank
                                // out when the pointer moves onto the tooltip.
                                text: view.nameAt(view.tipIndex)
                                color: "#F2F5FF"
                                font.pixelSize: 12
                                font.family: "Inter"
                                elide: Text.ElideRight
                                width: Math.min(implicitWidth, tipRoot.implicitWidth - 16)
                            }
                        }
                }
            }
        }
    }

    // Switching the containment's background off is what gives the icons somewhere
    // to overflow into; Panel.qml drops its FrameSvg when it sees NoBackground.
    function applyPanelBackground(off) {
        const c = Plasmoid.containment;
        if (!c) {
            return false;
        }
        c.backgroundHints = off
            ? PlasmaCore.Types.NoBackground
            : PlasmaCore.Types.DefaultBackground;
        return true;
    }

    // Plasmoid.containment isn't populated yet when the applet completes — whether
    // it resolves on the first try is a race (it did on some starts and not others,
    // leaving the panel's own background drawn behind ours). Retry briefly.
    Timer {
        id: bgRetry
        interval: 200
        repeat: true
        running: false
        property int tries: 0
        onTriggered: {
            if (root.applyPanelBackground(root.ownBackground) || ++tries > 25) {
                running = false;
                if (tries > 25) {
                    console.warn("MidnightDock: no containment handle after "
                        + tries + " tries; panel background left alone");
                }
            }
        }
    }

    onOwnBackgroundChanged: if (!applyPanelBackground(ownBackground)) bgRetry.restart()

    // ⚠️⚠️ "DOCK ONLY WORKS ON THE LEFT SIDE" (2026-10-23). A floating panel's INPUT
    // REGION is the mask of its background FrameSvg (Panel.qml panelMask). With
    // NoBackground that frame's imagePath is "" and its mask stops updating, so the
    // region freezes at the panel width of the moment the background went off. When
    // the dock widens afterwards (launchers load, an app opens) the new right-hand part
    // takes no clicks or hover. Same symptom as the 2026-10-06 "half the dock dead"
    // incident. Fix: whenever the width settles, put the background back and take it
    // off again IN THE SAME TICK — the frame recomputes its mask at the current size,
    // and nothing is ever painted with it.
    function remask() {
        const c = Plasmoid.containment;
        if (!c || !root.ownBackground) return;
        c.backgroundHints = PlasmaCore.Types.DefaultBackground;
        c.backgroundHints = PlasmaCore.Types.NoBackground;
    }
    Timer { id: remaskTimer; interval: 400; onTriggered: root.remask() }
    // and once after start-up, when the launchers have loaded
    Timer { interval: 3000; running: true; onTriggered: root.remask() }

    Component.onCompleted: {
        if (!applyPanelBackground(ownBackground)) {
            bgRetry.restart();
        }
    }

    // Leave the panel as we found it if the widget is removed.
    Component.onDestruction: applyPanelBackground(false)
}
