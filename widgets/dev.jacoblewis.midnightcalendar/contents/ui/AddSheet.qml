/*
 * The "+" sheet: add an event to an iCloud calendar.
 *
 * Same window architecture as the weather and type sheets — a screen-sized frameless
 * Window with a dismiss scrim, Windowed (never FullScreen: VRR/HDR mode flash). Unlike
 * the frameless desktop face, a SHEET is a lit surface and keeps a solid --panel card.
 *
 * Writing is done by icloud-calendar.py --add, handed ONE argument:
 * encodeURIComponent(JSON) with ' escaped, inside single quotes — an alphabet that cannot
 * break out of the shell, so a title is always just text.
 */
import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasma5support as Plasma5Support
import "Midnight.js" as M

Window {
    id: sheet

    // ⚠️ EXPLICIT SIZE IS REQUIRED — an unsized Window maps as a 0x0 surface and never shows.
    width: Screen.width
    height: Screen.height
    property bool up: false
    property bool shown: false
    visibility: up ? Window.Windowed : Window.Hidden
    color: "transparent"
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
    title: "MidnightCalendarAdd"

    property var calendars: []          // writable ones, from calendar.json
    property real u: 1.25
    signal added()

    // form state
    property date day: new Date()
    property string calName: ""
    property bool allDay: false
    property string busy: ""            // "" | "saving"
    property string error: ""

    function pad(n) { return (n < 10 ? "0" : "") + n }
    function fmt(h, m) {
        var ap = h < 12 ? "AM" : "PM", hh = h % 12 === 0 ? 12 : h % 12
        return hh + ":" + pad(m) + " " + ap
    }
    // "7", "7pm", "7:30 pm", "19:30", "730p" -> minutes after midnight, or -1
    function parseTime(t) {
        var m = String(t).trim().toLowerCase().replace(/\./g, "")
            .match(/^(\d{1,2})(?::?(\d{2}))?\s*([ap])?m?$/)
        if (!m) return -1
        var h = parseInt(m[1]), mi = m[2] ? parseInt(m[2]) : 0
        if (mi > 59 || h > 23) return -1
        if (m[3]) { if (h > 12 || h === 0) return -1; h = (h % 12) + (m[3] === "p" ? 12 : 0) }
        return h * 60 + mi
    }

    function openFor(d) {
        var today = new Date()
        day = new Date(d.getFullYear(), d.getMonth(), d.getDate())
        var startMin = 9 * 60
        if (day.toDateString() === today.toDateString())
            startMin = Math.min(23 * 60, (today.getHours() + 1) * 60)
        startField.text = fmt(Math.floor(startMin / 60), startMin % 60)
        endField.text = fmt(Math.floor((startMin + 60) / 60) % 24, (startMin + 60) % 60)
        titleField.text = ""; locField.text = ""
        allDay = false; error = ""; busy = ""
        if (!calName || !calendars.some(function (c) { return c.name === calName }))
            calName = calendars.length ? calendars[0].name : ""
        up = true; shown = true
        requestActivate()
        titleField.forceActiveFocus()
    }
    function closeDown() { shown = false; hideTimer.restart() }
    Timer { id: hideTimer; interval: 240; onTriggered: if (!sheet.shown) sheet.up = false }

    function submit() {
        if (busy) return
        error = ""
        if (!titleField.text.trim()) { error = "Give it a title"; titleField.forceActiveFocus(); return }
        if (!calName) { error = "No writable calendar"; return }
        var s = new Date(day), e = new Date(day)
        if (allDay) {
            e.setDate(e.getDate() + 1)
        } else {
            var a = parseTime(startField.text), b = parseTime(endField.text)
            if (a < 0) { error = "Start time? e.g. 7:30 PM"; return }
            if (b < 0) { error = "End time? e.g. 8:30 PM"; return }
            s.setHours(0, a, 0, 0); e.setHours(0, b, 0, 0)
            if (b <= a) e.setDate(e.getDate() + 1)   // runs past midnight
        }
        var ev = { title: titleField.text.trim(), cal: calName, allDay: allDay,
                   start: s.getTime(), end: e.getTime(), location: locField.text.trim() }
        var arg = encodeURIComponent(JSON.stringify(ev)).replace(/'/g, "%27")
        busy = "saving"
        runner.connectSource("/usr/bin/python3 '" + Qt.resolvedUrl("../code/icloud-calendar.py").toString().replace("file://", "") + "' --add '"
                             + arg + "'")
    }

    Plasma5Support.DataSource {
        id: runner
        engine: "executable"; connectedSources: []
        onNewData: function (source, data) {
            disconnectSource(source)
            sheet.busy = ""
            var out = String(data["stdout"] || "").trim().split("\n").pop()
            try {
                var r = JSON.parse(out)
                if (r.ok) { sheet.added(); sheet.closeDown(); return }
                sheet.error = r.error || "Could not add the event"
            } catch (e) {
                var err = String(data["stderr"] || "").trim().split("\n").pop()
                sheet.error = err ? err.slice(0, 90) : "Could not add the event"
            }
        }
    }

    // ---------------------------------------------------------------- scrim
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.62)
        opacity: sheet.shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 180 } }
        MouseArea { anchors.fill: parent; onClicked: sheet.closeDown() }
    }

    // ---------------------------------------------------------------- card
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 360 * sheet.u
        height: form.implicitHeight + 40 * sheet.u
        radius: 18 * sheet.u
        color: M.panel
        border.width: 1; border.color: M.a("#FFFFFF", 0.12)
        antialiasing: true
        opacity: sheet.shown ? 1 : 0
        scale: sheet.shown ? 1 : 0.97
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        MouseArea { anchors.fill: parent }          // clicks on the card must not dismiss

        Keys.onEscapePressed: sheet.closeDown()

        ColumnLayout {
            id: form
            anchors.fill: parent
            anchors.margins: 20 * sheet.u
            spacing: 12 * sheet.u

            Text {
                text: "NEW EVENT"
                color: M.accent
                font.family: M.fontMono; font.bold: true
                font.pixelSize: M.tertiary * sheet.u
                font.letterSpacing: M.eyebrowTrack
            }

            component Field: QQC2.TextField {
                Layout.fillWidth: true
                color: M.text
                placeholderTextColor: M.a(M.dim, 0.7)
                selectionColor: M.accent
                selectedTextColor: M.bg
                font.family: M.fontBody
                font.pixelSize: 13 * sheet.u
                leftPadding: 12 * sheet.u; rightPadding: 12 * sheet.u
                // ⚠️ implicitHeight ON THE BACKGROUND, or the field gets no hit area and
                // cannot be clicked into (the booth-message / volume-slider trap).
                background: Rectangle {
                    implicitHeight: 34 * sheet.u
                    implicitWidth: 120 * sheet.u
                    radius: 10 * sheet.u
                    color: M.a("#FFFFFF", 0.05)
                    border.width: 1
                    border.color: parent.activeFocus ? M.accent : M.a("#FFFFFF", 0.12)
                }
                Keys.onReturnPressed: sheet.submit()
                Keys.onEnterPressed: sheet.submit()
                Keys.onEscapePressed: sheet.closeDown()
            }

            Field { id: titleField; placeholderText: "Title"; font.pixelSize: 15 * sheet.u; font.weight: Font.DemiBold }

            // calendar chips, each in its own iCloud colour
            Flow {
                Layout.fillWidth: true
                spacing: 6 * sheet.u
                Repeater {
                    model: sheet.calendars
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool on: sheet.calName === modelData.name
                        height: 26 * sheet.u
                        width: chipRow.implicitWidth + 20 * sheet.u
                        radius: height / 2
                        color: on ? M.a(modelData.color, 0.28) : M.a("#FFFFFF", 0.05)
                        border.width: 1
                        border.color: on ? modelData.color : M.a("#FFFFFF", 0.10)
                        antialiasing: true
                        Row {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: 6 * sheet.u
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 7 * sheet.u; height: width; radius: width / 2
                                color: modelData.color
                            }
                            Text {
                                text: modelData.name
                                color: on ? M.text : M.dim
                                font.family: M.fontBody; font.pixelSize: 11.5 * sheet.u
                                font.weight: on ? Font.DemiBold : Font.Normal
                            }
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: sheet.calName = modelData.name }
                    }
                }
            }

            // date row: ‹ Tue, Oct 6 ›   [All day]
            RowLayout {
                Layout.fillWidth: true
                spacing: 8 * sheet.u
                component Arrow: Text {
                    property int step: 1
                    text: step < 0 ? "‹" : "›"
                    color: M.dim
                    font.family: M.fontBody; font.pixelSize: 20 * sheet.u
                    MouseArea { anchors.fill: parent; anchors.margins: -6
                                cursorShape: Qt.PointingHandCursor
                                onClicked: sheet.day = new Date(sheet.day.getFullYear(),
                                                                sheet.day.getMonth(),
                                                                sheet.day.getDate() + parent.step) }
                }
                Arrow { step: -1 }
                Text {
                    text: Qt.formatDate(sheet.day, "ddd, MMM d")
                    color: M.text
                    font.family: M.fontBody; font.weight: Font.DemiBold
                    font.pixelSize: 13 * sheet.u
                    Layout.minimumWidth: 92 * sheet.u
                    horizontalAlignment: Text.AlignHCenter
                }
                Arrow { step: 1 }
                Item { Layout.fillWidth: true }
                Rectangle {
                    height: 26 * sheet.u
                    width: adTxt.implicitWidth + 22 * sheet.u
                    radius: height / 2
                    color: sheet.allDay ? M.accent : M.a("#FFFFFF", 0.05)
                    border.width: sheet.allDay ? 0 : 1
                    border.color: M.a("#FFFFFF", 0.12)
                    Text {
                        id: adTxt
                        anchors.centerIn: parent
                        text: "All day"
                        // the accent rule: a glyph on a filled accent takes --bg
                        color: sheet.allDay ? M.bg : M.dim
                        font.family: M.fontBody; font.weight: Font.DemiBold
                        font.pixelSize: 11.5 * sheet.u
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: sheet.allDay = !sheet.allDay }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: !sheet.allDay
                spacing: 8 * sheet.u
                Field { id: startField; placeholderText: "Start" }
                Text { text: "–"; color: M.dim; font.pixelSize: 13 * sheet.u }
                Field { id: endField; placeholderText: "End" }
            }

            Field { id: locField; placeholderText: "Location (optional)" }

            Text {
                Layout.fillWidth: true
                visible: sheet.error !== ""
                text: sheet.error
                wrapMode: Text.Wrap
                color: M.red
                font.family: M.fontMono; font.pixelSize: 10 * sheet.u
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 2 * sheet.u
                spacing: 8 * sheet.u
                Item { Layout.fillWidth: true }
                Rectangle {
                    height: 32 * sheet.u; width: cTxt.implicitWidth + 28 * sheet.u
                    radius: height / 2
                    color: cMa.containsMouse ? M.a("#FFFFFF", 0.10) : M.a("#FFFFFF", 0.05)
                    Text { id: cTxt; anchors.centerIn: parent; text: "Cancel"; color: M.dim
                           font.family: M.fontBody; font.pixelSize: 12.5 * sheet.u }
                    MouseArea { id: cMa; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor; onClicked: sheet.closeDown() }
                }
                Rectangle {
                    height: 32 * sheet.u; width: aTxt.implicitWidth + 32 * sheet.u
                    radius: height / 2
                    color: M.accent
                    opacity: sheet.busy ? 0.6 : 1
                    scale: aMa.pressed ? M.pressScale : (aMa.containsMouse ? 1.03 : 1)
                    Behavior on scale { NumberAnimation { duration: M.durFast } }
                    Text { id: aTxt; anchors.centerIn: parent
                           text: sheet.busy ? "Adding…" : "Add Event"
                           color: M.bg
                           font.family: M.fontBody; font.weight: Font.Bold
                           font.pixelSize: 12.5 * sheet.u }
                    MouseArea { id: aMa; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor; onClicked: sheet.submit() }
                }
            }
        }
    }
}
