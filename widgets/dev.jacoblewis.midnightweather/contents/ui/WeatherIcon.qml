import QtQuick

// Hand-drawn weather glyphs on a Canvas.
//
// WHY not an icon font / Kirigami.Icon: some icon themes recolours glyphs on
// its own and Kirigami.Icon only honours `color` when isMask is true (the gotcha
// the radio widget hit twice). Drawing them means they always follow the
// wallpaper palette exactly, at any size, with no theme dependency.
//
// Everything is authored in a 100x100 box and scaled, so one geometry serves the
// 22px corner pill and the 76px hero in the popout.
Canvas {
    id: ico

    // clear | clear-night | partly | partly-night | cloudy | fog
    // drizzle | rain | sleet | snow | thunder
    property string kind: "cloudy"
    property color  cSun:   "#9A8CFF"   // sun / moon / precipitation
    property color  cCloud: "#8f9bb5"   // cloud bodies
    property color  cBolt:  "#00E5B0"   // the pop accent, lightning only
    property real   weight: 7.0         // stroke width in the 100-unit space

    // Canvas caches its last frame; a colour or kind change does NOT invalidate
    // it on its own. Without these it silently keeps painting the old palette.
    onKindChanged:   requestPaint()
    onCSunChanged:   requestPaint()
    onCCloudChanged: requestPaint()
    onCBoltChanged:  requestPaint()
    onWeightChanged: requestPaint()

    antialiasing: true

    onPaint: {
        var ctx = getContext("2d");
        ctx.reset();
        ctx.clearRect(0, 0, width, height);

        var s = Math.min(width, height) / 100;
        ctx.scale(s, s);
        ctx.lineCap = "round";
        ctx.lineJoin = "round";
        ctx.lineWidth = weight;

        var k = kind;
        var night = k.indexOf("-night") >= 0;
        var base = night ? k.substring(0, k.length - 6) : k;

        // ---- sun / moon --------------------------------------------------
        function sun(cx, cy, r) {
            ctx.strokeStyle = cSun;
            ctx.fillStyle = cSun;
            ctx.beginPath();
            ctx.arc(cx, cy, r, 0, Math.PI * 2);
            ctx.fill();
            // eight rays, drawn as spokes from just outside the disc
            for (var i = 0; i < 8; i++) {
                var a = i * Math.PI / 4;
                var x0 = cx + Math.cos(a) * (r + r * 0.42);
                var y0 = cy + Math.sin(a) * (r + r * 0.42);
                var x1 = cx + Math.cos(a) * (r + r * 0.95);
                var y1 = cy + Math.sin(a) * (r + r * 0.95);
                ctx.beginPath();
                ctx.moveTo(x0, y0);
                ctx.lineTo(x1, y1);
                ctx.stroke();
            }
        }

        // Crescent by subtraction: a filled disc with a second disc punched out
        // via destination-out, which keeps the edge as crisp as the fill.
        function moon(cx, cy, r) {
            ctx.save();
            ctx.fillStyle = cSun;
            ctx.beginPath();
            ctx.arc(cx, cy, r, 0, Math.PI * 2);
            ctx.fill();
            ctx.globalCompositeOperation = "destination-out";
            ctx.beginPath();
            ctx.arc(cx + r * 0.52, cy - r * 0.42, r * 0.92, 0, Math.PI * 2);
            ctx.fill();
            ctx.restore();
        }

        // ---- cloud -------------------------------------------------------
        // Three overlapping discs plus a flat base, filled as one path so the
        // interior seams never show.
        function cloud(cx, cy, w, col) {
            var r1 = w * 0.30, r2 = w * 0.24, r3 = w * 0.20;
            ctx.fillStyle = col;
            ctx.beginPath();
            ctx.arc(cx - w * 0.20, cy, r1, Math.PI * 0.5, Math.PI * 1.5);
            ctx.arc(cx - w * 0.02, cy - r1 * 0.72, r2, Math.PI * 1.1, Math.PI * 1.9);
            ctx.arc(cx + w * 0.24, cy - r1 * 0.10, r3, Math.PI * 1.5, Math.PI * 0.5);
            ctx.closePath();
            ctx.fill();
            ctx.fillRect(cx - w * 0.20, cy - r1, w * 0.44, r1);
        }

        // ---- precipitation ----------------------------------------------
        function streaks(y0, len, n, slant, col) {
            ctx.strokeStyle = col;
            ctx.lineWidth = weight * 0.8;
            for (var i = 0; i < n; i++) {
                var x = 30 + i * (40 / Math.max(1, n - 1));
                ctx.beginPath();
                ctx.moveTo(x, y0);
                ctx.lineTo(x - slant, y0 + len);
                ctx.stroke();
            }
            ctx.lineWidth = weight;
        }

        function flakes(y0, n, col) {
            ctx.strokeStyle = col;
            ctx.lineWidth = weight * 0.7;
            for (var i = 0; i < n; i++) {
                var x = 32 + i * (36 / Math.max(1, n - 1));
                var y = y0 + (i % 2) * 9;
                for (var a = 0; a < 3; a++) {
                    var t = a * Math.PI / 3;
                    ctx.beginPath();
                    ctx.moveTo(x - Math.cos(t) * 6, y - Math.sin(t) * 6);
                    ctx.lineTo(x + Math.cos(t) * 6, y + Math.sin(t) * 6);
                    ctx.stroke();
                }
            }
            ctx.lineWidth = weight;
        }

        // ---- compositions -------------------------------------------------
        if (base === "clear") {
            if (night) moon(50, 50, 27); else sun(50, 50, 21);

        } else if (base === "partly") {
            if (night) moon(63, 33, 19); else sun(64, 32, 15);
            cloud(46, 66, 62, cCloud);

        } else if (base === "cloudy") {
            cloud(56, 60, 56, Qt.rgba(cCloud.r, cCloud.g, cCloud.b, 0.45));
            cloud(44, 52, 66, cCloud);

        } else if (base === "fog") {
            cloud(50, 44, 62, cCloud);
            ctx.strokeStyle = cSun;
            ctx.lineWidth = weight * 0.85;
            for (var f = 0; f < 3; f++) {
                var fy = 66 + f * 12;
                ctx.beginPath();
                ctx.moveTo(24 + (f % 2) * 8, fy);
                ctx.lineTo(76 - (f % 2) * 8, fy);
                ctx.stroke();
            }
            ctx.lineWidth = weight;

        } else if (base === "drizzle") {
            cloud(50, 42, 64, cCloud);
            streaks(62, 12, 3, 3, cSun);

        } else if (base === "rain") {
            cloud(50, 40, 64, cCloud);
            streaks(60, 22, 3, 7, cSun);

        } else if (base === "sleet") {
            cloud(50, 40, 64, cCloud);
            streaks(60, 18, 2, 6, cSun);
            flakes(70, 2, cSun);

        } else if (base === "snow") {
            cloud(50, 40, 64, cCloud);
            flakes(70, 3, cSun);

        } else if (base === "thunder") {
            cloud(50, 40, 64, cCloud);
            ctx.fillStyle = cBolt;
            ctx.beginPath();
            ctx.moveTo(54, 58);
            ctx.lineTo(38, 82);
            ctx.lineTo(49, 82);
            ctx.lineTo(44, 98);
            ctx.lineTo(64, 72);
            ctx.lineTo(52, 72);
            ctx.closePath();
            ctx.fill();
        }
    }
}
