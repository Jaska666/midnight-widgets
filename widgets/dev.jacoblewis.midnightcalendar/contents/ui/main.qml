/*
 * Midnight Calendar — Apple's medium calendar widget, in the Midnight design language.
 *
 *   left:  weekday eyebrow (--accent where Apple uses red) · the date as a hero numeral ·
 *          what is left of the day, each event on its calendar's own colour bar
 *   right: the month, today as a filled --accent disc with a --bg label (the accent rule:
 *          a glyph on a filled accent takes --bg, 7.30:1), a dot under days with events
 *
 * FRAMELESS like every other Midnight widget (user, 2026-10-06: Apple layout, no tile):
 * text and marks only, readable over the wallpaper because of the shared drop shadow.
 * Every size, colour and the shadow come from Midnight.js, which gen-theme.py writes from
 * design/tokens.json — nothing here is a hand-typed palette value.
 *
 * DATA: ~/.cache/midnight/calendar.json, written by contents/code/icloud-calendar.py
 * (user timer midnight-calendar.timer). Read on change via a directory watch, the same
 * zero-poll pattern the Midnight Dock uses for its badge files.
 *
 * Click a day in the month to see its events; click the date numeral (or wait 30s) to come
 * back to today. Click an event to open iCloud Calendar.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtCore
import Qt.labs.folderlistmodel

import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as Plasma5Support
import "Midnight.js" as M

PlasmoidItem {
    id: root
    // album colour + away state for this widget (Live.qml)
    Live { id: mlive }

    preferredRepresentation: fullRepresentation
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    // ---------------------------------------------------------------- data
    property var cal: ({ state: "loading", error: "", events: [], calendars: [] })
    // Minute-resolution clock: drops finished events and rolls the day at midnight.
    property date now: new Date()
    // null = today; otherwise local midnight of the day picked in the month grid
    property var picked: null

    readonly property date shownDay: picked ? picked : dayStart(now)
    readonly property bool showingToday: !picked

    function dayStart(d) { var x = new Date(d); x.setHours(0, 0, 0, 0); return x }
    function addDays(d, n) { return new Date(d.getFullYear(), d.getMonth(), d.getDate() + n) }
    function sameDay(a, b) {
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth()
            && a.getDate() === b.getDate()
    }
    function key(d) { return d.getFullYear() * 10000 + d.getMonth() * 100 + d.getDate() }

    function eventsOn(day, upcomingOnly) {
        var s = dayStart(day).getTime(), e = addDays(dayStart(day), 1).getTime()
        var t = root.now.getTime(), out = []
        var evs = root.cal.events || []
        for (var i = 0; i < evs.length; ++i) {
            var ev = evs[i]
            if (ev.start >= e || ev.end <= s) continue
            if (upcomingOnly && !ev.allDay && ev.end <= t) continue
            out.push(ev)
        }
        return out
    }

    // the agenda shown on the left
    readonly property var dayEvents: eventsOn(shownDay, showingToday)

    // first upcoming event AFTER today — the "nothing left today" line points at it
    readonly property var nextEvent: {
        var e = addDays(dayStart(now), 1).getTime(), evs = cal.events || []
        for (var i = 0; i < evs.length; ++i)
            if (evs[i].start >= e) return evs[i]
        return null
    }

    // key(day) -> colour of that day's first event, for the month dots
    readonly property var dotMap: {
        var m = {}, evs = cal.events || []
        for (var i = 0; i < evs.length; ++i) {
            var d = new Date(evs[i].start), end = evs[i].end
            // multi-day events mark every day they cover (capped: a stray 3-month event
            // must not spin this binding)
            for (var n = 0; n < 40 && d.getTime() < end; ++n) {
                var k = key(d)
                if (m[k] === undefined) m[k] = evs[i].color
                d = addDays(dayStart(d), 1)
            }
        }
        return m
    }

    function timeLabel(ev) {
        if (ev.allDay) return "All day"
        var s = new Date(ev.start), e = new Date(ev.end)
        // ⚠️ Qt's "h" WITHOUT "AP" is the 24-HOUR hour ("19:30 – 9:00 PM"). Format both
        // ends as 12-hour, then drop the start's AM/PM when both share it (Apple style).
        var sameHalf = (s.getHours() < 12) === (e.getHours() < 12)
        var fs = Qt.formatTime(s, "h:mm AP")
        if (sameHalf) fs = fs.replace(/\s*[AaPp]\.?[Mm]\.?$/, "")
        return fs + " – " + Qt.formatTime(e, "h:mm AP")
    }

    function dayWord(d) {
        var today = dayStart(now)
        if (sameDay(d, addDays(today, 1))) return "Tomorrow"
        return Qt.formatDate(d, "dddd")
    }

    // ---------------------------------------------------- read on change
    Plasma5Support.DataSource {
        id: reader
        engine: "executable"; connectedSources: []
        onNewData: function (source, data) {
            disconnectSource(source)
            var t = String(data["stdout"] || "").trim()
            if (t.charAt(0) !== "{") return
            try { root.cal = JSON.parse(t) } catch (e) { /* caught mid-write: keep last */ }
        }
    }
    function read() { reader.connectSource("cat ~/.cache/midnight/calendar.json 2>/dev/null") }

    FolderListModel {
        folder: StandardPaths.writableLocation(StandardPaths.GenericCacheLocation) + "/midnight"
        nameFilters: ["calendar.json"]
        showDirs: false
        onDataChanged: kick.restart()
        onCountChanged: kick.restart()
    }
    Timer { id: kick; interval: 150; onTriggered: root.read() }

    Timer {   // the clock; also a slow fallback re-read in case the watch is ever lost
        interval: 30000; running: true; repeat: true; triggeredOnStart: true
        property int n: 0
        onTriggered: { root.now = new Date(); if (n++ % 20 === 0) root.read() }
    }
    Timer { id: backToToday; interval: 30000; onTriggered: root.picked = null }
    onPickedChanged: picked ? backToToday.restart() : backToToday.stop()

    readonly property var writable: (cal.calendars || []).filter(function (c) {
        return c.writable && c.url })

    AddSheet {
        id: addSheet
        onAdded: root.read()          // the --add run re-syncs; pick the result up now
    }

    // ================================================================ face
    fullRepresentation: Item {
        id: face
        // slide off the nearest edge while away (AwaySlide.qml)
        AwaySlide { id: away; target: face; mode: mlive.mode }
        transform: Translate { x: away.dx; y: away.dy }
        opacity: away.fade

        // ⚠️ The DISPLAY size, not a hint: the desktop containment re-places any applet
        // whose stored geometry disagrees with its implicit size (the "placement fight").
        // Apple's medium widget is ~2:1; 262.5u x 137.5u at the desktop's u of 1.28.
        // ⚠️ 176, not 168: the containment snaps applet height to its 16px grid, and an
        // implicit size that disagrees with the stored one is re-placed every restart.
        implicitWidth: 336
        implicitHeight: 176
        Layout.minimumWidth: 200
        Layout.minimumHeight: 100

        readonly property real u: Math.max(0.6, Math.min(width / 262.5, height / 137.5))

        HoverHandler { id: hov }

        Item {
            id: body
            anchors.fill: parent
            // the shared hover lift, same as every pill
            transform: Translate {
                y: hov.hovered ? -M.hoverLift * face.u : 0
                Behavior on y { NumberAnimation { duration: M.dur; easing.type: Easing.OutCubic } }
            }
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true; shadowColor: M.shadowColor; shadowOpacity: M.shadowOpacity
                shadowBlur: M.shadowBlur; blurMax: M.shadowBlurMax; shadowVerticalOffset: M.shadowY
                autoPaddingEnabled: true
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 0    // frameless: box edge = content edge (pixel grid, 2026-10-06)
                anchors.rightMargin: 0
                spacing: M.gap * face.u * 1.4

                // ---------------------------------------------- left: the day
                ColumnLayout {
                    Layout.fillHeight: true
                    Layout.preferredWidth: 128 * face.u
                    Layout.maximumWidth: 128 * face.u
                    spacing: 0

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6 * face.u
                        Text {
                            style: Text.Outline; styleColor: M.textOutline   // 1px outline, kit token
                            text: Qt.formatDate(root.shownDay, "dddd").toUpperCase()
                            color: mlive.accent
                            font.family: M.fontMono; font.bold: true
                            font.pixelSize: M.tertiary * face.u
                            font.letterSpacing: M.eyebrowTrack
                        }
                        // stale-data mark: last good agenda is shown, but say so
                        Text {
                            style: Text.Outline; styleColor: M.textOutline   // 1px outline, kit token
                            visible: root.cal.state === "offline" || root.cal.state === "error"
                            text: "OFFLINE"
                            color: M.dim
                            font.family: M.fontMono
                            font.pixelSize: (M.tertiary - 1.5) * face.u
                            font.letterSpacing: M.eyebrowTrack
                        }
                        Item { Layout.fillWidth: true }
                        // + : add an event. Shown on hover only — the face stays text and
                        // marks at rest — and only when a calendar can actually be written.
                        Text {
                            style: Text.Outline; styleColor: M.textOutline   // 1px outline, kit token
                            id: plus
                            visible: root.writable.length > 0
                            opacity: hov.hovered ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: M.dur } }
                            text: "+"
                            color: plusHov.hovered ? M.text : mlive.accent
                            font.family: M.fontDisplay; font.bold: true
                            font.pixelSize: 17 * face.u
                            Layout.rightMargin: 2 * face.u
                            HoverHandler { id: plusHov; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: { addSheet.calendars = root.writable; addSheet.openFor(root.shownDay) } }
                        }
                    }

                    Text {
                        style: Text.Outline; styleColor: M.textOutline   // 1px outline, kit token
                        id: numeral
                        text: root.shownDay.getDate()
                        color: M.text
                        font.family: M.fontDisplay; font.bold: true
                        font.pixelSize: M.hero * face.u
                        font.features: ({ "tnum": 1 })
                        Layout.topMargin: -4 * face.u
                        Layout.bottomMargin: -2 * face.u
                        TapHandler { onTapped: root.picked = null }
                        HoverHandler { cursorShape: root.showingToday ? Qt.ArrowCursor : Qt.PointingHandCursor }
                    }

                    // ---- agenda
                    Item {
                        id: agenda
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        readonly property real rowH: 25 * face.u
                        readonly property int fit: Math.max(1, Math.floor((height + 2 * face.u) / rowH))
                        readonly property int total: root.dayEvents.length
                        readonly property int shown: total > fit ? fit - 1 : total

                        // not connected / sign-in problem: say what to do, plainly
                        Column {
                            visible: root.cal.state === "setup" || root.cal.state === "auth"
                                     || root.cal.state === "loading"
                            width: parent.width
                            spacing: 2 * face.u
                            Text {
                                style: Text.Outline; styleColor: M.textOutline   // 1px outline, kit token
                                text: root.cal.state === "auth" ? "iCloud sign-in failed"
                                    : root.cal.state === "loading" ? "Loading…" : "Connect iCloud"
                                color: M.text
                                font.family: M.fontBody; font.weight: Font.DemiBold
                                font.pixelSize: M.body * face.u
                            }
                            Text {
                                style: Text.Outline; styleColor: M.textOutline   // 1px outline, kit token
                                width: parent.width
                                visible: root.cal.state !== "loading"
                                text: root.cal.state === "auth" ? "Replace the app password in KWallet"
                                                                : "run icloud-calendar.py\u00a0--setup"
                                wrapMode: Text.Wrap
                                color: M.dim
                                font.family: M.fontMono
                                font.pixelSize: M.tertiary * face.u
                            }
                        }

                        Column {
                            visible: !(root.cal.state === "setup" || root.cal.state === "auth"
                                       || root.cal.state === "loading")
                            width: parent.width
                            spacing: 0

                            Repeater {
                                model: root.dayEvents.slice(0, agenda.shown)
                                delegate: Item {
                                    required property var modelData
                                    width: agenda.width
                                    height: agenda.rowH

                                    Rectangle {   // the calendar's own colour, Apple-style
                                        id: bar
                                        x: 0; y: 3 * face.u
                                        width: 2.6 * face.u
                                        height: parent.height - 7 * face.u
                                        radius: width / 2
                                        color: modelData.color
                                        antialiasing: true
                                    }
                                    Column {
                                        anchors.left: bar.right; anchors.leftMargin: 6 * face.u
                                        anchors.right: parent.right
                                        y: 2 * face.u
                                        spacing: 1 * face.u
                                        Text {
                                            style: Text.Outline; styleColor: M.textOutline   // 1px outline, kit token
                                            width: parent.width
                                            text: modelData.title
                                            elide: Text.ElideRight
                                            color: M.text
                                            font.family: M.fontBody; font.weight: Font.DemiBold
                                            font.pixelSize: M.body * face.u
                                        }
                                        Text {
                                            style: Text.Outline; styleColor: M.textOutline   // 1px outline, kit token
                                            width: parent.width
                                            text: root.timeLabel(modelData)
                                                  + (modelData.location ? "  ·  " + modelData.location : "")
                                            elide: Text.ElideRight
                                            color: M.dim
                                            font.family: M.fontMono
                                            font.pixelSize: M.tertiary * face.u
                                            font.letterSpacing: M.tertiaryTrack * face.u
                                        }
                                    }
                                    TapHandler { onTapped: Qt.openUrlExternally("https://www.icloud.com/calendar/") }
                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                }
                            }

                            Text {   // Apple's "+2 more"
                                style: Text.Outline; styleColor: M.textOutline   // 1px outline, kit token
                                visible: agenda.total > agenda.shown
                                text: "+" + (agenda.total - agenda.shown) + " more"
                                color: M.dim
                                font.family: M.fontMono
                                font.pixelSize: M.tertiary * face.u
                                leftPadding: 8.6 * face.u
                                topPadding: 3 * face.u
                            }

                            // nothing (left) on this day
                            Column {
                                visible: agenda.total === 0
                                width: agenda.width
                                spacing: 2 * face.u
                                topPadding: 2 * face.u
                                Text {
                                    style: Text.Outline; styleColor: M.textOutline   // 1px outline, kit token
                                    text: root.showingToday ? "No more events today" : "No events"
                                    color: M.dim
                                    font.family: M.fontBody; font.weight: Font.Medium
                                    font.pixelSize: M.body * face.u
                                }
                                Text {   // ... and what is next, so the space still says something
                                    style: Text.Outline; styleColor: M.textOutline   // 1px outline, kit token
                                    visible: root.showingToday && root.nextEvent !== null
                                    width: agenda.width
                                    elide: Text.ElideRight
                                    text: root.nextEvent
                                          ? root.dayWord(new Date(root.nextEvent.start)).toUpperCase()
                                            + "  ·  " + root.nextEvent.title
                                          : ""
                                    color: M.dim
                                    font.family: M.fontMono
                                    font.pixelSize: M.tertiary * face.u
                                    font.letterSpacing: M.tertiaryTrack * face.u
                                }
                            }
                        }
                    }
                }

                // ---------------------------------------------- right: the month
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 2 * face.u

                    readonly property date month: new Date(root.shownDay.getFullYear(),
                                                           root.shownDay.getMonth(), 1)

                    Text {
                        style: Text.Outline; styleColor: M.textOutline   // 1px outline, kit token
                        text: Qt.formatDate(parent.month, "MMMM").toUpperCase()
                        color: M.dim
                        font.family: M.fontMono; font.bold: true
                        font.pixelSize: M.tertiary * face.u
                        font.letterSpacing: M.eyebrowTrack
                        Layout.leftMargin: 3 * face.u
                    }

                    Grid {
                        id: grid
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        columns: 7
                        readonly property date month: parent.month
                        readonly property int first: Qt.locale().firstDayOfWeek % 7
                        readonly property int lead: (month.getDay() - first + 7) % 7
                        readonly property int days: new Date(month.getFullYear(), month.getMonth() + 1, 0).getDate()
                        readonly property int rows: Math.ceil((lead + days) / 7)
                        readonly property real cw: width / 7
                        readonly property real ch: height / (rows + 1)

                        // weekday initials
                        Repeater {
                            model: 7
                            delegate: Text {
                                style: Text.Outline; styleColor: M.textOutline   // 1px outline, kit token
                                required property int index
                                width: grid.cw; height: grid.ch
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                text: Qt.locale().dayName((grid.first + index) % 7, Locale.NarrowFormat)
                                color: M.text      // was --dim @ .75: invisible on a light wallpaper
                                font.family: M.fontMono; font.bold: true
                                font.pixelSize: (M.tertiary - 1.5) * face.u
                            }
                        }

                        Repeater {
                            model: grid.rows * 7
                            delegate: Item {
                                required property int index
                                readonly property int dnum: index - grid.lead + 1
                                readonly property bool real: dnum >= 1 && dnum <= grid.days
                                readonly property date d: new Date(grid.month.getFullYear(),
                                                                   grid.month.getMonth(), dnum)
                                readonly property bool isToday: real && root.sameDay(d, root.now)
                                readonly property bool isPicked: real && root.picked !== null
                                                                 && root.sameDay(d, root.picked)
                                readonly property var dot: real ? root.dotMap[root.key(d)] : undefined
                                width: grid.cw; height: grid.ch

                                Rectangle {   // today: filled accent disc
                                    anchors.centerIn: parent
                                    // toned down 0.92 -> 0.72 (2026-10-06): it crowded its neighbours
                                    width: Math.min(parent.width, parent.height) * 0.72; height: width
                                    radius: width / 2
                                    visible: isToday || isPicked
                                    color: isToday ? mlive.accent : "transparent"
                                    border.width: isPicked && !isToday ? Math.max(1, 1.2 * face.u) : 0
                                    border.color: mlive.accent
                                    antialiasing: true
                                }
                                Text {
                                    // no outline on the filled disc: a dark glyph with a black
                                    // ring smears into a blob ("6" read as "8")
                                    style: isToday ? Text.Normal : Text.Outline; styleColor: M.textOutline
                                    anchors.centerIn: parent
                                    anchors.verticalCenterOffset: dot !== undefined && !isToday ? -1 * face.u : 0
                                    visible: real
                                    text: dnum
                                    // the accent rule: a glyph on a filled accent takes --bg
                                    color: isToday ? M.bg : M.text
                                    font.family: M.fontBody
                                    font.weight: isToday ? Font.Bold : Font.Medium
                                    font.pixelSize: (isToday ? 8.5 : 9.5) * face.u
                                    font.features: ({ "tnum": 1 })
                                }
                                Rectangle {   // a day with events
                                    visible: dot !== undefined && !isToday
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: parent.height * 0.02
                                    width: 2.4 * face.u; height: width; radius: width / 2
                                    color: dot !== undefined ? dot : "transparent"
                                    antialiasing: true
                                }
                                TapHandler {
                                    enabled: real
                                    onTapped: root.picked = isToday ? null : root.dayStart(d)
                                }
                                HoverHandler { enabled: real; cursorShape: Qt.PointingHandCursor }
                            }
                        }
                    }
                }
            }
        }
    }
}
