import QtQuick
import QtQuick.Effects
import "Weather.js" as Wx

// Full-weather sheet. Deliberately built from plain QtQuick only — no
// QtQuick.Controls — so there is no namespaced-attached-property trap
// (QQC2.ScrollBar.vertical) and nothing that can inherit the desktop's Plasma
// style and fight the palette.
//
// It is near-OPAQUE on purpose: with a giant flip clock glowing behind it there
// is nothing to absorb the backdrop, and a 0.9-alpha sheet lets the digits read
// straight through the forecast (the same lesson the radio widget's modals hit).
Item {
    id: pop

    // Text-only scale, passed in by main.qml (this file is standalone, so the
    // widget's `root` is not in scope). 1.0 keeps it independent if reused.
    property real fs: 1.0

    property var    forecast: null           // parsed Open-Meteo payload
    property string place: ""
    property string updated: ""
    property bool   h24: false
    property bool   metric: false
    property real   u: 1                 // scale unit

    property color cAccent: "#9A8CFF"
    property color cDim:    "#8f9bb5"
    property color cPale:   "#f6f9ff"
    property color cPop:    "#00E5B0"
    property color cPanel:  "#1D2336"
    property color cBg:     "#000000"

    readonly property color cSheet:  Qt.rgba(cPanel.r, cPanel.g, cPanel.b, 0.97)
    readonly property color cInset:  Qt.rgba(1, 1, 1, 0.045)
    readonly property color cHair:   Qt.rgba(1, 1, 1, 0.12)
    readonly property color cHairHi: Qt.rgba(1, 1, 1, 0.22)
    function accentA(a) { return Qt.rgba(cAccent.r, cAccent.g, cAccent.b, a) }

    readonly property string fDisp: "Inter Display"
    readonly property string fMono: "JetBrains Mono"
    readonly property string uWind: metric ? "km/h" : "mph"

    signal closed()

    // index of the hourly sample for "now"
    readonly property int hCursor: forecast && forecast.hourly
        ? Wx.hourCursor(forecast.hourly.time, new Date()) : 0

    // week temperature envelope, so every day's range bar shares one scale
    readonly property var span: {
        if (!forecast || !forecast.daily) return { lo: 0, hi: 1 };
        var lo = Infinity, hi = -Infinity;
        for (var i = 0; i < forecast.daily.time.length; i++) {
            lo = Math.min(lo, forecast.daily.temperature_2m_min[i]);
            hi = Math.max(hi, forecast.daily.temperature_2m_max[i]);
        }
        if (!isFinite(lo) || hi <= lo) return { lo: 0, hi: 1 };
        return { lo: lo, hi: hi };
    }

    width: sheet.width
    height: sheet.height

    Rectangle {
        id: sheet
        width: Math.round(760 * pop.u)
        height: col.implicitHeight + 40 * pop.u
        radius: 26 * pop.u
        color: pop.cSheet
        border.width: 1
        border.color: pop.cHair

        Column {
            id: col
            x: 26 * pop.u
            y: 20 * pop.u
            width: parent.width - 52 * pop.u
            spacing: 16 * pop.u

            // ---------------------------------------------------- header ---
            Item {
                width: parent.width
                height: 34 * pop.u

                // Midnight brand logo — the same two 1000x260 alpha masks the radio
                // and type cards use, at the same 192px width, so all three panels
                // are headed identically. This one had no logo at all.
                // A raster PNG cannot be tinted by Image/Kirigami; MultiEffect is
                // the Qt6 way to colourise while preserving alpha.
                Item {
                    id: brand
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 194 * pop.u
                    height: width * 0.26
                    Image {
                        id: markText
                        anchors.fill: parent
                        source: Qt.resolvedUrl("../images/midnight-text-m.png")
                        fillMode: Image.PreserveAspectFit
                        smooth: true; visible: false
                    }
                    MultiEffect {
                        source: markText; anchors.fill: markText
                        colorization: 1.0; colorizationColor: pop.cPale
                    }
                    Image {
                        id: markDisc
                        anchors.fill: parent
                        source: Qt.resolvedUrl("../images/midnight-circle-m.png")
                        fillMode: Image.PreserveAspectFit
                        smooth: true; visible: false
                    }
                    MultiEffect {
                        source: markDisc; anchors.fill: markDisc
                        colorization: 1.0; colorizationColor: pop.cAccent
                    }
                }

                Column {
                    anchors.left: brand.right
                    anchors.leftMargin: 14 * pop.u
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2 * pop.u
                    Text {
                        text: pop.place
                        color: pop.cPale
                        font.family: pop.fDisp
                        font.pixelSize: (19 * pop.u) * pop.fs
                        font.weight: Font.DemiBold
                    }
                }

                // NO exit button — click-away and Esc dismiss. This file is a
                // SECOND COPY of the wallpaper's WeatherPop; removing the button
                // there did nothing to what is actually on screen, because the
                // pill you see is this plasmoid, not the wallpaper's.
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: pop.updated ? "UPDATED " + pop.updated : ""
                    color: pop.cDim
                    font.family: pop.fMono
                    font.pixelSize: (10.5 * pop.u) * pop.fs
                    font.letterSpacing: 0.9 * pop.u
                }
            }

            Rectangle { width: parent.width; height: 1; color: pop.cHair }

            // ------------------------------------------------------ hero ---
            Item {
                width: parent.width
                height: 92 * pop.u

                WeatherIcon {
                    id: heroIcon
                    anchors.verticalCenter: parent.verticalCenter
                    width: 80 * pop.u; height: 80 * pop.u
                    kind: pop.forecast ? Wx.iconFor(pop.forecast.current.weather_code,
                                                pop.forecast.current.is_day === 1) : "cloudy"
                    cSun: pop.cAccent
                    cCloud: pop.cDim
                    cBolt: pop.cPop
                    weight: 6.5
                }

                Text {
                    id: heroTemp
                    anchors.left: heroIcon.right
                    anchors.leftMargin: 14 * pop.u
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: -4 * pop.u
                    text: pop.forecast ? Wx.temp(pop.forecast.current.temperature_2m) : "--°"
                    color: pop.cPale
                    font.family: pop.fDisp
                    font.pixelSize: (62 * pop.u) * pop.fs
                    font.weight: Font.Black
                    font.features: ({ "tnum": 1 })
                }

                Column {
                    anchors.left: heroTemp.right
                    anchors.leftMargin: 18 * pop.u
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4 * pop.u
                    Text {
                        text: pop.forecast ? Wx.decode(pop.forecast.current.weather_code).t : "—"
                        color: pop.cAccent
                        font.family: pop.fDisp
                        font.pixelSize: (20 * pop.u) * pop.fs
                        font.weight: Font.DemiBold
                    }
                    Text {
                        text: pop.forecast
                            ? "Feels like " + Wx.temp(pop.forecast.current.apparent_temperature)
                            : ""
                        color: pop.cDim
                        font.family: pop.fDisp
                        font.pixelSize: (13.5 * pop.u) * pop.fs
                    }
                    Text {
                        text: {
                            if (!pop.forecast || !pop.forecast.daily) return "";
                            return "H " + Wx.temp(pop.forecast.daily.temperature_2m_max[0])
                                 + "   L " + Wx.temp(pop.forecast.daily.temperature_2m_min[0]);
                        }
                        color: pop.cDim
                        font.family: pop.fMono
                        font.pixelSize: (12 * pop.u) * pop.fs
                        font.features: ({ "tnum": 1 })
                    }
                }
            }

            // ----------------------------------------------------- chips ---
            Grid {
                width: parent.width
                columns: 4
                spacing: 8 * pop.u

                Repeater {
                    model: pop.forecast ? [
                        { k: "Humidity", v: pop.forecast.current.relative_humidity_2m + "%" },
                        { k: "Wind",     v: Wx.round(pop.forecast.current.wind_speed_10m) + " " + pop.uWind
                                            + " " + Wx.compass(pop.forecast.current.wind_direction_10m) },
                        { k: "Gusts",    v: Wx.round(pop.forecast.current.wind_gusts_10m) + " " + pop.uWind },
                        { k: "Cloud",    v: pop.forecast.current.cloud_cover + "%" },
                        { k: "Rain today", v: (pop.forecast.daily.precipitation_probability_max[0] || 0) + "%" },
                        { k: "UV index",   v: Wx.round(pop.forecast.daily.uv_index_max[0]) },
                        { k: "Sunrise",    v: Wx.clockLabel(pop.forecast.daily.sunrise[0], pop.h24) },
                        { k: "Sunset",     v: Wx.clockLabel(pop.forecast.daily.sunset[0], pop.h24) }
                    ] : []

                    Rectangle {
                        required property var modelData
                        width: (col.width - 24 * pop.u) / 4
                        height: 50 * pop.u
                        radius: 12 * pop.u
                        color: pop.cInset
                        border.width: 1
                        border.color: pop.cHair
                        Column {
                            anchors.centerIn: parent
                            spacing: 3 * pop.u
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.k.toUpperCase()
                                color: pop.cDim
                                font.family: pop.fMono
                                font.pixelSize: (8.5 * pop.u) * pop.fs
                                font.letterSpacing: 1.1 * pop.u
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.v
                                color: pop.cPale
                                font.family: pop.fDisp
                                font.pixelSize: (14 * pop.u) * pop.fs
                                font.weight: Font.DemiBold
                                font.features: ({ "tnum": 1 })
                            }
                        }
                    }
                }
            }

            // --------------------------------------------------- hourly ----
            Text {
                text: "NEXT 12 HOURS"
                color: pop.cDim
                font.family: pop.fMono
                font.pixelSize: (9.5 * pop.u) * pop.fs
                font.letterSpacing: 1.6 * pop.u
            }

            Row {
                width: parent.width
                spacing: 0

                Repeater {
                    model: pop.forecast && pop.forecast.hourly ? 12 : 0

                    Item {
                        required property int index
                        readonly property int h: pop.hCursor + index
                        width: col.width / 12
                        height: 84 * pop.u

                        Rectangle {                     // "now" marker
                            visible: index === 0
                            anchors.fill: parent
                            anchors.margins: 1
                            radius: 11 * pop.u
                            color: pop.accentA(0.07)
                            border.width: 1
                            border.color: pop.accentA(0.30)
                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: 4 * pop.u

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: index === 0 ? "NOW"
                                    : Wx.hourLabel(pop.forecast.hourly.time[h], pop.h24)
                                color: index === 0 ? pop.cAccent : pop.cDim
                                font.family: pop.fMono
                                font.pixelSize: (9.5 * pop.u) * pop.fs
                                font.letterSpacing: 0.5 * pop.u
                            }
                            WeatherIcon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 26 * pop.u; height: 26 * pop.u
                                kind: Wx.iconFor(pop.forecast.hourly.weather_code[h],
                                                 pop.forecast.hourly.is_day[h] === 1)
                                cSun: pop.cAccent
                                cCloud: pop.cDim
                                cBolt: pop.cPop
                                weight: 8.5
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: Wx.temp(pop.forecast.hourly.temperature_2m[h])
                                color: pop.cPale
                                font.family: pop.fDisp
                                font.pixelSize: (13.5 * pop.u) * pop.fs
                                font.weight: Font.DemiBold
                                font.features: ({ "tnum": 1 })
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                // only surfaced when it actually matters
                                text: (pop.forecast.hourly.precipitation_probability[h] || 0) >= 10
                                    ? pop.forecast.hourly.precipitation_probability[h] + "%" : " "
                                color: pop.cPop
                                font.family: pop.fMono
                                font.pixelSize: (9.5 * pop.u) * pop.fs
                            }
                        }
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: pop.cHair }

            // ---------------------------------------------------- 7-day ----
            Text {
                text: "7-DAY FORECAST"
                color: pop.cDim
                font.family: pop.fMono
                font.pixelSize: (9.5 * pop.u) * pop.fs
                font.letterSpacing: 1.6 * pop.u
            }

            Column {
                width: parent.width
                spacing: 2 * pop.u

                Repeater {
                    model: pop.forecast && pop.forecast.daily ? pop.forecast.daily.time.length : 0

                    Item {
                        required property int index
                        width: col.width
                        height: 34 * pop.u

                        Text {
                            id: dayName
                            anchors.verticalCenter: parent.verticalCenter
                            width: 62 * pop.u
                            text: Wx.dayLabel(pop.forecast.daily.time[index], index)
                            color: index === 0 ? pop.cAccent : pop.cPale
                            font.family: pop.fDisp
                            font.pixelSize: (13.5 * pop.u) * pop.fs
                            font.weight: index === 0 ? Font.DemiBold : Font.Normal
                        }

                        WeatherIcon {
                            id: dayIcon
                            anchors.left: dayName.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: 24 * pop.u; height: 24 * pop.u
                            kind: Wx.iconFor(pop.forecast.daily.weather_code[index], true)
                            cSun: pop.cAccent
                            cCloud: pop.cDim
                            cBolt: pop.cPop
                            weight: 9
                        }

                        Text {
                            id: dayPop
                            anchors.left: dayIcon.right
                            anchors.leftMargin: 8 * pop.u
                            anchors.verticalCenter: parent.verticalCenter
                            width: 40 * pop.u
                            text: (pop.forecast.daily.precipitation_probability_max[index] || 0) >= 10
                                ? pop.forecast.daily.precipitation_probability_max[index] + "%" : ""
                            color: pop.cPop
                            font.family: pop.fMono
                            font.pixelSize: (10.5 * pop.u) * pop.fs
                        }

                        Text {
                            id: loT
                            anchors.left: dayPop.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: 42 * pop.u
                            horizontalAlignment: Text.AlignRight
                            text: Wx.temp(pop.forecast.daily.temperature_2m_min[index])
                            color: pop.cDim
                            font.family: pop.fDisp
                            font.pixelSize: (13 * pop.u) * pop.fs
                            font.features: ({ "tnum": 1 })
                        }

                        // range bar on one shared week-wide scale, so the bars
                        // are comparable down the column instead of each
                        // normalising to its own day
                        Rectangle {
                            id: track
                            anchors.left: loT.right
                            anchors.leftMargin: 12 * pop.u
                            anchors.right: hiT.left
                            anchors.rightMargin: 12 * pop.u
                            anchors.verticalCenter: parent.verticalCenter
                            height: 5 * pop.u
                            radius: height / 2
                            color: pop.cInset

                            Rectangle {
                                readonly property real f0: (pop.forecast.daily.temperature_2m_min[index] - pop.span.lo)
                                                           / (pop.span.hi - pop.span.lo)
                                readonly property real f1: (pop.forecast.daily.temperature_2m_max[index] - pop.span.lo)
                                                           / (pop.span.hi - pop.span.lo)
                                x: track.width * f0
                                width: Math.max(height, track.width * (f1 - f0))
                                height: parent.height
                                radius: height / 2
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0; color: pop.accentA(0.45) }
                                    GradientStop { position: 1; color: pop.cAccent }
                                }
                            }
                        }

                        Text {
                            id: hiT
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: 42 * pop.u
                            horizontalAlignment: Text.AlignRight
                            text: Wx.temp(pop.forecast.daily.temperature_2m_max[index])
                            color: pop.cPale
                            font.family: pop.fDisp
                            font.pixelSize: (13 * pop.u) * pop.fs
                            font.weight: Font.DemiBold
                            font.features: ({ "tnum": 1 })
                        }
                    }
                }
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignRight
                text: "open-meteo"
                color: Qt.rgba(pop.cDim.r, pop.cDim.g, pop.cDim.b, 0.5)
                font.family: pop.fMono
                font.pixelSize: (9 * pop.u) * pop.fs
                font.letterSpacing: 0.8 * pop.u
            }
        }
    }
}
