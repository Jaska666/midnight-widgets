.pragma library

// ---------------------------------------------------------------------------
// Open-Meteo. Chosen because it needs NO API KEY and no account — a wallpaper
// cannot prompt for one, and a key in a QML file under ~/.local is a plaintext
// secret sitting on disk. ZIP -> lat/lon uses zippopotam.us, also keyless.
// ---------------------------------------------------------------------------

// WMO weather-interpretation codes -> { t: label, i: icon key }.
// Icon keys are drawn by WeatherIcon.qml (hand-drawn on a Canvas — the system
// icon theme renders media/weather glyphs in its own colours and would ignore
// the wallpaper palette, the same gotcha the radio widget hit with Kirigami.Icon).
var CODES = {
    0:  { t: "Clear",              i: "clear"   },
    1:  { t: "Mainly clear",       i: "clear"   },
    2:  { t: "Partly cloudy",      i: "partly"  },
    3:  { t: "Overcast",           i: "cloudy"  },
    45: { t: "Fog",                i: "fog"     },
    48: { t: "Rime fog",           i: "fog"     },
    51: { t: "Light drizzle",      i: "drizzle" },
    53: { t: "Drizzle",            i: "drizzle" },
    55: { t: "Heavy drizzle",      i: "drizzle" },
    56: { t: "Freezing drizzle",   i: "sleet"   },
    57: { t: "Freezing drizzle",   i: "sleet"   },
    61: { t: "Light rain",         i: "rain"    },
    63: { t: "Rain",               i: "rain"    },
    65: { t: "Heavy rain",         i: "rain"    },
    66: { t: "Freezing rain",      i: "sleet"   },
    67: { t: "Freezing rain",      i: "sleet"   },
    71: { t: "Light snow",         i: "snow"    },
    73: { t: "Snow",               i: "snow"    },
    75: { t: "Heavy snow",         i: "snow"    },
    77: { t: "Snow grains",        i: "snow"    },
    80: { t: "Light showers",      i: "rain"    },
    81: { t: "Showers",            i: "rain"    },
    82: { t: "Violent showers",    i: "rain"    },
    85: { t: "Snow showers",       i: "snow"    },
    86: { t: "Snow showers",       i: "snow"    },
    95: { t: "Thunderstorm",       i: "thunder" },
    96: { t: "Storm w/ hail",      i: "thunder" },
    99: { t: "Storm w/ hail",      i: "thunder" }
};

function decode(code) {
    return CODES[code] || { t: "—", i: "cloudy" };
}

// "clear" and "partly" have night variants; everything else looks the same
// day or night, so the icon painter only needs the day flag for those two.
function iconFor(code, isDay) {
    var k = decode(code).i;
    if (!isDay && (k === "clear" || k === "partly")) return k + "-night";
    return k;
}

function forecastUrl(lat, lon, metric) {
    return "https://api.open-meteo.com/v1/forecast"
        + "?latitude=" + lat + "&longitude=" + lon
        + "&current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day"
        + ",precipitation,weather_code,cloud_cover,pressure_msl,wind_speed_10m"
        + ",wind_direction_10m,wind_gusts_10m"
        + "&hourly=temperature_2m,weather_code,precipitation_probability,is_day"
        + "&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset"
        + ",precipitation_probability_max,uv_index_max,wind_speed_10m_max"
        + "&temperature_unit=" + (metric ? "celsius" : "fahrenheit")
        + "&wind_speed_unit=" + (metric ? "kmh" : "mph")
        + "&precipitation_unit=" + (metric ? "mm" : "inch")
        + "&timezone=auto&forecast_days=7";
}

function zipUrl(zip) {
    return "https://api.zippopotam.us/us/" + encodeURIComponent(zip);
}

// Small XHR wrapper. cb(err, parsedJson).
function getJson(url, cb) {
    var xhr = new XMLHttpRequest();
    xhr.onreadystatechange = function () {
        if (xhr.readyState !== XMLHttpRequest.DONE) return;
        if (xhr.status !== 200) { cb("http " + xhr.status, null); return; }
        try { cb(null, JSON.parse(xhr.responseText)); }
        catch (e) { cb("parse: " + e, null); }
    };
    try { xhr.open("GET", url); xhr.send(); }
    catch (e) { cb("send: " + e, null); }
}

// --------------------------------------------------------------- formatting
function deg() { return "°"; }

function round(v) {
    return (v === undefined || v === null || isNaN(v)) ? "--" : String(Math.round(v));
}

function temp(v) { return round(v) + deg(); }

// 16-point compass from a wind bearing in degrees.
var COMPASS = ["N","NNE","NE","ENE","E","ESE","SE","SSE",
               "S","SSW","SW","WSW","W","WNW","NW","NNW"];
function compass(d) {
    if (d === undefined || d === null || isNaN(d)) return "--";
    return COMPASS[Math.round(d / 22.5) % 16];
}

// Open-Meteo hands back naive local ISO strings ("2026-08-08T15:00") already in
// the requested timezone. new Date() on that would re-interpret it in the
// DESKTOP's zone and shift the hourly strip, so parse the fields by hand.
function parseLocal(iso) {
    if (!iso) return null;
    var m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/.exec(iso);
    if (!m) return null;
    return new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5]);
}

function hourLabel(iso, h24) {
    var d = parseLocal(iso);
    if (!d) return "--";
    var h = d.getHours();
    if (h24) return (h < 10 ? "0" : "") + h;
    var ap = h < 12 ? "a" : "p";
    var hh = h % 12; if (hh === 0) hh = 12;
    return hh + ap;
}

function clockLabel(iso, h24) {
    var d = parseLocal(iso);
    if (!d) return "--:--";
    var h = d.getHours(), mn = d.getMinutes();
    var mm = (mn < 10 ? "0" : "") + mn;
    if (h24) return ((h < 10 ? "0" : "") + h) + ":" + mm;
    var hh = h % 12; if (hh === 0) hh = 12;
    return hh + ":" + mm + (h < 12 ? " AM" : " PM");
}

var DAYS = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"];
function dayLabel(iso, index) {
    if (index === 0) return "Today";
    var d = parseLocal(iso + "T00:00");
    return d ? DAYS[d.getDay()] : "--";
}

// Index of the first hourly sample at or after `now`, so the strip starts on
// the current hour rather than at midnight.
function hourCursor(times, now) {
    if (!times) return 0;
    for (var i = 0; i < times.length; i++) {
        var d = parseLocal(times[i]);
        if (d && d.getTime() >= now.getTime() - 3600000) return i;
    }
    return 0;
}
