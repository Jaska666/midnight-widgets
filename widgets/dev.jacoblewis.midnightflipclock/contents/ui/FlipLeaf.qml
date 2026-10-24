import QtQuick

// One HALF of a flip card (top or bottom).
//
// The trick: a full-height card Rectangle is nested inside a half-height clipped
// Item and offset so the visible slice is the half we want. That keeps the
// rounded corners correct (the top half keeps only its top corners, the bottom
// half only its bottom) and — critically — means both halves render the SAME
// centred text at the same size, so the digit lines up perfectly across the seam.
//
// It is a separate file rather than an inline `component` because inline
// components get their own scope and cannot reach the enclosing file's ids.
Item {
    id: leaf

    property string txt: ""
    property bool   topHalf: true
    property real   cardW: 100
    property real   cardH: 100
    property real   cardRadius: 10
    property color  cardColor: "#0e1016"
    property color  edgeColor: "#22ffffff"
    property color  sheenColor: "#14ffffff"
    property color  digitColor: "#e9edf6"
    property string fontFamily: "Inter Display"
    property real   fontPx: 60
    property real   textBias: 0      // optical centring nudge, in px
    property real   shade: 0         // 0..1 fold darkening
    // 0..1 lift of the fill toward fully opaque. The card is TRANSLUCENT at rest
    // so it reads as glass over the wallpaper, but a translucent leaf mid-fold
    // would let the static half behind it show through and you would see two
    // digits at once. Leaves ramp this with their angle: opaque while swinging,
    // back to the resting alpha exactly as they land, so the handover is seamless.
    property real   opaqueBoost: 0

    width: cardW
    height: cardH / 2
    clip: true

    Rectangle {
        id: card
        width: leaf.cardW
        height: leaf.cardH
        y: leaf.topHalf ? 0 : -leaf.cardH / 2
        radius: leaf.cardRadius
        // a fully transparent card stays transparent mid-flip (no opaque flash)
        color: leaf.cardColor.a < 0.01 ? "transparent"
             : Qt.rgba(leaf.cardColor.r, leaf.cardColor.g, leaf.cardColor.b,
                       leaf.cardColor.a + (1 - leaf.cardColor.a) * leaf.opaqueBoost)
        border.width: 1
        border.color: leaf.edgeColor
        antialiasing: true

        Text {
            anchors.fill: parent
            anchors.topMargin: leaf.textBias
            text: leaf.txt
            color: leaf.digitColor
            style: Text.Outline; styleColor: "#000000"   // kit textOutline
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.family: leaf.fontFamily
            font.pixelSize: leaf.fontPx
            font.weight: Font.Black
            font.features: ({ "tnum": 1 })   // tabular figures: no width jitter
        }

        // specular top edge — the design language uses an inset hairline for
        // "thickness" rather than a drawn 3D side panel (which read as dirt).
        Rectangle {
            visible: leaf.topHalf
            x: leaf.cardRadius
            y: 1
            width: parent.width - leaf.cardRadius * 2
            height: 1
            color: leaf.sheenColor
        }
    }

    // Light falls off as the leaf folds away from the plane.
    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: leaf.shade
        visible: leaf.cardColor.a >= 0.01   // no card to shade -> no dark band during the fold
    }
}
