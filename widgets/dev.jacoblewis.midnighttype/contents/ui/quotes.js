.pragma library

// Midnight Type — the passage pool.
//
// ⚠️ ASCII ONLY, and only characters that exist on a US keyboard. A curly
// apostrophe or an em dash is unreachable without a compose key, which makes a
// passage impossible to finish — the race would dead-end on one glyph. Straight
// quotes, hyphens, and single spaces only; the loader asserts this at startup.
//
// Bands are derived from length at runtime (see band()), not hand-assigned, so
// adding a passage never means picking a bucket for it.

var QUOTES = [
    { t: "The night is the hard drive of the day. Everything you did gets written down whether you meant it to or not.", a: "Anon" },
    { t: "A record does not care how you feel about it. It plays at the speed it plays, and you either keep up or you do not.", a: "Anon" },
    { t: "Simplicity is prerequisite for reliability.", a: "Edsger Dijkstra" },
    { t: "There are only two hard things in computer science: cache invalidation and naming things.", a: "Phil Karlton" },
    { t: "Talk is cheap. Show me the code.", a: "Linus Torvalds" },
    { t: "Programs must be written for people to read, and only incidentally for machines to execute.", a: "Abelson and Sussman" },
    { t: "The best way out is always through.", a: "Robert Frost" },
    { t: "Any sufficiently advanced technology is indistinguishable from magic.", a: "Arthur C. Clarke" },
    { t: "It is not that I am so smart, it is just that I stay with problems longer.", a: "Albert Einstein" },
    { t: "The quick brown fox jumps over the lazy dog while the sound engineer sleeps through the whole take.", a: "Pangram" },
    { t: "Perfection is achieved not when there is nothing more to add, but when there is nothing left to take away.", a: "Antoine de Saint-Exupery" },
    { t: "A vinyl record is a groove that remembers a room. You are not hearing a song, you are hearing a place.", a: "Anon" },

    { t: "The city at three in the morning belongs to the machines. Fans spinning in a dark rack, a disk head parking itself, a light blinking somewhere behind a locked door. Nobody is watching and the work gets done anyway.", a: "Anon" },
    { t: "Premature optimization is the root of all evil. Yet we should not pass up our opportunities in that critical three percent. A good programmer will look carefully at the critical code, but only after that code has been identified.", a: "Donald Knuth" },
    { t: "Walking on water and developing software from a specification are easy if both are frozen. Nothing else in the trade holds still long enough to be that simple, and the specification never freezes.", a: "Edward Berard" },
    { t: "The function of good software is to make the complex appear to be simple. That is the whole job. Everything underneath can be as intricate as it needs to be, provided the person at the front never has to think about it.", a: "Grady Booch" },
    { t: "Music is the arithmetic of sounds as optics is the geometry of light. You can measure it all the way down and still not explain why a minor chord sounds like a room you used to live in.", a: "Claude Debussy, adapted" },
    { t: "I have not failed. I have just found ten thousand ways that will not work. Each one narrows the search, and the search is the only part of the job that is actually mine.", a: "Thomas Edison" },
    { t: "The measure of intelligence is the ability to change. A system that cannot be changed is not finished, it is fossilized, and the difference matters most on the day you need it to do something new.", a: "Albert Einstein" },
    { t: "Deleted code is debugged code. Every line you do not write cannot break, cannot be misread at two in the morning, and cannot quietly disagree with the line above it six months from now.", a: "Jeff Sickel" },
    { t: "The stream stays up because somebody made the boring choice ten times in a row. Log rotation, a watchdog that checks the right thing, a backup that has actually been restored once. None of it is clever and all of it is why the music never stops.", a: "Anon" },
    { t: "Everything should be made as simple as possible, but not simpler. The second half of that sentence is the one people forget, and it is the half that keeps a simple design from becoming a wrong one.", a: "Albert Einstein" },
    { t: "There is no such thing as a small change to a running system. There are only changes whose blast radius you have measured and changes whose blast radius you are about to discover.", a: "Anon" },
    { t: "The most disastrous thing that you can ever learn is your first programming language, because from then on every problem quietly rearranges itself into the shape of the tools you already have.", a: "Alan Kay" },
    { t: "Records wear. Tape stretches. Drives fail. The only music that lasts is the music somebody bothered to copy somewhere else, on purpose, before anything went wrong.", a: "Anon" },
    { t: "Any fool can write code that a computer can understand. Good programmers write code that humans can understand, and the difference shows up not today but on the morning you come back to it with no memory of what you meant.", a: "Martin Fowler" },
    { t: "The turntable is the most honest instrument in the house. It has one job, it does that job at exactly thirty three and a third revolutions per minute, and it never once pretends to be doing anything else.", a: "Anon" },
    { t: "First, solve the problem. Then, write the code. Doing it the other way around feels faster for about twenty minutes and then costs you the rest of the week.", a: "John Johnson" },
    { t: "Fast is fine, but accuracy is everything. In a race against a clock the errors you leave behind cost more time than the keys you never pressed.", a: "Wyatt Earp, adapted" },

    { t: "The best error message is the one that never shows up. The second best tells you exactly what went wrong, where it went wrong, and what you can do about it right now. Everything else is a note from the program saying that it has given up and would prefer not to discuss the matter further. A stack trace is not an explanation, it is a receipt, and the difference between the two is roughly the difference between a map and a photograph of a map.", a: "Thomas Fuchs, adapted" },
    { t: "Consider the machine that has been running for a year without anyone touching it. Its uptime is not evidence of good design. It is evidence that nobody has needed anything new from it. The day you do, every assumption baked in on the first afternoon comes due at once, and you will find that the version numbers have moved, the certificates have expired, and the one person who remembered why that flag was set has changed jobs twice.", a: "Anon" },
    { t: "Legacy code is code without tests, and by that definition most code is legacy the moment it is written. The tests are not there for the code, they are there for you, six months out, when you want to change one thing and need some way to find out whether you have changed thirty. Without them you are not maintaining software, you are performing surgery in the dark and hoping the patient complains loudly enough to be useful.", a: "Michael Feathers, adapted" },
    { t: "The needle drops and the room changes shape. There is a second of surface noise before the first note, and that second is the whole argument for the format. It tells you that the thing you are hearing has a body, that it takes up space, that somebody cut it into a physical object and shipped it across an ocean so that you could put it on a shelf and forget about it for eleven years before pulling it back out on a Tuesday night with nothing else to do.", a: "Anon" },
    { t: "Good architecture is not the diagram. It is the set of decisions that were expensive to reverse, made early, by someone who understood what would be asked of the system later. Everything else, every framework, every library, every clever module boundary, is a detail that can be swapped out in an afternoon. If you cannot tell which of your choices are which, you do not have an architecture yet, you have an arrangement.", a: "Anon" },
    { t: "The problem with the internet is that it made distribution free and everything else expensive. Anyone can put a thing in front of ten thousand people. Almost nobody can make a thing worth putting in front of ten. We built the biggest amplifier in history and then spent thirty years discovering that the hard part was never the amplifier, it was having something to say into it.", a: "Anon" },
    { t: "Backups are a story you tell yourself until the first restore. Until then you have not got a backup, you have got a directory that is the same size as some other directory, sitting on a disk you have never read from, encrypted with a key you have never tested, following a schedule nobody has watched run. The restore is the backup. Everything before it is a rehearsal for a play that may not have a script.", a: "Anon" },
    { t: "Debugging is twice as hard as writing the code in the first place. Therefore, if you write the code as cleverly as possible, you are by definition not smart enough to debug it. This is not a warning about your intelligence, it is arithmetic about your attention, which will be lower on the night the pager goes off than it was on the afternoon you felt brilliant.", a: "Brian Kernighan" },
    { t: "Every night the same routine. The last light in the house goes off, the fans step down a notch, and the machine settles into the part of the day it was actually built for. Files move to somewhere safer. A library rescans itself. A queue that nobody is watching keeps its promise to a listener who fell asleep two hours ago with the stream still running, and it holds that promise until morning without once asking to be thanked for it.", a: "Anon" },
    { t: "A user interface is like a joke. If you have to explain it, it is not that good. The trouble is that explanation is the cheapest fix available, so most software arrives with a tour, a tooltip, and a documentation page, all of which exist to apologize for a layout that could have been rearranged in an hour by someone willing to admit that the first arrangement was wrong.", a: "Martin LeBlanc, adapted" },
    { t: "The tools you build for yourself are the only ones that fit. Every commercial product is a compromise between your needs and the needs of ten thousand strangers, and the compromise is not usually made in your favor. So you build the small ugly thing that does exactly one job the way you want it done, and you find, years later, that it is still running, still doing that one job, and that you have never once thought about replacing it.", a: "Anon" },
    { t: "Speed comes from familiarity, not from effort. The fastest typists are not straining, they are recognizing. Their hands have seen these letter pairs ten thousand times and no longer wait for the brain to confirm. The same is true of code, of scales on an instrument, of the route home. You do not get faster by pushing harder, you get faster by making the hard part boring.", a: "Anon" },
    { t: "There is a particular kind of quiet that only exists at four in the morning, when the deploy has finished, the logs have gone still, and the graphs are all the flat green line you were hoping for. It never lasts. Something will drift, something will expire, some upstream will change a default. But for about ten minutes the whole system is exactly as you understood it, and that is as close to finished as software ever gets.", a: "Anon" }
];

// Bands by length: short is a warm-up, long is a real sit-down race.
function band(q) {
    var n = q.t.length;
    if (n < 150) return "short";
    if (n <= 330) return "medium";
    return "long";
}

// Returns the passages in a band, or every passage if the band is unknown.
function pool(name) {
    var out = [];
    for (var i = 0; i < QUOTES.length; i++)
        if (!name || band(QUOTES[i]) === name) out.push(QUOTES[i]);
    return out.length ? out : QUOTES;
}

// Pick a random passage from the band, avoiding `avoid` (the one just raced) so
// a repeat is never served back to back unless the band holds a single entry.
function pick(name, avoid) {
    var p = pool(name);
    if (p.length > 1 && avoid) {
        var f = [];
        for (var i = 0; i < p.length; i++) if (p[i].t !== avoid) f.push(p[i]);
        if (f.length) p = f;
    }
    return p[Math.floor(Math.random() * p.length)];
}

// Startup assertion: any passage carrying a character that is not printable
// ASCII would be untypeable. Returns the offending list (empty when clean).
function untypeable() {
    var bad = [];
    for (var i = 0; i < QUOTES.length; i++) {
        var t = QUOTES[i].t;
        for (var j = 0; j < t.length; j++) {
            var c = t.charCodeAt(j);
            if (c < 32 || c > 126) { bad.push(i + ":" + t.charAt(j) + "(" + c + ")"); break; }
        }
    }
    return bad;
}
