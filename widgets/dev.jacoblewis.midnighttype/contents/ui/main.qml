// Midnight Type — KDE plasmoid
//
// A TypeRacer-style typing race on the desktop, wearing the same design language
// as the Midnight Radio page and widget: the page's five themes,
// its glass card + filled-pill vocabulary, JetBrains Mono for anything numeric,
// Inter for display type.
//
// Architecture is deliberately the SAME SHAPE as Midnight Radio: a fixed-spec
// pill in the desktop containment (so the two corners line up), and the real UI
// in its own screen-sized frameless Window rather than a Plasma popup. That is
// not decoration — a race needs real keyboard focus, and a popup that the shell
// sizes and places cannot reliably give it (see the Window comments below).
import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtQuick.Effects
import QtCore
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import "quotes.js" as Quotes
import "Midnight.js" as M

PlasmoidItem {
    id: root
    // album colour + away state for this widget (Live.qml)
    Live { id: mlive }

    // ⚠️ TEXT-ONLY SCALE. Container/glyph metrics stay on u and gu — only
    // font.pixelSize is multiplied by this, so shrinking type never reflows
    // the pills. 32in 4K at scale 1.5 made the stock sizes read large.
    readonly property real fs: 0.88

    // ---------------------------------------------------------------- themes
    // EXACT hexes from the radio page's :root blocks, identical to the Midnight
    // Radio widget's map, so all three surfaces are the same product.
    // {a: accent, d: dim, p: pale, bg, panel, pop}. --red is shared by every
    // theme (errors here, live/love there).
    readonly property var themes: ({
        "glass": { a: "#9A8CFF", d: "#A8B2C8", p: "#FFFFFF", bg: "#05060A", panel: "#1D2336", pop: "#00E5B0", label: "Prism" }
    })
    readonly property var themeOrder: ["glass"]

    Settings {
        id: prefs
        category: "MidnightType"
        property string theme: "glass"   // matches Midnight Weather
        property string band: "medium"        // short | medium | long
        property int    bestWpm: 0
        property int    bestAcc: 0
        property string history: "[]"         // last 20 races, newest last
    }
    property string theme: themeOrder.indexOf(prefs.theme) >= 0 ? prefs.theme : "glass"

    readonly property var   pal: themes[theme]
    readonly property color cAccent: mlive.accent
    readonly property color cDim:    pal.d
    readonly property color cPale:   pal.p
    readonly property color cBg:     pal.bg
    readonly property color cPop:    pal.pop
    readonly property color cRed:    "#ff2b3d"
    // ⚠️ pal.* are STRINGS from the JS map. Assigning a string to a `color`
    // property parses it, but `pal.a.r` is UNDEFINED and Qt.rgba(undefined, …)
    // is transparent — which silently erases fills, borders and every tint. So
    // every alpha derives from these real `color` properties, never from pal.*.
    readonly property color cPanel:   pal.panel
    readonly property color cSheet:   Qt.rgba(cPanel.r, cPanel.g, cPanel.b, 0.97)
    readonly property color cGlass:   Qt.rgba(cPanel.r, cPanel.g, cPanel.b, 0.72)
    readonly property color cEdge:    Qt.rgba(cAccent.r, cAccent.g, cAccent.b, 0.18)  // = --border
    readonly property color cEdgeHi:  Qt.rgba(cAccent.r, cAccent.g, cAccent.b, 0.42)  // = --border-bright
    // The white hairline every Midnight surface carries on its outer edge.
    // Was inlined as a literal in several places, which is how a shared value
    // drifts; the wallpaper and the weather pill already had it as a token.
    readonly property color cHair:    Qt.rgba(1, 1, 1, 0.20)
    readonly property color cOutline: Qt.rgba(0, 0, 0, 0.45)
    function accentA(a) { return Qt.rgba(cAccent.r, cAccent.g, cAccent.b, a) }
    function popA(a)    { return Qt.rgba(cPop.r, cPop.g, cPop.b, a) }
    function redA(a)    { return Qt.rgba(1, 0.169, 0.239, a) }   // --red #ff2b3d


    // The single scale unit for the card. Hoisted to root (rather than living on
    // the card, as it does in Midnight Radio) so the inline components declared
    // below can reach it — an inline component only sees root-level scope.
    readonly property real gu: Kirigami.Units.gridUnit * 1.3

    // ------------------------------------------------------------- race model
    property string quote: ""
    property string author: ""
    property var    words: []            // [{t: "word ", s: startIndex}] for the Flow
    property string typed: ""
    property string phase: "idle"        // idle | count | race | done
    property int    countdown: 3
    property bool   started: false       // clock running (first keystroke landed)
    property double startMs: 0
    property int    elapsedMs: 0
    property int    keystrokes: 0        // every printable key, including mistakes
    property int    errors: 0            // keys that did not match at the time
    property int    lastWpm: 0
    property int    lastAcc: 0
    property int    pbDelta: 0           // vs the previous personal best

    // ⚠️ These read `typed`/`quote` inside a called function on purpose — QML
    // tracks property reads through the call, so the binding stays live.
    function countCorrect() {
        var n = 0
        var lim = Math.min(typed.length, quote.length)
        for (var i = 0; i < lim; i++) if (typed.charAt(i) === quote.charAt(i)) n++
        return n
    }
    readonly property int  correctChars: countCorrect()
    readonly property real progress: quote.length ? Math.min(1, typed.length / quote.length) : 0
    readonly property real minutes: Math.max(elapsedMs, 1) / 60000
    // NET wpm: only characters that are actually right count toward the word
    // total, so leaving a wrong letter behind costs you rather than paying you.
    readonly property int  wpm: started ? Math.max(0, Math.round((correctChars / 5) / minutes)) : 0
    readonly property int  acc: keystrokes ? Math.round(100 * (keystrokes - errors) / keystrokes) : 100
    // The pace ghost: where your personal best would be on this passage right
    // now. Hidden until you have set a best, and while the clock is stopped.
    //
    // ⚠️ The pace is SNAPSHOT at the start of the race (ghostWpm), not read live
    // off prefs.bestWpm. Reading it live meant that the moment you beat your
    // best, finishRace() raised the bar and the ghost teleported forward to sit
    // under your own marker — so the one race where the ghost matters most was
    // the one race where it lied about what you had beaten.
    property int ghostWpm: 0
    readonly property bool hasGhost: ghostWpm > 0 && started && quote.length > 0
    readonly property real ghostProgress: hasGhost
        ? Math.min(1, (ghostWpm * 5 * minutes) / quote.length) : 0

    // 0 = untyped, 1 = correct, 2 = wrong. Read per character by the Flow.
    function charState(i) {
        if (i >= typed.length) return 0
        return typed.charAt(i) === quote.charAt(i) ? 1 : 2
    }

    // Split into words with their trailing space attached, so the Flow wraps at
    // real word boundaries. Wrapping per CHARACTER (the obvious first attempt)
    // breaks words across lines and makes the passage unreadable to type from.
    function buildWords(q) {
        var out = [], i = 0
        while (i < q.length) {
            var j = q.indexOf(" ", i)
            var end = (j < 0) ? q.length : j + 1     // the space rides with its word
            out.push({ t: q.substring(i, end), s: i })
            i = end
        }
        return out
    }

    function loadQuote() {
        var q = Quotes.pick(prefs.band, root.quote)
        root.quote  = q.t
        root.author = q.a
        root.words  = buildWords(q.t)
        root.typed  = ""
    }

    function resetRace() {
        countTimer.stop()
        phase = "idle"; typed = ""; started = false
        elapsedMs = 0; keystrokes = 0; errors = 0
    }

    function startRace(fresh) {
        if (fresh || !quote) loadQuote()
        typed = ""; started = false; elapsedMs = 0
        keystrokes = 0; errors = 0
        ghostWpm = prefs.bestWpm            // the bar as it stood when you set off
        countdown = 3
        phase = "count"
        countTimer.restart()
        keyCatcher.forceActiveFocus()
    }

    function beginClock() {
        startMs = Date.now()
        elapsedMs = 0
        started = true
    }

    function finishRace() {
        elapsedMs = Date.now() - startMs
        phase = "done"
        lastWpm = wpm                    // read AFTER elapsedMs so the binding is settled
        lastAcc = acc
        pbDelta = lastWpm - prefs.bestWpm
        if (lastWpm > prefs.bestWpm) { prefs.bestWpm = lastWpm; prefs.bestAcc = lastAcc }
        pushHistory(lastWpm, lastAcc)
    }

    // -------------------------------------------------------------- history
    // Stored as a JSON string in Settings (QtCore Settings has no list type).
    readonly property var raceHistory: {
        try { var h = JSON.parse(prefs.history); return Array.isArray(h) ? h : [] }
        catch (e) { return [] }
    }
    function pushHistory(w, a) {
        var h = raceHistory.slice()
        h.push({ w: w, a: a, t: Math.floor(Date.now() / 1000) })
        while (h.length > 20) h.shift()
        prefs.history = JSON.stringify(h)
    }
    readonly property int lastRaceWpm: raceHistory.length ? raceHistory[raceHistory.length - 1].w : 0

    // ---------------------------------------------------------------- timers
    Timer {
        id: countTimer
        interval: 700; repeat: true
        onTriggered: {
            root.countdown--
            if (root.countdown < 0) { stop(); root.phase = "race" }
        }
    }
    // 60ms is fast enough that the live WPM reads as continuous without spending
    // a frame budget on it; the clock itself is wall time, not a tick count, so
    // a dropped tick never skews the result.
    Timer {
        interval: 60; repeat: true
        running: root.phase === "race" && root.started
        onTriggered: root.elapsedMs = Date.now() - root.startMs
    }

    // ------------------------------------------------------------ key input
    function handleKey(e) {
        if (e.key === Qt.Key_Escape) {
            e.accepted = true
            raceWindow.closeDown()
            return
        }
        // Tab always deals a fresh passage, the muscle memory from every other
        // typing trainer. Accepting it also stops Tab walking the focus chain.
        if (e.key === Qt.Key_Tab) { e.accepted = true; root.startRace(true); return }

        if (root.phase === "idle" || root.phase === "done") {
            if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) {
                e.accepted = true
                root.startRace(root.phase === "done")   // a finished race deals a new passage
            }
            return
        }
        if (root.phase === "count") { e.accepted = true; return }   // swallow the false start

        if (e.key === Qt.Key_Backspace) {
            e.accepted = true
            if (!root.typed.length) return
            if (e.modifiers & Qt.ControlModifier) {
                // ctrl+backspace: back to the start of the current word
                var s = root.typed.replace(/\s+$/, "")
                var k = s.lastIndexOf(" ")
                root.typed = k < 0 ? "" : s.substring(0, k + 1)
            } else {
                root.typed = root.typed.slice(0, -1)
            }
            return
        }

        if (e.text && e.text.length === 1) {
            var code = e.text.charCodeAt(0)
            if (code < 32 || code > 126) return          // control keys, dead keys, unicode
            e.accepted = true
            if (root.typed.length >= root.quote.length) return
            if (!root.started) root.beginClock()
            root.keystrokes++
            if (e.text !== root.quote.charAt(root.typed.length)) root.errors++
            root.typed += e.text
            if (root.typed.length === root.quote.length) root.finishRace()
        }
    }

    // ---------------------------------------------------------------- arcade
    // This widget is the desktop's play surface, so the Spider Solitaire page is
    // launched from here — it does not belong in the radio or weather pill.

    // Set to a Spider Solitaire page to get the arcade button; empty hides it.
    readonly property string spiderUrl: ""

    // Also on the pill's right-click menu, so it needs no card opened first.
    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: "Spider Solitaire"
            visible: root.spiderUrl !== ""
            icon.name: "applications-games"
            onTriggered: Qt.openUrlExternally(root.spiderUrl)
        }
    ]

    // ------------------------------------------------------ inline components
    // Declared at root level so they can see root.gu and the palette. Qt 6
    // inline components — one definition, used by every button on the card.

    // The page's two button weights: a solid --pop CTA (`.btn-req`) and a
    // ghost accent-tinted secondary. ⚠️ `enabled` is a real Item property, so
    // the on/off flag is `active` — shadowing `enabled` would also kill the
    // MouseArea underneath it.
    // A round icon button sized for the pill. Same vocabulary as GlassBtn — accent
    // tint, hairline, press-scale — but square and icon-only, because 25u is the
    // whole budget the pill has to spare.
    component ArcadeBtn: Rectangle {
        id: ab
        property string icon: ""
        property string tip: ""
        property bool on: false          // the action is currently active
        property bool busy: false
        // ⚠️ SIZE IS PASSED IN, not derived from compactRoot.u. An inline
        // component is its own scope and can only see the FILE ROOT's ids —
        // referencing compactRoot here is an unresolvable name at load time,
        // which QML reports as nothing at all (the widget just fails to load).
        property real cell: 32
        readonly property alias hovered: abM.containsMouse
        signal tapped()

        width: cell
        height: width
        radius: width / 2
        antialiasing: true
        opacity: busy ? 0.45 : 1
        scale: abM.pressed && !busy ? 0.90 : 1
        Behavior on scale { NumberAnimation { duration: 90 } }
        // A filled surface takes its glyph in the contrast colour — the page's
        // rule. `on` is the only state that fills, so live reads at a glance.
        color: on ? root.cPop
                  : (abM.containsMouse ? root.accentA(0.16) : root.accentA(0.07))
        border.width: 1
        border.color: on ? "transparent"
                         : (abM.containsMouse ? root.cAccent : root.cEdgeHi)
        Behavior on color { ColorAnimation { duration: 120 } }

        // ⚠️ isMask is REQUIRED to recolour: without it this icon theme renders
        // its media glyphs in their own colour and ignores `color` entirely.
        Kirigami.Icon {
            anchors.centerIn: parent
            width: parent.width * 0.56; height: width
            source: ab.icon
            isMask: true
            color: ab.on ? root.cBg
                         : (abM.containsMouse ? root.cPop : root.cAccent)
        }
        MouseArea {
            id: abM
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: ab.busy ? Qt.ArrowCursor : Qt.PointingHandCursor
            onClicked: if (!ab.busy) ab.tapped()
        }
        QQC2.ToolTip.visible: abM.containsMouse && ab.tip !== ""
        QQC2.ToolTip.text: ab.tip
    }

    component GlassBtn: Rectangle {
        id: gb
        property string label: ""
        property bool primary: false
        property bool active: true
        signal tapped()

        implicitWidth: gbTxt.implicitWidth + root.gu * 1.5
        implicitHeight: root.gu * 1.7
        radius: height / 2
        antialiasing: true
        opacity: active ? 1 : 0.38
        scale: gbM.pressed && active ? 0.95 : 1
        Behavior on scale { NumberAnimation { duration: 90 } }
        color: primary
               ? (gbM.containsMouse && active ? Qt.lighter(root.cPop, 1.12) : root.cPop)
               : (gbM.containsMouse && active ? root.accentA(0.14) : root.accentA(0.06))
        border.width: 1
        border.color: primary ? "transparent"
                              : (gbM.containsMouse && active ? root.cAccent : root.cEdge)
        Behavior on color { ColorAnimation { duration: 120 } }

        Text {
            style: Text.Outline; styleColor: M.textOutline   // 1px outline, kit token
            id: gbTxt
            anchors.centerIn: parent
            text: gb.label
            // A filled surface takes its glyph in the contrast colour, never in
            // the accent — the page's rule, applied here to the pop CTA.
            color: gb.primary ? root.cBg
                              : (gbM.containsMouse && gb.active ? root.cPop : root.cDim)
            font.family: "JetBrains Mono"
            font.bold: true
            font.pixelSize: (root.gu * 0.5) * root.fs
            font.letterSpacing: 1.2
        }
        MouseArea {
            id: gbM
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: gb.active ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (gb.active) { gb.tapped(); keyCatcher.forceActiveFocus() }
        }
    }

    // A stat readout: mono label over an Inter numeral. The value colour is the
    // caller's choice so WPM can carry the accent while the rest stay pale.
    component StatCell: Rectangle {
        id: sc
        property string label: ""
        property string value: "—"
        property color  tone: root.cPale
        Layout.fillWidth: true
        Layout.preferredHeight: root.gu * 2.9
        radius: root.gu * 0.5
        color: root.accentA(0.05)
        border.width: 1; border.color: root.cEdge
        antialiasing: true
        Column {
            anchors.centerIn: parent
            spacing: root.gu * 0.05
            Text {
                style: Text.Outline; styleColor: M.textOutline   // 1px outline, kit token
                anchors.horizontalCenter: parent.horizontalCenter
                text: sc.label
                color: root.cDim
                font.family: "JetBrains Mono"; font.pixelSize: (root.gu * 0.42) * root.fs
                font.letterSpacing: 1.6
            }
            Text {
                style: Text.Outline; styleColor: M.textOutline   // 1px outline, kit token
                anchors.horizontalCenter: parent.horizontalCenter
                text: sc.value
                color: sc.tone
                font.family: "Inter"; font.bold: true
                font.pixelSize: (root.gu * 1.15) * root.fs
            }
        }
    }

    // ------------------------------------------------------------ containment
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    switchWidth:  Kirigami.Units.gridUnit * 14
    switchHeight: Kirigami.Units.gridUnit * 10
    // The desktop shows the pill; the race lives in its own window. Without this
    // the containment renders the full representation inline.
    preferredRepresentation: compactRepresentation

    // ------------------------------------------------------------------ pill
    compactRepresentation: Item {
        id: compactRoot
        // slide off the nearest edge while away (AwaySlide.qml)
        AwaySlide { id: away; target: compactRoot; mode: mlive.mode }
        transform: Translate { x: away.dx; y: away.dy }
        opacity: away.fade

        // A HALF-WIDTH sibling of the shared desktop pill: 120u x 50u against
        // the wallpaper's 240u x 50u weather pill, same 50u height, same 16u
        // radius, same fill and hairline. It reads as the small one in a set,
        // not as a different kind of object.
        //
        // ⚠️ `u` comes from HEIGHT here, not width as the radio pill derives it.
        // The radio pill can use width because it IS the full 240u spec; this
        // one is deliberately narrower, so measuring its width against 240
        // would land on u = 0.8 and render everything at half scale. Height is
        // the sound reference precisely because the desktop containment
        // grid-locks applet height (to 80 logical here) — that lock is what
        // makes it a fixed point, and 80 / 50u = the wallpaper's own u = 1.6.
        readonly property real u: Math.max(0.8, Math.min(2.4, height / 50))
        readonly property bool roomy: width > 88 * u     // false in a thin panel

        // ⚠️ Must include the BUTTONS' own hover, not just the pill's. With only
        // pillMouse in this test the row faded out the instant the pointer
        // crossed onto a button — the buttons sit above pillMouse, so entering
        // one leaves the pill, and they would vanish under the cursor before
        // they could be clicked.
        readonly property bool arcadeOpen: pillMouse.containsMouse
                                           || solBtn.hovered

        // ⚠️ Hardcoded, NOT `120 * u` — u is derived from height, so an implicit
        // WIDTH computed from it is circular: before the stored geometry lands,
        // height is 0, u clamps to 0.8, and the pill asks to be 96 wide. Same
        // pattern as the radio pill (which hardcodes 384): these are the 120u
        // x 50u spec resolved at the desktop's u of 1.6, and stored geometry
        // wins over both anyway.
        implicitWidth:  160          // 120u at u = 1.28 = 154, snapped to the 16px grid the containment stores (2026-10-23)
        implicitHeight: 64
          // ⚠️ MEASURED: the stored geometry does NOT win. If this differs from the
        // size in appletsrc, the containment re-places the applet at runtime —
        // that is the whole "placement fight". 50u at the desktop's u of 1.28.

        Rectangle {
            id: pill
            anchors.fill: parent
            // 16u radius + cPanel at .62 (hover .90) + a white hairline that
            // turns accent on hover: copied from the wallpaper's weather pill
            // rather than approximated, so the pair matches exactly.
            radius: 16 * compactRoot.u
            color: "transparent"
            antialiasing: true
            border.width: 0
            border.color: pillMouse.containsMouse ? root.accentA(0.42)
                                                  : root.cHair
            scale: pillMouse.pressed ? M.pressScale : 1
            // the shared hover: a small lift — the app's card bounce, scaled to a pill
            transform: Translate {
                y: (compactRoot.arcadeOpen) ? -M.hoverLift * compactRoot.u : 0
                Behavior on y { NumberAnimation { duration: M.dur; easing.type: Easing.OutCubic } }
            }
            Behavior on color { ColorAnimation { duration: 140 } }
            Behavior on scale { NumberAnimation { duration: 90 } }
            // NO BACKGROUND (2026-10-03, user: "text and album art / clip art only"). The fill,
            // hairline and outline ring are gone; a soft drop shadow on the whole layer keeps the
            // text readable over any part of the wallpaper.
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true; shadowColor: M.shadowColor; shadowOpacity: M.shadowOpacity
                shadowBlur: M.shadowBlur; blurMax: M.shadowBlurMax; shadowVerticalOffset: M.shadowY; shadowHorizontalOffset: 0
                autoPaddingEnabled: true
            }

            // The two-tone edge: a dark ring outside the light hairline so the
            // pill reads on a bright wallpaper as well as a dark one.
            Rectangle {
                visible: false   // (outline ring: no background now)
                anchors.fill: parent
                anchors.margins: -1
                radius: parent.radius + 1
                color: "transparent"
                border.width: 1; border.color: root.cOutline
                antialiasing: true
                z: -1
            }

            // Same internal structure as the weather pill — a glyph, then a
            // two-line column — at its 13u side margin and 12u spacing.
            //
            // ⚠️ SIDE MARGINS ONLY, exactly as the weather pill does it. A
            // symmetric `anchors.margins` looks tidier in the source and is
            // wrong: it left 80 - 2*19.2 = 41.6px of vertical room, which
            // CLAMPED the 32u (51.2px) keycap and squeezed the text block off
            // centre with it. With no vertical margin the row is free at its
            // natural height and the layout centres it.
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 0    // frameless: box edge = content edge (pixel grid, 2026-10-06)
                anchors.rightMargin: 0
                spacing: 12 * compactRoot.u

                // keycap — a literal key, drawn rather than iconified so it
                // takes the theme accent like everything else on the pill.
                Rectangle {
                    Layout.preferredWidth: M.glyph * compactRoot.u
                    Layout.preferredHeight: M.glyph * compactRoot.u
                    Layout.alignment: Qt.AlignVCenter
                    // NO PLATE: clip art only, like the weather glyph beside it. The
                    // keycap's fill + hairline were the last background on the desktop.
                    radius: width * 0.26
                    color: "transparent"
                    border.width: 0
                    antialiasing: true

                    Canvas {
                        anchors.centerIn: parent
                        width: parent.width * 0.78; height: width
                        renderStrategy: Canvas.Cooperative
                        property color col: root.cAccent
                        onColChanged: requestPaint()      // Canvas will not repaint on its own
                        onPaint: {
                            var ctx = getContext("2d"); ctx.reset()
                            var k = width / 24
                            ctx.strokeStyle = col; ctx.lineWidth = 2.6 * k
                            ctx.lineCap = "round"; ctx.lineJoin = "round"
                            // a caret and a baseline: the universal "type here"
                            ctx.beginPath()
                            ctx.moveTo(5 * k, 7 * k); ctx.lineTo(11 * k, 12 * k); ctx.lineTo(5 * k, 17 * k)
                            ctx.stroke()
                            ctx.beginPath()
                            ctx.moveTo(13 * k, 17 * k); ctx.lineTo(19 * k, 17 * k)
                            ctx.stroke()
                        }
                    }
                }

                // ⚠️ The unit rides on the EYEBROW, not beside the numeral. With
                // "72" and "WPM" on one line the column grew with the score and
                // a three-digit best overflowed the pill — the one outcome the
                // widget is designed to produce. This way the column's width is
                // set by the label and the numeral can grow underneath it.
                // ⚠️ OPTICAL CENTRING. A text item's box is much taller than its
                // ink: the numeral carries a full descent under digits that
                // never use one, and the label carries ascent slack above its
                // caps. Centring the BOX therefore leaves the INK sitting high —
                // measured at 11px of space above against 37px below, which is
                // exactly the "not centred" you can see without a ruler.
                //
                // The fix is to make each box equal its ink, via tightBoundingRect
                // (the real inked rect for that string), so that centring the
                // column centres what you actually see. Derived from the font at
                // runtime, so it holds if a size or family ever changes — and the
                // gap between the two lines becomes the column's `spacing`, an
                // honest number, instead of whatever the descents happened to add.
                FontMetrics { id: fmEye; font: eyebrow.font }
                FontMetrics { id: fmNum; font: numeral.font }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 3 * compactRoot.u
                    visible: compactRoot.roomy
                    // Yields this space to the arcade buttons on hover. It stays
                    // in the layout at zero opacity rather than being hidden, so
                    // the keycap beside it never shifts.
                    opacity: compactRoot.arcadeOpen ? 0 : 1
                    Behavior on opacity { NumberAnimation { duration: 130 } }

                    // ⚠️ Both rows need an explicit left alignment: a ColumnLayout
                    // CENTRES any child that does not fill its width, which sat
                    // the label and the numeral in the middle of the column and
                    // left them floating away from the keycap beside them.
                    RowLayout {
                        Layout.alignment: Qt.AlignLeft
                        spacing: 5 * compactRoot.u
                        Text {
                            style: Text.Outline; styleColor: M.textOutline   // 1px outline, kit token
                            id: numeral
                            Layout.preferredHeight: fmNum.tightBoundingRect("8").height
                            verticalAlignment: Text.AlignVCenter
                            text: prefs.bestWpm > 0 ? prefs.bestWpm : "—"
                            color: M.text
                            font.family: M.fontDisplay; font.bold: true
                            // 21u = the shared primary size (weather's
                            // temperature, the radio pill's track title)
                            font.pixelSize: (M.primary * compactRoot.u) * root.fs
                            font.features: ({ "tnum": 1 })
                        }
                        // A terminal caret, breathing: the pill's one moving
                        // part, and the whole widget's idea in three pixels.
                        // Height tracks the DIGITS' ink, so it is a cursor beside
                        // the number rather than a bar of its own height.
                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            width: 3 * compactRoot.u
                            height: fmNum.tightBoundingRect("8").height
                            radius: 1 * compactRoot.u
                            color: root.cAccent
                            antialiasing: true
                            SequentialAnimation on opacity {
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.15; duration: 620; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1.0;  duration: 620; easing.type: Easing.InOutSine }
                            }
                        }
                    }
                    Text {
                        style: Text.Outline; styleColor: M.textOutline   // 1px outline, kit token
                        id: eyebrow
                        Layout.alignment: Qt.AlignLeft
                        // ⚠️ FILLS, so the column can absorb the box's spare width. With every
                        // child fixed-width the RowLayout spread the leftover ~16px AROUND the
                        // column and the text sat right of the weather pill's (2026-10-06).
                        Layout.fillWidth: true
                        Layout.preferredHeight: fmEye.tightBoundingRect(text).height
                        verticalAlignment: Text.AlignVCenter
                        text: prefs.bestWpm > 0 ? "WPM BEST" : "READY"
                        color: root.cDim
                        font.family: M.fontMono
                        // 9u is the shared tertiary size on both desktop pills
                        font.pixelSize: (M.tertiary * compactRoot.u) * root.fs
                        font.letterSpacing: 1.6
                    }
                }
            }

            // The whole pill is the button — at this size there is no room for a
            // separate target, and "click the small pill, race" is the gesture.
            MouseArea {
                id: pillMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { raceWindow.openUp(); root.startRace(true) }
            }
            QQC2.ToolTip.visible: pillMouse.containsMouse && !compactRoot.arcadeOpen
            QQC2.ToolTip.text: prefs.bestWpm > 0
                               ? ("Start a race — best " + prefs.bestWpm + " wpm, "
                                  + root.raceHistory.length + " raced")
                               : "Start a typing race"

            // ------------------------------------------------------- arcade
            // The two things this widget launches besides a race. They live on
            // the PILL, not in the race card: the card is a race surface you
            // have to open first, which is a poor place for shortcuts whose
            // whole point is not making you go somewhere else.
            //
            // ⚠️ DECLARED AFTER pillMouse ON PURPOSE. Later siblings paint and
            // hit-test above earlier ones, so each button's own MouseArea takes
            // the click; without this ordering pillMouse would swallow them and
            // every tap would start a race instead.
            //
            // They occupy the stats column's space rather than adding width:
            // the pill's inner width is ~127 logical, of which the keycap and
            // its spacing take 56, leaving ~70 — which is two 25u buttons and a
            // 4u gap, and nothing more. Growing the pill was the alternative and
            // it would have undone the 20% scale-down it just received.
            Row {
                id: arcadeRow
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: 0
                spacing: 4 * compactRoot.u
                visible: opacity > 0.01 && compactRoot.roomy
                opacity: compactRoot.arcadeOpen ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 130 } }

                ArcadeBtn {
                    id: solBtn
                    cell: 25 * compactRoot.u
                    icon: "applications-games"
                    tip: "Spider Solitaire"
                    visible: root.spiderUrl !== ""
                    onTapped: Qt.openUrlExternally(root.spiderUrl)
                }
            }
        }
    }

    // ⚠️ A Plasma popup is sized and placed by the shell — asking for a large
    // surface gets clamped and the clamped size written back to config. The race
    // therefore lives in its own Window (below) and the full representation is a
    // stub that never shows.
    fullRepresentation: Item { implicitWidth: 1; implicitHeight: 1 }

    // -------------------------------------------- the race, in its own window
    Window {
        id: raceWindow

        // ⚠️ EXPLICIT SIZE IS REQUIRED — an unsized Window gets a 0x0 Wayland
        // surface and silently never maps: no client, no error, nothing.
        width:  Screen.width
        height: Screen.height

        // ⚠️ Windowed, NOT FullScreen. A real fullscreen surface makes KWin
        // engage and drop adaptive sync as it appears and goes; with VRR on
        // Automatic and HDR enabled each of those is a display MODE TRANSITION,
        // which blanks and resets the panel on every open. A screen-sized
        // Windowed surface looks identical and never triggers one.
        //
        // `visibility` ONLY — declaring `visible` as well is a hard "Conflicting
        // properties" warning and the two then fight over the same state.
        property bool up: false          // surface mapped
        property bool shown: false       // fade target
        visibility: up ? Window.Windowed : Window.Hidden

        color: "transparent"
        flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
        title: "MidnightTypeRace"        // unique hook for a KWin rule, if ever needed

        function openUp() {
            raceWindow.up = true
            raceWindow.shown = true
            if (!root.quote) root.loadQuote()
            focusTimer.restart()
        }
        function closeDown() {
            root.resetRace()
            raceWindow.shown = false
            hideTimer.restart()
        }

        // Focus has to be claimed AFTER the surface maps — forcing it in
        // openUp() lands on a window that does not exist yet, and the first
        // keystrokes then go to whatever was focused before.
        Timer {
            id: focusTimer
            interval: 70
            onTriggered: { raceWindow.requestActivate(); keyCatcher.forceActiveFocus() }
        }
        Timer {
            id: hideTimer
            interval: 220                              // unmap only after the fade
            onTriggered: if (!raceWindow.shown) raceWindow.up = false
        }

        Rectangle {                                    // screen fade
            anchors.fill: parent
            color: "black"
            opacity: raceWindow.shown ? 0.66 : 0
            Behavior on opacity { NumberAnimation { duration: 180 } }
            MouseArea { anchors.fill: parent; onClicked: raceWindow.closeDown() }
        }

        // The keyboard sink for the whole race. Plain Item, not a TextInput: the
        // race needs per-character verdicts against the passage, an IME-free
        // keystroke count, and control over backspace — none of which survive a
        // text field's own editing model.
        Item {
            id: keyCatcher
            anchors.fill: parent
            focus: true
            Keys.onPressed: (event) => root.handleKey(event)
        }

        Item {
            id: card
            anchors.centerIn: parent
            width: Math.min(root.gu * 34, parent.width * 0.9)
            // Height FOLLOWS THE CONTENT — nothing inside stretches vertically,
            // so the column has a finite implicit height and the card wears it.
            // That also means the card grows with a long passage instead of
            // reserving the space permanently.
            height: cardCol.implicitHeight + root.gu * 1.9
            opacity: raceWindow.shown ? 1 : 0
            scale:   raceWindow.shown ? 1 : 0.97
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

            // Declared FIRST so every control paints and takes events above it;
            // it only stops a click on empty card space reaching the scrim.
            MouseArea {
                anchors.fill: parent
                onClicked: keyCatcher.forceActiveFocus()
            }

            // ⚠️ FULLY OPAQUE, not the backdrop-less treatment the radio card
            // uses on the wallpaper, and not the 0.97 sheet either. At 0.97 the
            // window behind this one was still legible THROUGH the passage —
            // measured, not guessed — and a second set of words ghosting under
            // the one you are reading character by character is the worst place
            // in the stack to save three percent of alpha. The frosted feel
            // comes from the scrim behind the card, not from the card itself.
            Rectangle {
                anchors.fill: parent
                radius: root.gu * 1.4
                color: root.cPanel
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.12)
                antialiasing: true
            }

            ColumnLayout {
                id: cardCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: root.gu * 0.95
                spacing: root.gu * 0.62

                // ------------------------------------------------ header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: root.gu * 0.5

                    // The real two-tone logo: the same 1000x260 alpha masks the
                    // page and the radio widget use, stacked — wordmark in
                    // --pale, circle-M in --accent so the M recolours per theme.
                    // ⚠️ Kirigami.Icon with isMask does NOT recolour a raster
                    // PNG; MultiEffect colorization is the Qt 6 way.
                    Item {
                        Layout.preferredWidth: root.gu * 6.6
                        Layout.preferredHeight: root.gu * 6.6 * 0.26
                        Image {
                            id: wordMask
                            anchors.fill: parent
                            source: Qt.resolvedUrl("../images/midnight-text-m.png")
                            fillMode: Image.PreserveAspectFit
                            visible: false
                            smooth: true
                        }
                        MultiEffect {
                            anchors.fill: wordMask
                            source: wordMask
                            colorization: 1.0
                            colorizationColor: root.cPale
                        }
                        Image {
                            id: circleMask
                            anchors.fill: parent
                            source: Qt.resolvedUrl("../images/midnight-circle-m.png")
                            fillMode: Image.PreserveAspectFit
                            visible: false
                            smooth: true
                        }
                        MultiEffect {
                            anchors.fill: circleMask
                            source: circleMask
                            colorization: 1.0
                            colorizationColor: root.cAccent
                        }
                    }

                    // The page's UP NEXT pill spec: label only, --pop text on a
                    // popA(.08) fill with a popA(.45) hairline, fully rounded.
                    Rectangle {
                        Layout.preferredWidth: typeTag.implicitWidth + root.gu * 0.7
                        Layout.preferredHeight: typeTag.implicitHeight + root.gu * 0.34
                        radius: height / 2
                        color: root.popA(0.08)
                        border.width: 1; border.color: root.popA(0.45)
                        antialiasing: true
                        Text {
                            id: typeTag
                            anchors.centerIn: parent
                            text: "TYPE"
                            color: root.cPop
                            font.family: "JetBrains Mono"; font.bold: true
                            font.pixelSize: (root.gu * 0.44) * root.fs
                            font.letterSpacing: 1.4
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        visible: prefs.bestWpm > 0
                        text: "BEST " + prefs.bestWpm + " WPM"
                        color: root.cDim
                        font.family: "JetBrains Mono"; font.pixelSize: (root.gu * 0.52) * root.fs
                        font.letterSpacing: 1.1
                    }

                    // theme crystal — the page's exact faceted-gem geometry
                    // (hex face in --accent, top facet in --pop, three white
                    // hairlines), cycling all five themes.
                        // Theme crystal removed: the palette is fixed to Prism/glass
                        // across all three cards, so a per-widget theme cycler only let them
                        // drift back out of sync.

                    // close
                        // Exit button removed: Esc and click-away dismiss, matching
                        // Midnight Weather and Midnight Radio. All three panels are now
                        // consistently button-free.
                }

                // ------------------------------------------- length segments
                // Same segmented control as the page's Live / Night Shift
                // toggle. Locked while a race is in flight — changing the band
                // mid-passage would swap the text out from under your hands.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.gu * 1.6
                    radius: root.gu * 0.45
                    color: Qt.rgba(0, 0, 0, 0.26)
                    border.width: 1; border.color: root.cEdge
                    antialiasing: true
                    opacity: (root.phase === "idle" || root.phase === "done") ? 1 : 0.45

                    Row {
                        anchors.fill: parent
                        anchors.margins: 3
                        Repeater {
                            model: [{ k: "short", t: "SHORT" },
                                    { k: "medium", t: "MEDIUM" },
                                    { k: "long", t: "LONG" }]
                            delegate: Rectangle {
                                id: seg
                                required property var modelData
                                readonly property bool on: prefs.band === modelData.k
                                // Page rules verbatim: .mode-seg.active{background:var(--green);
                                // color:var(--bg)} + the active glyph in --pop. So on Nova the
                                // purple pill carries a lime-green mark.
                                readonly property color fg: on ? root.cBg
                                         : (segMouse.containsMouse ? root.cPop : root.cDim)
                                width: parent.width / 3; height: parent.height
                                radius: root.gu * 0.34
                                color: on ? root.cAccent : "transparent"
                                antialiasing: true
                                Behavior on color { ColorAnimation { duration: 140 } }

                                Row {
                                    anchors.centerIn: parent
                                    spacing: root.gu * 0.28
                                    Rectangle {                       // the active mark, in --pop
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: root.gu * 0.34; height: width
                                        radius: width / 2
                                        color: root.cPop
                                        visible: seg.on
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: seg.modelData.t
                                        color: seg.fg
                                        font.family: "JetBrains Mono"
                                        font.bold: seg.on
                                        font.pixelSize: (root.gu * 0.53) * root.fs
                                        font.letterSpacing: 1.1
                                    }
                                }
                                MouseArea {
                                    id: segMouse
                                    anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (root.phase === "count" || root.phase === "race") return
                                        prefs.band = seg.modelData.k
                                        root.loadQuote()
                                        root.resetRace()
                                        keyCatcher.forceActiveFocus()
                                    }
                                }
                            }
                        }
                    }
                }

                // ------------------------------------------------- stat row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: root.gu * 0.5
                    StatCell {
                        label: "WPM"
                        value: root.started ? String(root.wpm) : "—"
                        tone: root.cAccent
                    }
                    StatCell {
                        label: "ACCURACY"
                        value: root.keystrokes ? (root.acc + "%") : "—"
                        tone: root.acc < 92 && root.keystrokes > 10 ? root.cRed : root.cPale
                    }
                    StatCell {
                        label: "TIME"
                        value: root.started ? (root.elapsedMs / 1000).toFixed(1) + "s" : "—"
                    }
                }

                // ------------------------------------------------ the track
                // Progress rail with your marker and, once you have a best, a
                // ghost running at that pace — the race half of TypeRacer,
                // against yourself instead of strangers.
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.gu * 1.9

                    Rectangle {                                     // rail
                        id: rail
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left; anchors.right: parent.right
                        height: 3
                        radius: 1.5
                        color: root.accentA(0.16)
                        antialiasing: true

                        Rectangle {                                 // travelled
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width * root.progress
                            height: parent.height
                            radius: parent.radius
                            color: root.cAccent
                            antialiasing: true
                            Behavior on width { NumberAnimation { duration: 80 } }
                        }
                        // finish line
                        Rectangle {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: 2; height: root.gu * 0.8
                            color: root.cEdgeHi
                        }
                    }

                    // ghost: hollow ring at your personal-best pace
                    Rectangle {
                        visible: root.hasGhost
                        width: root.gu * 0.66; height: width
                        radius: width / 2
                        color: "transparent"
                        border.width: 2; border.color: root.cPop
                        opacity: 0.6
                        antialiasing: true
                        y: (parent.height - height) / 2
                        x: Math.max(0, Math.min(rail.width - width,
                                    rail.width * root.ghostProgress - width / 2))
                        Behavior on x { NumberAnimation { duration: 80 } }
                    }

                    // you: a record, because of course it is — accent disc with
                    // a cBg spindle hole punched out of the middle.
                    Item {
                        width: root.gu * 0.95; height: width
                        y: (parent.height - height) / 2
                        x: Math.max(0, Math.min(rail.width - width,
                                    rail.width * root.progress - width / 2))
                        Behavior on x { NumberAnimation { duration: 80 } }
                        Rectangle {                                  // glow
                            anchors.centerIn: parent
                            width: parent.width * 1.9; height: width
                            radius: width / 2
                            color: root.accentA(0.20)
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: root.cAccent
                            antialiasing: true
                            Rectangle {                          // the spindle hole
                                anchors.centerIn: parent
                                width: parent.width * 0.3; height: width
                                radius: width / 2
                                color: root.cPanel               // = the card behind it
                                antialiasing: true
                            }
                        }
                    }
                }

                // ----------------------------------------------- the passage
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: flow.implicitHeight

                    // Metrics for the character cells. JetBrains Mono is
                    // monospaced, so ONE advance width sizes every cell and the
                    // cursor block never jitters as it moves between glyphs.
                    FontMetrics {
                        id: qfm
                        font.family: "JetBrains Mono"
                        font.pixelSize: (root.gu * 0.82) * root.fs
                    }

                    Flow {
                        id: flow
                        width: parent.width
                        spacing: 0
                        // Held back until the countdown so the passage cannot be
                        // pre-read — the same reason TypeRacer hides it. Low
                        // enough to read as a placeholder shape rather than as
                        // text you could get a head start on.
                        opacity: root.phase === "idle" ? 0.09 : 1
                        Behavior on opacity { NumberAnimation { duration: 260 } }

                        Repeater {
                            model: root.words
                            delegate: Row {
                                id: wordRow
                                required property var modelData

                                Repeater {
                                    model: wordRow.modelData.t.length
                                    delegate: Item {
                                        id: cell
                                        required property int index
                                        readonly property int gi: wordRow.modelData.s + index
                                        readonly property string ch: wordRow.modelData.t.charAt(index)
                                        readonly property int st: root.charState(gi)
                                        readonly property bool cur: root.phase === "race"
                                                                    && root.typed.length === gi

                                        width: qfm.advanceWidth("M")
                                        height: qfm.height * 1.5

                                        Rectangle {
                                            anchors.fill: parent
                                            anchors.topMargin: 1
                                            anchors.bottomMargin: 1
                                            radius: 3
                                            antialiasing: true
                                            // A wrong character keeps its red wash even on a
                                            // space, which is how you spot a doubled space.
                                            color: cell.cur ? root.cAccent
                                                   : (cell.st === 2 ? root.redA(0.22) : "transparent")
                                            // Breathe only before the clock starts — an
                                            // invitation to type, not a distraction mid-race.
                                            opacity: (cell.cur && !root.started) ? caretPulse.value : 1
                                        }
                                        Text {
                                            anchors.centerIn: parent
                                            text: cell.ch
                                            font: qfm.font
                                            color: cell.cur ? root.cBg
                                                   : cell.st === 2 ? root.cRed
                                                   : cell.st === 1 ? root.cPale
                                                   : root.cDim
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // countdown — translucent so the passage reads through it,
                    // rather than a scrim that hides what you are about to type
                    Text {
                        id: countLabel
                        anchors.centerIn: parent
                        visible: root.phase === "count"
                        text: root.countdown > 0 ? String(root.countdown) : "GO"
                        color: root.cAccent
                        opacity: 0.92
                        font.family: "Inter Display"; font.bold: true
                        font.pixelSize: (root.gu * 4.6) * root.fs

                        // ⚠️ `scale` is animated IMPERATIVELY here, so it must not
                        // also carry a binding — an imperative assignment destroys
                        // a binding on the same property, and the declared value
                        // would then never come back. The animation owns it, and
                        // it is re-fired per number rather than per phase.
                        Connections {
                            target: root
                            function onCountdownChanged() { tick.restart() }
                        }
                        NumberAnimation {
                            id: tick
                            target: countLabel; property: "scale"
                            from: 0.72; to: 1; duration: 240; easing.type: Easing.OutBack
                        }
                    }

                    // idle prompt
                    Rectangle {
                        anchors.centerIn: parent
                        visible: root.phase === "idle"
                        width: idleTxt.implicitWidth + root.gu * 1.6
                        height: idleTxt.implicitHeight + root.gu * 0.9
                        radius: height / 2
                        // Opaque, not an accent wash: this pill sits ON TOP of
                        // the held-back passage, and a translucent fill let the
                        // words run straight through the label.
                        color: root.cPanel
                        border.width: 1; border.color: root.cEdgeHi
                        antialiasing: true
                        Text {
                            id: idleTxt
                            anchors.centerIn: parent
                            text: "PRESS ENTER TO RACE"
                            color: root.cPale
                            font.family: "JetBrains Mono"; font.bold: true
                            font.pixelSize: (root.gu * 0.6) * root.fs
                            font.letterSpacing: 1.6
                        }
                    }
                }

                // attribution, kept quiet. "Anon" is not an attribution, it is
                // the absence of one — printing it just adds a line of noise.
                // ⚠️ THIS IS THE ONLY TEXT IN THIS WIDGET THAT CAN OVERFLOW — the pill
                // carries a fixed label and a number, so a marquee there would be inert.
                // The attribution is the one variable-length string, hence the hover
                // target lives here rather than on the pill like the other three widgets.
                MarqueeText {
                    id: attribution
                    Layout.fillWidth: true
                    Layout.preferredHeight: implicitHeight
                    visible: root.phase !== "idle" && root.author && root.author !== "Anon"
                    text: "— " + root.author
                    color: root.cDim
                    opacity: 0.75
                    family: "Inter"
                    italic: true
                    pixelSize: (root.gu * 0.55) * root.fs
                    alignRight: true
                    hovered: attribMa.containsMouse
                    MouseArea { id: attribMa; anchors.fill: parent; hoverEnabled: true }
                }

                // ------------------------------------------------- result bar
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.gu * 2.2
                    visible: root.phase === "done"
                    radius: root.gu * 0.5
                    color: root.pbDelta > 0 ? root.popA(0.10) : root.accentA(0.06)
                    border.width: 1
                    border.color: root.pbDelta > 0 ? root.popA(0.45) : root.cEdge
                    antialiasing: true

                    Row {
                        anchors.centerIn: parent
                        spacing: root.gu * 0.5
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.pbDelta > 0 ? "NEW PERSONAL BEST" : "FINISHED"
                            color: root.pbDelta > 0 ? root.cPop : root.cDim
                            font.family: "JetBrains Mono"; font.bold: true
                            font.pixelSize: (root.gu * 0.55) * root.fs
                            font.letterSpacing: 1.5
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.lastWpm + " wpm · " + root.lastAcc + "% · "
                                  + (root.pbDelta === 0 ? "matched your best"
                                     : root.pbDelta > 0 ? ("+" + root.pbDelta + " over your best")
                                     : (Math.abs(root.pbDelta) + " off your best"))
                            color: root.cPale
                            font.family: "Inter"
                            font.pixelSize: (root.gu * 0.62) * root.fs
                        }
                    }
                }

                // ---------------------------------------------------- footer
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: root.gu * 0.15
                    spacing: root.gu * 0.5

                    // last dozen races, as a shape rather than a table
                    Item {
                        visible: root.raceHistory.length > 1
                        Layout.preferredWidth: root.gu * 6.4
                        Layout.preferredHeight: root.gu * 1.9

                        Canvas {
                            id: spark
                            anchors.fill: parent
                            renderStrategy: Canvas.Cooperative
                            property color line: root.cAccent
                            property color dot: root.cPop
                            property var data: root.raceHistory
                            onLineChanged: requestPaint()
                            onDataChanged: requestPaint()
                            onPaint: {
                                var ctx = getContext("2d"); ctx.reset()
                                var h = data.slice(-12)
                                if (h.length < 2) return
                                var lo = h[0].w, hi = h[0].w
                                for (var i = 1; i < h.length; i++) {
                                    lo = Math.min(lo, h[i].w); hi = Math.max(hi, h[i].w)
                                }
                                if (hi === lo) { hi = lo + 1 }        // a flat run still draws a line
                                var pad = 3
                                function px(i) { return pad + (width - pad * 2) * (i / (h.length - 1)) }
                                function py(v) { return height - pad - (height - pad * 2) * ((v - lo) / (hi - lo)) }

                                ctx.beginPath()
                                ctx.moveTo(px(0), height)
                                for (var j = 0; j < h.length; j++) ctx.lineTo(px(j), py(h[j].w))
                                ctx.lineTo(px(h.length - 1), height)
                                ctx.closePath()
                                ctx.fillStyle = root.accentA(0.13)
                                ctx.fill()

                                ctx.beginPath()
                                for (var k = 0; k < h.length; k++) {
                                    if (k === 0) ctx.moveTo(px(k), py(h[k].w))
                                    else ctx.lineTo(px(k), py(h[k].w))
                                }
                                ctx.strokeStyle = line
                                ctx.lineWidth = 1.8
                                ctx.lineJoin = "round"; ctx.lineCap = "round"
                                ctx.stroke()

                                ctx.beginPath()
                                ctx.arc(px(h.length - 1), py(h[h.length - 1].w), 2.6, 0, Math.PI * 2)
                                ctx.fillStyle = dot
                                ctx.fill()
                            }
                        }
                        QQC2.ToolTip.visible: sparkMouse.containsMouse
                        QQC2.ToolTip.text: "Last " + Math.min(12, root.raceHistory.length) + " races"
                        MouseArea { id: sparkMouse; anchors.fill: parent; hoverEnabled: true }
                    }

                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        // Kept short enough to survive next to the sparkline and
                        // both buttons — the long version elided to "esc to …",
                        // which is worse than not offering the hint at all.
                        text: root.phase === "race"
                              ? "esc to quit · tab to skip"
                              : root.phase === "count" ? "get ready"
                              : "enter to race · tab to skip"
                        color: root.cDim
                        opacity: 0.8
                        font.family: "JetBrains Mono"; font.pixelSize: (root.gu * 0.48) * root.fs
                    }

                    GlassBtn {
                        label: "NEW PASSAGE"
                        active: root.phase !== "count"
                        onTapped: { root.loadQuote(); root.resetRace() }
                    }
                    GlassBtn {
                        label: root.phase === "done" ? "RACE AGAIN"
                               : root.phase === "race" ? "RESTART" : "RACE"
                        primary: true
                        active: root.phase !== "count"
                        onTapped: root.startRace(root.phase === "done")
                    }
                }
            }
        }

        // Drives the pre-race cursor breathing. Lives on the window so it keeps
        // its phase across passage rebuilds instead of restarting per character.
        QtObject {
            id: caretPulse
            property real value: 1
        }
        SequentialAnimation {
            running: root.phase === "race" && !root.started
            loops: Animation.Infinite
            NumberAnimation { target: caretPulse; property: "value"; to: 0.35; duration: 480; easing.type: Easing.InOutSine }
            NumberAnimation { target: caretPulse; property: "value"; to: 1.0;  duration: 480; easing.type: Easing.InOutSine }
            onRunningChanged: if (!running) caretPulse.value = 1
        }
    }

    // ⚠️ Component.onCompleted may be declared ONCE per object — a second one is
    // a hard "Property value set multiple times" load failure. All init here.
    Component.onCompleted: {
        var bad = Quotes.untypeable()
        if (bad.length) console.warn("[midnighttype] untypeable passages:", bad.join(", "))
        loadQuote()
    }
}
