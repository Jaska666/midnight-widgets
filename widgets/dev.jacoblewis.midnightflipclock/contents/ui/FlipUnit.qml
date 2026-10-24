import QtQuick

// A two-digit flip card, e.g. "07". Nothing else — no label, no chrome.
//
// Mechanic (the classic split-flap, same as the reference site's tick.js):
//   statics   top = NEW value, bottom = OLD value
//   phase 1   an upper leaf showing the OLD top folds down 0 -> -90 degrees,
//             revealing the NEW top that was already sitting behind it
//   phase 2   a lower leaf showing the NEW bottom falls 90 -> 0 degrees,
//             landing over the OLD bottom
// The whole pair flips as ONE card (not per-digit) — that is what a real flip
// clock does, and it means 59 -> 00 is a single motion.
Item {
    id: unit

    property string value: "00"

    property real   cardW: 200
    property real   cardH: 105
    property real   cardRadius: Math.max(4, cardH * 0.075)
    // Sized against BOTH axes. Inter Display Black renders a digit PAIR at
    // ~1.256em, so 0.70 * cardW fills ~88% of the card horizontally; the cardH
    // term is a guard so a future, even taller card cannot push the glyphs past
    // the seam. At 0.55 the digits filled 73% of the width but only ~39% of the
    // height, which read as a small number floating in a large empty box.
    property real   fontPx: Math.min(cardW * 0.70, cardH * 0.62)
    // Digits have no descenders, so the glyph box leaves dead space below the
    // baseline and the number reads low without a nudge up. 0.04 over-corrected
    // once the font grew — measured 88px of card above the digits vs 98 below.
    property real   textBias: -fontPx * 0.024

    property color  cardColor: "#0e1016"
    property color  edgeColor: "#22ffffff"
    property color  sheenColor: "#14ffffff"
    property color  digitColor: "#e9edf6"
    property color  seamColor: "#000000"
    property color  seamLight: "#1affffff"   // lit top edge of the lower leaf
    property color  outlineColor: "#73000000" // dark ring outside the hairline
    property string displayFont: "Inter Display"
    property int    flipMs: 150

    // --- flip state ---------------------------------------------------------
    property string oldVal: value
    property string newVal: value
    property int    phase: 0          // 0 idle | 1 upper folding | 2 lower falling
    property real   upperAngle: 0
    property real   lowerAngle: 90

    width: cardW
    height: cardH

    // Perspective. Qt Quick's Rotation about X is orthographic on its own — the
    // leaf would just squash flat. This builds translate(c) * perspective *
    // translate(-c) so the vanishing point sits on the hinge instead of the
    // item's top-left corner (which would skew the fold sideways).
    function persp(cx, cy, d) {
        var p  = Qt.matrix4x4(1, 0, 0, 0,   0, 1, 0, 0,   0, 0, 1, 0,   0, 0, -1 / d, 1);
        var t  = Qt.matrix4x4(1, 0, 0,  cx, 0, 1, 0,  cy, 0, 0, 1, 0,   0, 0, 0, 1);
        var ti = Qt.matrix4x4(1, 0, 0, -cx, 0, 1, 0, -cy, 0, 0, 1, 0,   0, 0, 0, 1);
        return t.times(p).times(ti);
    }
    readonly property real perspDepth: cardH * 5

    onValueChanged: {
        if (value === newVal) return;
        // A pending flip is snapped to its end state first, otherwise a fast
        // value change (or a resume from sleep) leaves a leaf stranded mid-fold.
        if (flipAnim.running) flipAnim.complete();
        oldVal = newVal;
        newVal = value;
        flipAnim.restart();
    }

    SequentialAnimation {
        id: flipAnim
        ScriptAction { script: { unit.phase = 1; unit.upperAngle = 0; unit.lowerAngle = 90; } }
        NumberAnimation {
            target: unit; property: "upperAngle"
            from: 0; to: -90; duration: unit.flipMs; easing.type: Easing.InQuad
        }
        ScriptAction { script: unit.phase = 2 }
        NumberAnimation {
            target: unit; property: "lowerAngle"
            from: 90; to: 0; duration: unit.flipMs + 30; easing.type: Easing.OutQuad
        }
        ScriptAction { script: { unit.phase = 0; unit.oldVal = unit.newVal; } }
    }

    // ⚠️ NOT a drop shadow. The obvious way to make the card pop is MultiEffect
    // with shadowEnabled, but MultiEffect paints its SOURCE as well as the
    // shadow — a black proxy would sit behind the card, and because the card is
    // translucent that black shows straight through it and destroys the very
    // transparency this is meant to preserve.
    //
    // Instead: a two-tone edge. A dark ring immediately OUTSIDE the light
    // hairline. That pair reads on any wallpaper — the light edge carries
    // against dark photos, the dark ring against bright ones — and it costs one
    // rectangle with no offscreen pass and no darkening behind the glass.
    Rectangle {
        z: -1
        x: -1
        y: -1
        width: unit.cardW + 2
        height: unit.cardH + 2
        radius: unit.cardRadius + 1
        color: "transparent"
        border.width: 1
        border.color: unit.outlineColor
        antialiasing: true
    }

    // --- card ---------------------------------------------------------------
    Item {
        id: cardBox
        width: unit.cardW
        height: unit.cardH

        FlipLeaf {            // static top: already the NEW value
            id: topStatic
            z: 0
            y: 0
            topHalf: true
            txt: unit.newVal
            cardW: unit.cardW; cardH: unit.cardH; cardRadius: unit.cardRadius
            cardColor: unit.cardColor; edgeColor: unit.edgeColor
            sheenColor: unit.sheenColor; digitColor: unit.digitColor
            fontFamily: unit.displayFont; fontPx: unit.fontPx; textBias: unit.textBias
        }

        FlipLeaf {            // static bottom: OLD until the lower leaf lands
            id: botStatic
            z: 0
            y: unit.cardH / 2
            topHalf: false
            txt: unit.phase > 0 ? unit.oldVal : unit.newVal
            cardW: unit.cardW; cardH: unit.cardH; cardRadius: unit.cardRadius
            cardColor: unit.cardColor; edgeColor: unit.edgeColor
            sheenColor: unit.sheenColor; digitColor: unit.digitColor
            fontFamily: unit.displayFont; fontPx: unit.fontPx; textBias: unit.textBias
        }

        FlipLeaf {            // folding leaf: OLD top, hinged on its bottom edge
            id: upperLeaf
            z: 2
            y: 0
            visible: unit.phase === 1
            topHalf: true
            txt: unit.oldVal
            shade: 0.55 * Math.abs(unit.upperAngle) / 90
            opaqueBoost: Math.abs(unit.upperAngle) / 90
            cardW: unit.cardW; cardH: unit.cardH; cardRadius: unit.cardRadius
            cardColor: unit.cardColor; edgeColor: unit.edgeColor
            sheenColor: unit.sheenColor; digitColor: unit.digitColor
            fontFamily: unit.displayFont; fontPx: unit.fontPx; textBias: unit.textBias
            // Transforms are POST-multiplied, so the LAST entry is applied to the
            // point first: perspective must be listed BEFORE the rotation.
            transform: [
                Matrix4x4 { matrix: unit.persp(unit.cardW / 2, unit.cardH / 2, unit.perspDepth) },
                Rotation {
                    origin.x: unit.cardW / 2; origin.y: unit.cardH / 2
                    axis { x: 1; y: 0; z: 0 }
                    angle: unit.upperAngle
                }
            ]
        }

        FlipLeaf {            // falling leaf: NEW bottom, hinged on its top edge
            id: lowerLeaf
            z: 2
            y: unit.cardH / 2
            visible: unit.phase === 2
            topHalf: false
            txt: unit.newVal
            shade: 0.55 * unit.lowerAngle / 90
            opaqueBoost: unit.lowerAngle / 90
            cardW: unit.cardW; cardH: unit.cardH; cardRadius: unit.cardRadius
            cardColor: unit.cardColor; edgeColor: unit.edgeColor
            sheenColor: unit.sheenColor; digitColor: unit.digitColor
            fontFamily: unit.displayFont; fontPx: unit.fontPx; textBias: unit.textBias
            transform: [
                Matrix4x4 { matrix: unit.persp(unit.cardW / 2, 0, unit.perspDepth) },
                Rotation {
                    origin.x: unit.cardW / 2; origin.y: 0
                    axis { x: 1; y: 0; z: 0 }
                    angle: unit.lowerAngle
                }
            ]
        }

        // The hinge. Previously a single bar of Math.max(2, cardH * 0.024) — a
        // ~10px slab at this card size — which over a translucent card read as a
        // painted stripe rather than a join between two leaves.
        //
        // Now it is what it physically is: a THIN dark gap between the halves,
        // with the lower leaf's top edge catching a little light directly under
        // it. That one highlight is what sells the two-piece illusion. Both stay
        // on top, since the gap is the axle and should remain continuous even
        // while a leaf swings past.
        Rectangle {
            id: seamGap
            z: 3
            y: unit.cardH / 2 - height / 2
            width: unit.cardW
            height: Math.max(2, unit.cardH * 0.009)
            color: unit.seamColor
        }
        Rectangle {
            z: 3
            y: seamGap.y + seamGap.height
            width: unit.cardW
            height: Math.max(1, unit.cardH * 0.003)
            color: unit.seamLight
        }
    }

}
