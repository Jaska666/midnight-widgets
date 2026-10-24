// Midnight Weather — KDE plasmoid
//
// The weather pill lifted OUT of the flip-clock wallpaper and made a widget, so
// all three desktop pills (radio, weather, type) are the same kind of object:
// movable, individually configurable, and not tied to which wallpaper is set.
//
// ⚠️ THE PILL AND THE SHEET ARE PORTS, NOT REWRITES. Weather.js, WeatherIcon.qml,
// WeatherPop.qml and Theme.js are copied VERBATIM from the wallpaper — they were
// already written as self-contained plain-QtQuick pieces with clean property
// interfaces, so the only new code here is the shell around them: the applet, the
// pill's chrome, and the popout window. If a fix lands in either copy, port it to
// the other; the wallpaper's originals stay in place for the clock.
import QtQuick
import QtQuick.Effects
import QtQuick.Window
import QtQuick.Layouts
import QtCore
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import "Weather.js" as Wx
import "Theme.js" as Theme
import "Midnight.js" as M

PlasmoidItem {
    id: root
    // album colour + away state for this widget (Live.qml)
    Live { id: mlive }

    // ⚠️ TEXT-ONLY SCALE. Container/glyph metrics stay on u and gu — only
    // font.pixelSize is multiplied by this, so shrinking type never reflows
    // the pills. 32in 4K at scale 1.5 made the stock sizes read large.
    readonly property real fs: 0.88

    // ------------------------------------------------------------- settings
    // Defaults are the wallpaper's OWN defaults, which is what has actually been
    // rendering — its stored config only ever overrode the photo keys, so these
    // values reproduce the pill exactly as it was.
    Settings {
        id: prefs
        category: "MidnightWeather"
        property string theme: "glass"          // the wallpaper's default too
        // lat/lon/place/metric MOVED to the applet configuration so they can be
        // edited from the widget's settings page. Plasmoid.configuration is
        // reactive, so a ZIP change re-fetches immediately; QtCore Settings would
        // not have propagated to this object without a plasmashell restart.
        property bool   hour24: false
        property int    brightness: 82
        property bool   nightDim: true
        property int    panelScale: 100
    }

    readonly property real   cfgLat:    Plasmoid.configuration.latitude
    readonly property real   cfgLon:    Plasmoid.configuration.longitude
    readonly property string cfgPlace:  Plasmoid.configuration.placeLabel
    readonly property bool   cfgMetric: Plasmoid.configuration.metric

    onCfgLatChanged: fetchWeather()
    onCfgLonChanged: fetchWeather()
    onCfgMetricChanged: fetchWeather()

    // ------------------------------------------------------------- palette
    // ⚠️ Theme.pal() returns a JS object of STRINGS. Assigning a string to a
    // `color` property parses it, but reading .r/.g/.b off the string yields
    // undefined and Qt.rgba(undefined, …) is fully transparent — which silently
    // erases every tint. So the alpha helpers derive from these real `color`
    // properties, never from p.* directly.
    readonly property var   p: Theme.pal(prefs.theme)
    readonly property color rawAccent: mlive.accent
    readonly property color rawDim:    p.d
    readonly property color rawPale:   p.p
    readonly property color rawPop:    p.pop
    readonly property color rawPanel:  p.panel
    readonly property color cBg:       "#000000"

    // OLED dimming, carried over from the wallpaper so the pill does not suddenly
    // burn brighter at 2am than it did as part of the clock. Applied to the
    // COLOURS rather than as layer opacity: over a dark desktop the result is
    // identical, but it lights fewer subpixels and costs no offscreen pass.
    property int hh24: 0
    // ⚠️ DIMMING DISABLED so this pill matches its two siblings.
    //
    // This used to multiply every colour by brightness/100 (0.82) plus a night
    // factor (x0.52 from 23:00-06:00, x0.72 at the shoulders). Midnight Radio and
    // Midnight Type apply NO dimming at all, so the weather pill read visibly
    // darker than them at every hour — worst at night, but ~18% darker even at
    // noon from the brightness term alone. Same tokens, different result.
    //
    // The machinery is kept rather than deleted: restoring the OLED behaviour is
    // a one-line change here, but it should be done to ALL THREE widgets at once
    // or the mismatch simply comes back.
    readonly property real dimK: 1.0
    function lum(c) { return Qt.rgba(c.r * dimK, c.g * dimK, c.b * dimK, c.a) }

    readonly property color cAccent: lum(rawAccent)
    readonly property color cDim:    lum(rawDim)
    readonly property color cPale:   lum(rawPale)
    readonly property color cPop:    lum(rawPop)
    readonly property color cPanel:  lum(rawPanel)
    readonly property color cHair:   Qt.rgba(1, 1, 1, 0.20 * dimK)
    readonly property color cOutline: Qt.rgba(0, 0, 0, 0.45)
    // The temperature must read instantly, so it is held near-white and only
    // lightly modulated by the dim — straight cPale went soft over a bright photo.
    readonly property color cDigit: {
        var k = 0.80 + 0.20 * dimK
        return Qt.rgba(k, k, k, 1)
    }
    function accentA(a) { return Qt.rgba(cAccent.r, cAccent.g, cAccent.b, a) }

    readonly property string fDisp: "Inter Display"
    readonly property string fMono: "JetBrains Mono"

    // Ticks the hour that nightDim reads. A minute is plenty — the only thing
    // downstream of it is which side of an hour boundary we are on.
    Timer {
        interval: 60000; repeat: true; running: true; triggeredOnStart: true
        onTriggered: root.hh24 = new Date().getHours()
    }

    // ---------------------------------------------------------- weather data
    QtObject {
        id: wx
        property var    payload: null
        property string updated: ""
        property int    failures: 0
    }

    function fetchWeather() {
        Wx.getJson(Wx.forecastUrl(cfgLat, cfgLon, cfgMetric), function (err, js) {
            if (err || !js || !js.current) {
                wx.failures++
                retry.interval = Math.min(15 * 60000, 30000 * Math.pow(2, Math.min(5, wx.failures)))
                retry.restart()
                return
            }
            wx.failures = 0
            wx.payload = js
            wx.updated = Wx.clockLabel(js.current.time, prefs.hour24)
        })
    }

    // Open-Meteo refreshes on a 15-minute cadence; polling faster only burns
    // requests. Failures back off exponentially instead of hammering.
    Timer {
        interval: 600000; repeat: true; running: true; triggeredOnStart: false
        onTriggered: root.fetchWeather()
    }
    Timer { id: retry; repeat: false; onTriggered: root.fetchWeather() }

    // ------------------------------------------------------------ containment
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    preferredRepresentation: compactRepresentation

    // ------------------------------------------------------------------ pill
    compactRepresentation: Item {
        id: compactRoot
        // slide off the nearest edge while away (AwaySlide.qml)
        AwaySlide { id: away; target: compactRoot; mode: mlive.mode }
        transform: Translate { x: away.dx; y: away.dy }
        opacity: away.fade

        // The shared desktop spec: 240u x 50u. ⚠️ `u` is derived from HEIGHT
        // against that spec, because the desktop containment grid-locks applet
        // height (80 logical here) and that lock is what makes it a fixed point
        // — 80 / 50u lands on the wallpaper's own u of 1.6, so this pill is the
        // same size it was when the wallpaper drew it.
        readonly property real u: Math.max(0.8, Math.min(2.4, height / 50))
        readonly property bool roomy: width > 150 * u     // false in a thin panel

        // Hardcoded rather than `240 * u`: u comes from height, so an implicit
        // WIDTH computed from it is circular (height is 0 before the stored
        // geometry lands). This is the 240u x 50u spec resolved at u = 1.6.
        implicitWidth:  304          // 240u at u = 1.28 = 307, snapped to the 16px grid the containment stores (2026-10-23)
        implicitHeight: 64
          // ⚠️ MEASURED: the stored geometry does NOT win. If this differs from the
        // size in appletsrc, the containment re-places the applet at runtime —
        // that is the whole "placement fight". 50u at the desktop's u of 1.28.

        Rectangle {
            id: pill
            anchors.fill: parent
            radius: 16 * compactRoot.u

            // filled pill, not a thin outline (thin curved strokes alias badly)
            color: "transparent"
            border.width: 0
            border.color: pillMa.containsMouse ? root.accentA(0.42) : root.cHair
            antialiasing: true
            scale: pillMa.pressed ? M.pressScale : 1
            // the shared hover: a small lift — the app's card bounce, scaled to a pill
            transform: Translate {
                y: (pillMa.containsMouse) ? -M.hoverLift * compactRoot.u : 0
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

            // Two-tone edge: a dark ring immediately OUTSIDE the light hairline
            // so the pill holds its shape over a bright photo as well as a dark
            // one. It sits entirely outside the parent's rect (negative margins,
            // and children are not clipped), so it never tints the glass.
            Rectangle {
                visible: false   // (outline ring: no background now)
                anchors.fill: parent
                anchors.margins: -1
                radius: parent.radius + 1
                color: "transparent"
                border.width: 1
                border.color: root.cOutline
                antialiasing: true
            }

            // ⚠️ SIDE MARGINS ONLY — no vertical ones. A symmetric
            // `anchors.margins` would clamp the 38u icon to whatever height was
            // left over and drag the text block off centre with it.
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 0    // frameless: box edge = content edge (pixel grid, 2026-10-06)
                anchors.rightMargin: 0
                spacing: 12 * compactRoot.u

                WeatherIcon {
                    Layout.preferredWidth: M.glyph * compactRoot.u
                    Layout.preferredHeight: M.glyph * compactRoot.u
                    Layout.alignment: Qt.AlignVCenter
                    kind: wx.payload ? Wx.iconFor(wx.payload.current.weather_code,
                                                  wx.payload.current.is_day === 1) : "cloudy"
                    cSun: root.cAccent
                    cCloud: root.cDim
                    cBolt: root.cPop
                    weight: 7.5
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 1 * compactRoot.u
                    visible: compactRoot.roomy

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 9 * compactRoot.u
                        Text {
                            style: Text.Outline; styleColor: M.textOutline   // 1px outline, kit token
                            text: wx.payload ? Wx.temp(wx.payload.current.temperature_2m) : "--°"
                            color: M.text
                            font.family: M.fontDisplay
                            // 21u is the SHARED primary size across the desktop
                            // pills, so the three corners read as one type system.
                            font.pixelSize: (M.primary * compactRoot.u) * root.fs
                            font.weight: Font.Bold
                            font.features: ({ "tnum": 1 })
                        }
                        Text {
                            style: Text.Outline; styleColor: M.textOutline   // 1px outline, kit token
                            Layout.fillWidth: true
                            text: wx.payload ? Wx.decode(wx.payload.current.weather_code).t : ""
                            // the condition is a qualifier, not a name: --dim, like the app's
                            // secondary text. The sun glyph carries this pill's accent.
                            color: M.dim
                            elide: Text.ElideRight
                            font.family: M.fontDisplay
                            font.pixelSize: (M.secondary * compactRoot.u) * root.fs
                        }
                    }
                    MarqueeText {
                        Layout.fillWidth: true
                        Layout.preferredHeight: implicitHeight
                        // ⚠️ THE RESTING TEXT STAYS SHORTENED. The state is still dropped
                        // and the separators single-spaced, because that is what keeps the
                        // low temperature from being elided away AT REST. The marquee only
                        // rescues the remainder on hover — it is not a licence to put the
                        // full label back and rely on scrolling to read the common case.
                        text: {
                            if (!wx.payload || !wx.payload.daily) return root.cfgPlace
                            return root.cfgPlace.split(",")[0]
                                + " · H " + Wx.temp(wx.payload.daily.temperature_2m_max[0])
                                + " L " + Wx.temp(wx.payload.daily.temperature_2m_min[0])
                        }
                        color: root.cDim
                        family: root.fMono
                        pixelSize: (M.tertiary * compactRoot.u) * root.fs
                        letterSpacing: M.tertiaryTrack * compactRoot.u
                        hovered: pillMa.containsMouse
                    }
                }
            }

            MouseArea {
                id: pillMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: sheetWindow.toggle()
            }
        }
    }

    // ⚠️ A Plasma popup is sized and placed by the shell — the sheet is a big
    // surface and the shell clamps it, then writes the clamped size back to
    // config. It lives in its own Window instead, exactly as the type widget's
    // race card does.
    fullRepresentation: Item { implicitWidth: 1; implicitHeight: 1 }

    // --------------------------------------------- the sheet, in its own window
    Window {
        id: sheetWindow

        // ⚠️ EXPLICIT SIZE IS REQUIRED — an unsized Window gets a 0x0 Wayland
        // surface and silently never maps: no client, no error, nothing.
        width:  Screen.width
        height: Screen.height

        // ⚠️ Windowed, NOT FullScreen. A real fullscreen surface makes KWin
        // engage and drop adaptive sync as it appears and goes; with VRR on
        // Automatic and HDR enabled each of those is a display MODE TRANSITION
        // that blanks the panel on every open.
        //
        // `visibility` ONLY — declaring `visible` as well is a hard "Conflicting
        // properties" warning and the two then fight over the same state.
        property bool up: false
        property bool shown: false
        visibility: up ? Window.Windowed : Window.Hidden

        color: "transparent"
        flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
        title: "MidnightWeatherSheet"

        function openUp() { up = true; shown = true }
        function closeDown() { shown = false; hideTimer.restart() }
        function toggle() { if (shown) closeDown(); else openUp() }

        // Unmap only AFTER the fade, or the window vanishes mid-animation.
        Timer {
            id: hideTimer
            interval: 240
            onTriggered: if (!sheetWindow.shown) sheetWindow.up = false
        }

        Rectangle {                                    // dismiss scrim
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.62)
            opacity: sheetWindow.shown ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 180 } }
            MouseArea { anchors.fill: parent; onClicked: sheetWindow.closeDown() }
        }

        WeatherPop {
            anchors.centerIn: parent
            opacity: sheetWindow.shown ? 1 : 0
            scale:   sheetWindow.shown ? 1 : 0.97
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

            forecast: wx.payload
            place: root.cfgPlace
            updated: wx.updated
            h24: prefs.hour24
            metric: root.cfgMetric
            // The sheet gets its OWN scale, deliberately well under the pill's.
            // At full u it rendered ~1060px tall on a 1440p logical desktop,
            // which read as a takeover rather than a glance.
            u: 1.6 * 0.62 * prefs.panelScale / 100
            // ⚠️ WeatherPop.qml is standalone (id: pop), so the widget's `root` is NOT
            // in scope inside it — the text scale has to be handed across explicitly or
            // the sheet keeps full-size type while every other surface shrinks.
            fs: root.fs

            // The sheet is a lit surface in its own right, so it uses the
            // UNDIMMED palette: it is transient, and dimming it would make the
            // forecast the hardest thing on screen to read.
            cAccent: root.rawAccent
            cDim:    root.rawDim
            cPale:   root.rawPale
            cPop:    root.rawPop
            cPanel:  root.rawPanel
            cBg:     root.cBg

            onClosed: sheetWindow.closeDown()
        }
    }

    // ⚠️ Component.onCompleted may be declared ONCE per object — a second one is
    // a hard "Property value set multiple times" load failure.
    Component.onCompleted: {
        root.hh24 = new Date().getHours()
        fetchWeather()
    }
}
