.pragma library

// ⚠️ SINGLE PALETTE. The five-theme system (Verdant/Glacier/Blaze/Prism/Nova)
// was cut deliberately — every Midnight surface is Prism now, so there is one
// look to keep correct instead of five that drift apart. The accessor shape is
// unchanged (pal() still takes a name and returns the same object shape), so
// nothing downstream had to be rewritten and a theme could be reintroduced by
// adding entries back here.
//
// Prism hexes are canonical, straight from the radio page :root block:
// accent #9A8CFF / dim #A8B2C8 / pale #FFFFFF / bg #05060A / panel #1D2336 / pop #00E5B0
var THEMES = {
    "glass": { a: "#9A8CFF", d: "#A8B2C8", p: "#FFFFFF", bg: "#05060A", panel: "#1D2336", pop: "#00E5B0", label: "Prism" }
};

var ORDER = ["glass"];

var RED = "#ff2b3d";

// Any name resolves to Prism, so a stale stored theme cannot blank the palette.
function pal(name) { return THEMES["glass"]; }

function labels() { return ["Prism"]; }
