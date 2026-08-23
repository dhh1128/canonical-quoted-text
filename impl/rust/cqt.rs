//! Reference-conformant port of Canonical Quoted Text 2.17 (`cqt2.17`).
//!
//! NOTE: THIS CODE WAS PORTED FROM THE PYTHON REFERENCE IMPLEMENTATION BY AN AI.
//! DO NOT USE WITHOUT PROVING IT IS CORRECT. ONCE YOU'VE PROVED THAT, PLEASE SUBMIT
//! A PR THAT REMOVES THIS WARNING FROM THE FILE. (`tests/conformance.rs` runs all
//! 78 normative vectors in `goldens/cqt2.17.json`; `cargo test` is that proof for
//! the vectors, but a human has not reviewed this port line by line.)
//!
//! # Unicode version
//!
//! cqt2.17 requires Unicode 17.0.0 for every operation that consults the character
//! database. The `unicode-normalization` crate is pinned to `=0.1.25`, whose
//! `UNICODE_VERSION` is `(17, 0, 0)`; [`assert_unicode_version`] checks that at
//! runtime and the conformance test calls it. Every other property this algorithm
//! reads is a table in this file, extracted from Unicode 17.0.0, so no other
//! runtime property lookup exists to drift:
//!
//! * `General_Category=Cc` is `char::is_control`, which is frozen by stability
//!   policy at `U+0000..=U+001F` and `U+007F..=U+009F`.
//! * `Bidi_Class` `LRO`/`RLO` is exactly `U+202D` and `U+202E`.
//! * `Ps`/`Pi` and `Pe`/`Pf` are [`OPEN_PUNCT`] and [`CLOSE_PUNCT`].
//! * `White_Space`, `Dash_Punctuation`, `Terminal_Punctuation` and
//!   `Line_Break=SA` are enumerated by the spec and copied here.
//!
//! # Indexing
//!
//! The algorithm is defined on Unicode scalar values and protected spans are
//! recorded as scalar offsets, so everything below works on `&[char]`. Rust's
//! `&str` is byte-indexed and slicing it at a non-boundary panics, so the input
//! is expanded to a `Vec<char>` once and only re-encoded at the end.

use unicode_normalization::UnicodeNormalization;

/// The Unicode version this algorithm is defined against.
pub const UNICODE_VERSION: (u8, u8, u8) = (17, 0, 0);

/// Panics unless the normalization crate implements Unicode 17.0.0.
///
/// The reference implementation refuses to load when its Unicode data is the
/// wrong version; this is the same check, callable rather than automatic because
/// Rust has no module-level initializer.
pub fn assert_unicode_version() {
    assert_eq!(
        unicode_normalization::UNICODE_VERSION,
        UNICODE_VERSION,
        "cqt2.17 requires Unicode {:?}, but unicode-normalization provides {:?}",
        UNICODE_VERSION,
        unicode_normalization::UNICODE_VERSION
    );
}

// ---------------------------------------------------------------------------
// Character tables
// ---------------------------------------------------------------------------

/// Membership test over a sorted, disjoint, inclusive range table.
fn in_ranges(table: &[(u32, u32)], c: char) -> bool {
    let cp = c as u32;
    table
        .binary_search_by(|&(lo, hi)| {
            if cp < lo {
                std::cmp::Ordering::Greater
            } else if cp > hi {
                std::cmp::Ordering::Less
            } else {
                std::cmp::Ordering::Equal
            }
        })
        .is_ok()
}

/// Unicode 17 `White_Space`, enumerated by step 6.1 of the spec.
fn is_white_space(c: char) -> bool {
    matches!(
        c,
        '\u{0009}'..='\u{000D}'
            | '\u{0020}'
            | '\u{0085}'
            | '\u{00A0}'
            | '\u{1680}'
            | '\u{2000}'..='\u{200A}'
            | '\u{2028}'
            | '\u{2029}'
            | '\u{202F}'
            | '\u{205F}'
            | '\u{3000}'
    )
}

/// Unicode 17 `Dash_Punctuation` (`Pd`), enumerated by step 7.1 of the spec.
fn is_dash_punctuation(c: char) -> bool {
    matches!(
        c,
        '\u{002D}'
            | '\u{058A}'
            | '\u{05BE}'
            | '\u{1400}'
            | '\u{1806}'
            | '\u{2010}'..='\u{2015}'
            | '\u{2E17}'
            | '\u{2E1A}'
            | '\u{2E3A}'
            | '\u{2E3B}'
            | '\u{2E40}'
            | '\u{2E5D}'
            | '\u{301C}'
            | '\u{3030}'
            | '\u{30A0}'
            | '\u{FE31}'
            | '\u{FE32}'
            | '\u{FE58}'
            | '\u{FE63}'
            | '\u{FF0D}'
            | '\u{10D6E}'
            | '\u{10EAD}'
    )
}

/// The quote characters step 7.6 folds onto the ASCII apostrophe.
fn is_quote_character(c: char) -> bool {
    matches!(
        c,
        '\u{0022}'
            | '\u{2018}'
            | '\u{2019}'
            | '\u{201C}'
            | '\u{201D}'
            | '\u{00AB}'
            | '\u{00BB}'
            | '\u{2039}'
            | '\u{203A}'
            | '\u{3008}'..='\u{300D}'
    )
}

/// The four layout-only invisibles removed by step 5.1.
fn is_removed_invisible(c: char) -> bool {
    matches!(c, '\u{00AD}' | '\u{200B}' | '\u{2060}' | '\u{FEFF}')
}

/// Unicode 17 `General_Category` `Ps` or `Pi`: punctuation that binds rightward.
static OPEN_PUNCT: &[(u32, u32)] = &[
    (0x0028, 0x0028), (0x005B, 0x005B), (0x007B, 0x007B), (0x00AB, 0x00AB),
    (0x0F3A, 0x0F3A), (0x0F3C, 0x0F3C), (0x169B, 0x169B), (0x2018, 0x2018),
    (0x201A, 0x201C), (0x201E, 0x201F), (0x2039, 0x2039), (0x2045, 0x2045),
    (0x207D, 0x207D), (0x208D, 0x208D), (0x2308, 0x2308), (0x230A, 0x230A),
    (0x2329, 0x2329), (0x2768, 0x2768), (0x276A, 0x276A), (0x276C, 0x276C),
    (0x276E, 0x276E), (0x2770, 0x2770), (0x2772, 0x2772), (0x2774, 0x2774),
    (0x27C5, 0x27C5), (0x27E6, 0x27E6), (0x27E8, 0x27E8), (0x27EA, 0x27EA),
    (0x27EC, 0x27EC), (0x27EE, 0x27EE), (0x2983, 0x2983), (0x2985, 0x2985),
    (0x2987, 0x2987), (0x2989, 0x2989), (0x298B, 0x298B), (0x298D, 0x298D),
    (0x298F, 0x298F), (0x2991, 0x2991), (0x2993, 0x2993), (0x2995, 0x2995),
    (0x2997, 0x2997), (0x29D8, 0x29D8), (0x29DA, 0x29DA), (0x29FC, 0x29FC),
    (0x2E02, 0x2E02), (0x2E04, 0x2E04), (0x2E09, 0x2E09), (0x2E0C, 0x2E0C),
    (0x2E1C, 0x2E1C), (0x2E20, 0x2E20), (0x2E22, 0x2E22), (0x2E24, 0x2E24),
    (0x2E26, 0x2E26), (0x2E28, 0x2E28), (0x2E42, 0x2E42), (0x2E55, 0x2E55),
    (0x2E57, 0x2E57), (0x2E59, 0x2E59), (0x2E5B, 0x2E5B), (0x3008, 0x3008),
    (0x300A, 0x300A), (0x300C, 0x300C), (0x300E, 0x300E), (0x3010, 0x3010),
    (0x3014, 0x3014), (0x3016, 0x3016), (0x3018, 0x3018), (0x301A, 0x301A),
    (0x301D, 0x301D), (0xFD3F, 0xFD3F), (0xFE17, 0xFE17), (0xFE35, 0xFE35),
    (0xFE37, 0xFE37), (0xFE39, 0xFE39), (0xFE3B, 0xFE3B), (0xFE3D, 0xFE3D),
    (0xFE3F, 0xFE3F), (0xFE41, 0xFE41), (0xFE43, 0xFE43), (0xFE47, 0xFE47),
    (0xFE59, 0xFE59), (0xFE5B, 0xFE5B), (0xFE5D, 0xFE5D), (0xFF08, 0xFF08),
    (0xFF3B, 0xFF3B), (0xFF5B, 0xFF5B), (0xFF5F, 0xFF5F), (0xFF62, 0xFF62),
];

/// Unicode 17 `General_Category` `Pe` or `Pf`: punctuation that binds leftward.
static CLOSE_PUNCT: &[(u32, u32)] = &[
    (0x0029, 0x0029), (0x005D, 0x005D), (0x007D, 0x007D), (0x00BB, 0x00BB),
    (0x0F3B, 0x0F3B), (0x0F3D, 0x0F3D), (0x169C, 0x169C), (0x2019, 0x2019),
    (0x201D, 0x201D), (0x203A, 0x203A), (0x2046, 0x2046), (0x207E, 0x207E),
    (0x208E, 0x208E), (0x2309, 0x2309), (0x230B, 0x230B), (0x232A, 0x232A),
    (0x2769, 0x2769), (0x276B, 0x276B), (0x276D, 0x276D), (0x276F, 0x276F),
    (0x2771, 0x2771), (0x2773, 0x2773), (0x2775, 0x2775), (0x27C6, 0x27C6),
    (0x27E7, 0x27E7), (0x27E9, 0x27E9), (0x27EB, 0x27EB), (0x27ED, 0x27ED),
    (0x27EF, 0x27EF), (0x2984, 0x2984), (0x2986, 0x2986), (0x2988, 0x2988),
    (0x298A, 0x298A), (0x298C, 0x298C), (0x298E, 0x298E), (0x2990, 0x2990),
    (0x2992, 0x2992), (0x2994, 0x2994), (0x2996, 0x2996), (0x2998, 0x2998),
    (0x29D9, 0x29D9), (0x29DB, 0x29DB), (0x29FD, 0x29FD), (0x2E03, 0x2E03),
    (0x2E05, 0x2E05), (0x2E0A, 0x2E0A), (0x2E0D, 0x2E0D), (0x2E1D, 0x2E1D),
    (0x2E21, 0x2E21), (0x2E23, 0x2E23), (0x2E25, 0x2E25), (0x2E27, 0x2E27),
    (0x2E29, 0x2E29), (0x2E56, 0x2E56), (0x2E58, 0x2E58), (0x2E5A, 0x2E5A),
    (0x2E5C, 0x2E5C), (0x3009, 0x3009), (0x300B, 0x300B), (0x300D, 0x300D),
    (0x300F, 0x300F), (0x3011, 0x3011), (0x3015, 0x3015), (0x3017, 0x3017),
    (0x3019, 0x3019), (0x301B, 0x301B), (0x301E, 0x301F), (0xFD3E, 0xFD3E),
    (0xFE18, 0xFE18), (0xFE36, 0xFE36), (0xFE38, 0xFE38), (0xFE3A, 0xFE3A),
    (0xFE3C, 0xFE3C), (0xFE3E, 0xFE3E), (0xFE40, 0xFE40), (0xFE42, 0xFE42),
    (0xFE44, 0xFE44), (0xFE48, 0xFE48), (0xFE5A, 0xFE5A), (0xFE5C, 0xFE5C),
    (0xFE5E, 0xFE5E), (0xFF09, 0xFF09), (0xFF3D, 0xFF3D), (0xFF5D, 0xFF5D),
    (0xFF60, 0xFF60), (0xFF63, 0xFF63),
];

/// Unicode 17.0.0 `Terminal_Punctuation`, from `PropList.txt`. Punctuation that
/// ends a sentence, clause or word, and so attaches to the text on its LEFT. The
/// ASCII members are exactly `!` `,` `.` `:` `;` `?` -- deliberately NOT the whole
/// `Po` category, which would drag in the solidus and turn `A & B / C` into
/// `A & B/ C`, nor the apostrophe, which step 7.6 has already made ambiguous by
/// folding every quote character onto it.
static TERMINAL_PUNCTUATION: &[(u32, u32)] = &[
    (0x0021, 0x0021), (0x002C, 0x002C), (0x002E, 0x002E), (0x003A, 0x003B),
    (0x003F, 0x003F), (0x037E, 0x037E), (0x0387, 0x0387), (0x0589, 0x0589),
    (0x05C3, 0x05C3), (0x060C, 0x060C), (0x061B, 0x061B), (0x061D, 0x061F),
    (0x06D4, 0x06D4), (0x0700, 0x070A), (0x070C, 0x070C), (0x07F8, 0x07F9),
    (0x0830, 0x0835), (0x0837, 0x083E), (0x085E, 0x085E), (0x0964, 0x0965),
    (0x0E5A, 0x0E5B), (0x0F08, 0x0F08), (0x0F0D, 0x0F12), (0x104A, 0x104B),
    (0x1361, 0x1368), (0x166E, 0x166E), (0x16EB, 0x16ED), (0x1735, 0x1736),
    (0x17D4, 0x17D6), (0x17DA, 0x17DA), (0x1802, 0x1805), (0x1808, 0x1809),
    (0x1944, 0x1945), (0x1AA8, 0x1AAB), (0x1B4E, 0x1B4F), (0x1B5A, 0x1B5B),
    (0x1B5D, 0x1B5F), (0x1B7D, 0x1B7F), (0x1C3B, 0x1C3F), (0x1C7E, 0x1C7F),
    (0x2024, 0x2024), (0x203C, 0x203D), (0x2047, 0x2049), (0x2CF9, 0x2CFB),
    (0x2E2E, 0x2E2E), (0x2E3C, 0x2E3C), (0x2E41, 0x2E41), (0x2E4C, 0x2E4C),
    (0x2E4E, 0x2E4F), (0x2E53, 0x2E54), (0x3001, 0x3002), (0xA4FE, 0xA4FF),
    (0xA60D, 0xA60F), (0xA6F3, 0xA6F7), (0xA876, 0xA877), (0xA8CE, 0xA8CF),
    (0xA92F, 0xA92F), (0xA9C7, 0xA9C9), (0xAA5D, 0xAA5F), (0xAADF, 0xAADF),
    (0xAAF0, 0xAAF1), (0xABEB, 0xABEB), (0xFE12, 0xFE12), (0xFE15, 0xFE16),
    (0xFE50, 0xFE52), (0xFE54, 0xFE57), (0xFF01, 0xFF01), (0xFF0C, 0xFF0C),
    (0xFF0E, 0xFF0E), (0xFF1A, 0xFF1B), (0xFF1F, 0xFF1F), (0xFF61, 0xFF61),
    (0xFF64, 0xFF64), (0x1039F, 0x1039F), (0x103D0, 0x103D0), (0x10857, 0x10857),
    (0x1091F, 0x1091F), (0x10A56, 0x10A57), (0x10AF0, 0x10AF5), (0x10B3A, 0x10B3F),
    (0x10B99, 0x10B9C), (0x10F55, 0x10F59), (0x10F86, 0x10F89), (0x11047, 0x1104D),
    (0x110BE, 0x110C1), (0x11141, 0x11143), (0x111C5, 0x111C6), (0x111CD, 0x111CD),
    (0x111DE, 0x111DF), (0x11238, 0x1123C), (0x112A9, 0x112A9), (0x113D4, 0x113D5),
    (0x1144B, 0x1144D), (0x1145A, 0x1145B), (0x115C2, 0x115C5), (0x115C9, 0x115D7),
    (0x11641, 0x11642), (0x1173C, 0x1173E), (0x11944, 0x11944), (0x11946, 0x11946),
    (0x11A42, 0x11A43), (0x11A9B, 0x11A9C), (0x11AA1, 0x11AA2), (0x11C41, 0x11C43),
    (0x11C71, 0x11C71), (0x11EF7, 0x11EF8), (0x11F43, 0x11F44), (0x12470, 0x12474),
    (0x16A6E, 0x16A6F), (0x16AF5, 0x16AF5), (0x16B37, 0x16B39), (0x16B44, 0x16B44),
    (0x16D6E, 0x16D6F), (0x16E97, 0x16E98), (0x1BC9F, 0x1BC9F), (0x1DA87, 0x1DA8A),
];

/// Unicode 17.0.0 `Line_Break=SA`, from `LineBreak.txt`: the scripts that do not
/// separate words with spaces and therefore need explicit break opportunities --
/// Thai, Lao, Khmer, Myanmar, Tai Tham, New Tai Lue, Ahom. In these scripts
/// `U+200B` is a real word separator rather than a layout artifact.
static SPACELESS_SCRIPTS: &[(u32, u32)] = &[
    (0x0E01, 0x0E3A), (0x0E40, 0x0E4E), (0x0E81, 0x0E82), (0x0E84, 0x0E84),
    (0x0E86, 0x0E8A), (0x0E8C, 0x0EA3), (0x0EA5, 0x0EA5), (0x0EA7, 0x0EBD),
    (0x0EC0, 0x0EC4), (0x0EC6, 0x0EC6), (0x0EC8, 0x0ECE), (0x0EDC, 0x0EDF),
    (0x1000, 0x103F), (0x1050, 0x108F), (0x109A, 0x109F), (0x1780, 0x17D3),
    (0x17D7, 0x17D7), (0x17DC, 0x17DD), (0x1950, 0x196D), (0x1970, 0x1974),
    (0x1980, 0x19AB), (0x19B0, 0x19C9), (0x19DE, 0x19DF), (0x1A20, 0x1A5E),
    (0x1A60, 0x1A7C), (0x1AA0, 0x1AAD), (0xA9E0, 0xA9EF), (0xA9FA, 0xA9FE),
    (0xAA60, 0xAAC2), (0xAADB, 0xAADF), (0x11700, 0x1171A), (0x1171D, 0x1172B),
    (0x1173A, 0x1173B), (0x1173F, 0x11746),
];

/// Step 7.7.
static AUTOCORRECT_BASE: &[(&str, &str)] = &[
    ("\u{1F60A}", ":-)"),
    ("\u{1F610}", ":-|"),
    ("\u{2639}", ":-("),
    ("\u{1F603}", ":-D"),
    ("\u{1F61D}", ":-p"),
    ("\u{1F632}", ":-o"),
    ("\u{1F609}", ";-)"),
    ("\u{2764}", "<3"),
    ("\u{1F494}", "</3"),
    ("\u{00A9}", "(c)"),
    ("\u{00AE}", "(R)"),
    ("\u{2022}", "*"),
];

/// A trailing variation selector belongs to the character it follows, for every
/// entry rather than the two that happened to be spelled out. `U+FE0F` asks for
/// the emoji rendering and `U+FE0E` for the text rendering; neither changes what
/// the character is, and pickers and keyboards add them without the user
/// knowing. So all three spellings of one character have to converge, which is
/// the whole point of this step. Longest source first, so a selector form is
/// always tried before the bare one; the other order strands the selector.
static VARIATION_SELECTORS: &[char] = &['\u{FE0F}', '\u{FE0E}'];

/// Step 7.8.
static ASCII_AUTOCORRECT_PAIRS: &[(&str, &str)] = &[
    (":)", ":-)"),
    (":|", ":-|"),
    (":(", ":-("),
    (":D", ":-D"),
    (":p", ":-p"),
    (":o", ":-o"),
    (";)", ";-)"),
];

/// The marker is built from NUL deliberately. Step 2 strips every `Cc` scalar
/// from the input BEFORE protection runs, so the text provably cannot contain
/// one, and a marker therefore cannot be forged. A marker made of noncharacters
/// could be: an input holding `U+FDD0 CQT0 U+FDEF` used to have span 0's content
/// substituted into it, which both collided two distinct inputs onto one
/// canonical form and gave an attacker a way to smuggle a copy of a code span
/// past a signer.
const MARKER_OPEN: char = '\u{0}';
const MARKER_CLOSE: char = '\u{0}';

// ---------------------------------------------------------------------------
// Span recognition (step 3)
// ---------------------------------------------------------------------------

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct Span {
    start: usize,
    end: usize,
}

/// The line without its ending: CRLF, CR or LF.
fn line_body(line: &[char]) -> &[char] {
    if line.len() >= 2 && line[line.len() - 2] == '\r' && line[line.len() - 1] == '\n' {
        &line[..line.len() - 2]
    } else if !line.is_empty() && (line[line.len() - 1] == '\r' || line[line.len() - 1] == '\n') {
        &line[..line.len() - 1]
    } else {
        line
    }
}

/// Split into lines that keep their endings. A line ending is exactly LF, CR or
/// CRLF; no other Unicode separator ends a line for fence recognition.
fn lines_with_endings(text: &[char]) -> Vec<(usize, usize)> {
    let mut lines = Vec::new();
    let mut start = 0usize;
    let mut i = 0usize;
    while i < text.len() {
        if text[i] == '\r' {
            i += if i + 1 < text.len() && text[i + 1] == '\n' { 2 } else { 1 };
            lines.push((start, i));
            start = i;
        } else if text[i] == '\n' {
            i += 1;
            lines.push((start, i));
            start = i;
        } else {
            i += 1;
        }
    }
    if start < text.len() {
        lines.push((start, text.len()));
    }
    lines
}

/// `^ {0,3}(`{3,})([^`\r\n]*)$` -- returns the backtick run length.
fn fence_open_len(body: &[char]) -> Option<usize> {
    let mut i = 0;
    while i < body.len() && body[i] == ' ' {
        i += 1;
    }
    if i > 3 {
        return None;
    }
    let run_start = i;
    while i < body.len() && body[i] == '`' {
        i += 1;
    }
    let run = i - run_start;
    if run < 3 {
        return None;
    }
    // The info string may contain no backtick (and no line ending, which a line
    // body cannot hold anyway).
    if body[i..].iter().any(|&c| c == '`' || c == '\r' || c == '\n') {
        return None;
    }
    Some(run)
}

/// ``^ {0,3}`{fence_len,}[ \t]*$``
fn is_fence_close(body: &[char], fence_len: usize) -> bool {
    let mut i = 0;
    while i < body.len() && body[i] == ' ' {
        i += 1;
    }
    if i > 3 {
        return false;
    }
    let run_start = i;
    while i < body.len() && body[i] == '`' {
        i += 1;
    }
    if i - run_start < fence_len {
        return false;
    }
    body[i..].iter().all(|&c| c == ' ' || c == '\t')
}

fn fenced_spans(text: &[char]) -> Vec<Span> {
    let lines = lines_with_endings(text);
    let mut spans: Vec<Span> = Vec::new();

    let mut i = 0usize;
    while i < lines.len() {
        let (ls, le) = lines[i];
        let fence_len = match fence_open_len(line_body(&text[ls..le])) {
            Some(n) => n,
            None => {
                i += 1;
                continue;
            }
        };

        let mut j = i + 1;
        while j < lines.len() {
            let (js, je) = lines[j];
            if is_fence_close(line_body(&text[js..je]), fence_len) {
                break;
            }
            j += 1;
        }
        if j == lines.len() {
            // No closing line, so the pattern is not present. A run of backticks
            // in prose is prose. Failing to match is not an error; human text
            // has no syntax to get wrong.
            i += 1;
            continue;
        }

        // Take the line ending that precedes the opening line, so the fence still
        // starts a line after the surrounding prose is flattened into spaces.
        let mut start = ls;
        if start >= 2 && text[start - 2] == '\r' && text[start - 1] == '\n' {
            start -= 2;
        } else if start >= 1 && (text[start - 1] == '\r' || text[start - 1] == '\n') {
            start -= 1;
        }
        if let Some(previous) = spans.last() {
            start = start.max(previous.end);
        }
        spans.push(Span { start, end: lines[j].1 });
        i = j + 1;
    }
    spans
}

/// Index of the first run of exactly `length` backticks in `text[from..limit]`
/// that is not part of a longer run.
fn matching_backtick_run(
    text: &[char],
    from: usize,
    limit: usize,
    length: usize,
) -> Option<usize> {
    let mut candidate = find_backticks(text, from, limit, length)?;
    loop {
        let before_is_tick = candidate > from && text[candidate - 1] == '`';
        let after = candidate + length;
        let after_is_tick = after < limit && text[after] == '`';
        if !before_is_tick && !after_is_tick {
            return Some(candidate);
        }
        candidate = find_backticks(text, candidate + length, limit, length)?;
    }
}

/// `str.find` for a run of `length` backticks, bounded by `[from, limit)`.
fn find_backticks(text: &[char], from: usize, limit: usize, length: usize) -> Option<usize> {
    if length == 0 || limit < length {
        return None;
    }
    let mut i = from;
    while i + length <= limit {
        if text[i..i + length].iter().all(|&c| c == '`') {
            return Some(i);
        }
        i += 1;
    }
    None
}

/// `https?://` compared ASCII-case-insensitively, per RFC 3986 section 3.1. A
/// Unicode case fold would let `U+017F` match `s`; `eq_ignore_ascii_case` cannot.
fn url_scheme_len(text: &[char], at: usize, limit: usize) -> Option<usize> {
    for scheme in ["https://", "http://"] {
        let n = scheme.chars().count();
        if at + n <= limit
            && text[at..at + n]
                .iter()
                .zip(scheme.chars())
                .all(|(&a, b)| a.eq_ignore_ascii_case(&b))
        {
            return Some(n);
        }
    }
    None
}

fn url_end(text: &[char], start: usize, limit: usize) -> usize {
    let mut i = start;
    let mut paren_depth = 0usize;
    while i < limit {
        let c = text[i];
        // The Cc test is unreachable defence in depth: step 2 has already removed
        // every Cc scalar that is not White_Space, and the White_Space ones
        // terminate on the first test. Kept so a reordering of the passes cannot
        // silently swallow a control character into a URL.
        if is_white_space(c) || matches!(c, '<' | '>' | '"' | '`') || c.is_control() {
            break;
        }
        if c == '(' {
            paren_depth += 1;
        } else if c == ')' {
            if paren_depth == 0 {
                break;
            }
            paren_depth -= 1;
        }
        i += 1;
    }
    i
}

fn inline_and_url_spans(text: &[char], start: usize, end: usize) -> Vec<Span> {
    let mut spans = Vec::new();
    let mut i = start;
    while i < end {
        if text[i] == '`' {
            let mut run_end = i + 1;
            while run_end < end && text[run_end] == '`' {
                run_end += 1;
            }
            let run_length = run_end - i;
            if let Some(closing) = matching_backtick_run(text, run_end, end, run_length) {
                let span_end = closing + run_length;
                spans.push(Span { start: i, end: span_end });
                i = span_end;
                continue;
            }
            // An unmatched run is ordinary prose in its entirety, so resume AFTER
            // it. Advancing one character would re-examine a proper suffix of the
            // run as a shorter run, which can pair with a later run and protect
            // text the prose rules should have normalized.
            i = run_end;
            continue;
        }

        if let Some(scheme_len) = url_scheme_len(text, i, end) {
            let span_end = url_end(text, i + scheme_len, end);
            spans.push(Span { start: i, end: span_end });
            i = span_end;
            continue;
        }
        i += 1;
    }
    spans
}

/// Fenced code blocks first, then inline code spans and URLs in what is left.
fn opaque_spans(text: &[char]) -> Vec<Span> {
    let fences = fenced_spans(text);
    let mut spans = Vec::new();
    let mut cursor = 0usize;
    for fence in fences {
        spans.extend(inline_and_url_spans(text, cursor, fence.start));
        spans.push(fence);
        cursor = fence.end;
    }
    spans.extend(inline_and_url_spans(text, cursor, text.len()));
    spans
}

/// Replace each protected span with a placeholder that is neither whitespace nor
/// punctuation, returning the rewritten text and the span contents in order.
fn protect(text: &[char]) -> (String, Vec<String>) {
    let spans = opaque_spans(text);
    if spans.is_empty() {
        return (text.iter().collect(), Vec::new());
    }

    let mut out = String::new();
    let mut protected = Vec::with_capacity(spans.len());
    let mut cursor = 0usize;
    for (number, span) in spans.iter().enumerate() {
        out.extend(text[cursor..span.start].iter());
        out.push(MARKER_OPEN);
        out.push_str("CQT");
        out.push_str(&number.to_string());
        out.push(MARKER_CLOSE);
        protected.push(text[span.start..span.end].iter().collect());
        cursor = span.end;
    }
    out.extend(text[cursor..].iter());
    (out, protected)
}

/// Put every protected span back where its placeholder is (step 8).
///
/// A marker whose index names no span is left standing: cqt2.17 is a total
/// function with no error conditions. Since markers are made of NUL and step 2
/// strips every `Cc` scalar before protection runs, this is unreachable for any
/// input -- it exists so a future reordering of the passes degrades rather than
/// panics.
fn restore(text: &str, protected: &[String]) -> String {
    if protected.is_empty() && !text.contains(MARKER_OPEN) {
        return text.to_string();
    }
    let chars: Vec<char> = text.chars().collect();
    let mut out = String::with_capacity(text.len());
    let mut i = 0usize;
    while i < chars.len() {
        if chars[i] == MARKER_OPEN {
            if let Some((number, after)) = parse_marker(&chars, i) {
                if let Some(content) = protected.get(number) {
                    out.push_str(content);
                    i = after;
                    continue;
                }
            }
        }
        out.push(chars[i]);
        i += 1;
    }
    out
}

/// `\x00CQT[0-9]+\x00` beginning at `at`; yields the number and the index
/// just past the marker.
fn parse_marker(chars: &[char], at: usize) -> Option<(usize, usize)> {
    let mut i = at + 1;
    for expected in ['C', 'Q', 'T'] {
        if i >= chars.len() || chars[i] != expected {
            return None;
        }
        i += 1;
    }
    let digits_start = i;
    while i < chars.len() && chars[i].is_ascii_digit() {
        i += 1;
    }
    if i == digits_start || i >= chars.len() || chars[i] != MARKER_CLOSE {
        return None;
    }
    // The reference keys its table on the marker string itself, so only the
    // canonical decimal rendering of an index is a marker. `CQT007` is not
    // `CQT7`; it is text that happens to look like a marker.
    if i - digits_start > 1 && chars[digits_start] == '0' {
        return None;
    }
    let number: usize = chars[digits_start..i].iter().collect::<String>().parse().ok()?;
    Some((number, i + 1))
}

// ---------------------------------------------------------------------------
// Prose canonicalization (steps 4 through 7)
// ---------------------------------------------------------------------------

/// Step 2: remove what cannot belong to plain text.
///
/// Rust's `&str` cannot hold an unpaired surrogate -- `char` is a Unicode scalar
/// value by construction -- so step 2.1 has nothing to do here and any surrogate
/// in the source data was already lost or rejected before this function saw it.
/// A well-formed pair arrives as the one astral character it encodes.
///
/// Control characters outside the `White_Space` set -- NUL and its neighbours --
/// are not plain text. And the two directional overrides, LRO and RLO, force
/// every character in their scope to render in a given direction regardless of
/// what the character is, so Latin letters display reversed. That is an
/// instruction to a rendering engine, not a statement about the text, and it is
/// the primitive behind bidi spoofing.
///
/// The other bidi controls stay. Marks (ALM, LRM, RLM) only affect how
/// neighbouring neutral characters resolve, and isolates (LRI, RLI, FSI, PDI)
/// scope a direction without overriding anything, so both are ordinary parts of
/// correct Arabic and Hebrew text.
fn strip_disallowed(plaintext: &str) -> Vec<char> {
    plaintext
        .chars()
        .filter(|&c| {
            if c.is_control() && !is_white_space(c) {
                return false;
            }
            // Bidi_Class LRO and RLO are exactly these two scalars in Unicode 17.
            !matches!(c, '\u{202D}' | '\u{202E}')
        })
        .collect()
}

/// Step 5: drop the four layout-only characters.
///
/// `U+200B` survives between two scalars from a script that does not separate
/// words with spaces, where it is the word separator rather than an artifact.
/// Both neighbours must qualify, so a stray `U+200B` injected at a script
/// boundary by a mailer or sanitizer is still removed.
fn remove_invisibles(text: &str) -> String {
    let chars: Vec<char> = text.chars().collect();
    let mut out = String::with_capacity(text.len());
    for (index, &c) in chars.iter().enumerate() {
        if !is_removed_invisible(c) {
            out.push(c);
            continue;
        }
        if c == '\u{200B}' {
            let before = index.checked_sub(1).map(|k| chars[k]);
            let after = chars.get(index + 1).copied();
            let qualifies = |x: Option<char>| x.is_some_and(|y| in_ranges(SPACELESS_SCRIPTS, y));
            if qualifies(before) && qualifies(after) {
                out.push(c);
            }
        }
    }
    out
}

/// Step 6: each run of `White_Space` becomes one space; then trim spaces.
fn collapse_unicode_whitespace(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut in_whitespace = false;
    for c in text.chars() {
        if is_white_space(c) {
            if !in_whitespace {
                out.push(' ');
            }
            in_whitespace = true;
        } else {
            out.push(c);
            in_whitespace = false;
        }
    }
    // Python's str.strip(" ") removes ASCII spaces only, which is all that can
    // remain at either end after the collapse above.
    out.trim_matches(' ').to_string()
}

/// Collapse every run of `at_least` or more `target` characters to `replacement`.
fn collapse_runs(text: &str, target: char, at_least: usize, replacement: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut chars = text.chars().peekable();
    while let Some(c) = chars.next() {
        if c != target {
            out.push(c);
            continue;
        }
        let mut run = 1usize;
        while chars.peek() == Some(&target) {
            chars.next();
            run += 1;
        }
        if run >= at_least {
            out.push_str(replacement);
        } else {
            for _ in 0..run {
                out.push(target);
            }
        }
    }
    out
}

/// Step 7.9: attach punctuation to the side it belongs to.
///
/// Punctuation is not symmetric. Opening punctuation binds to what follows it and
/// closing, final and terminal punctuation bind to what precedes, so a space is
/// removed on the side the punctuation attaches to and left alone on the other.
/// That keeps `ignorance, up` and `name: value` intact while still converging
/// `hello :)` and `hello 😊` on `hello:-)`, which is what this rule exists to do.
fn remove_spaces_adjacent_to_punctuation(text: &str) -> String {
    let chars: Vec<char> = text.chars().collect();
    let mut out = String::with_capacity(text.len());
    let mut i = 0usize;
    while i < chars.len() {
        if chars[i] != ' ' {
            out.push(chars[i]);
            i += 1;
            continue;
        }
        let run_start = i;
        while i < chars.len() && chars[i] == ' ' {
            i += 1;
        }
        let before = run_start.checked_sub(1).map(|k| chars[k]);
        let after = chars.get(i).copied();
        let attaches_left = after.is_some_and(|c| {
            in_ranges(TERMINAL_PUNCTUATION, c) || in_ranges(CLOSE_PUNCT, c)
        });
        let attaches_right = before.is_some_and(|c| in_ranges(OPEN_PUNCT, c));
        if !(attaches_left || attaches_right) {
            out.push(' ');
        }
    }
    out
}

fn map_chars(text: &str, f: impl Fn(char) -> Option<char>) -> String {
    text.chars().map(|c| f(c).unwrap_or(c)).collect()
}

/// Steps 4 through 7, one pass, in order. Nothing here runs twice.
///
/// The autocorrect tables run before space removal. A client that swaps an emoji
/// for its emoticon spelling, or the reverse, is exactly the kind of tooling
/// transformation CQT exists to survive, so `hello 😊`, `hello :)` and
/// `hello :-)` must all reach the same bytes. Mapping to the canonical spelling
/// first puts a colon where the space rule can see it.
///
/// The cost of a single pass is that `: )` ends at `:)` rather than `:-)`, since
/// nothing revisits the tables after the space closes the gap. That is an oddity
/// somebody typed, not something a tool did to their text.
fn canonicalize_prose(text: &str) -> String {
    // Step 4: NFKC.
    let mut text: String = text.nfkc().collect();
    // Step 5.
    text = remove_invisibles(&text);
    // Step 6.
    text = collapse_unicode_whitespace(&text);
    // Step 7.1 and 7.2.
    text = map_chars(&text, |c| if is_dash_punctuation(c) { Some('-') } else { None });
    text = collapse_runs(&text, '-', 2, "-");
    // Step 7.3.
    text = map_chars(&text, |c| match c {
        '\u{3001}' => Some(','),
        '\u{3002}' => Some('.'),
        _ => None,
    });
    // Step 7.4.
    text = text.replace('\u{2026}', "...");
    text = collapse_runs(&text, '.', 4, "...");
    // Step 7.5.
    text = text.replace('\u{2044}', "/");
    // Step 7.6.
    text = map_chars(&text, |c| if is_quote_character(c) { Some('\'') } else { None });
    // Step 7.7 and 7.8, in table order, before the space rule. Each base entry
    // contributes three rules: the source with each variation selector, longest
    // first, then the bare source.
    let mut with_selector = String::new();
    for (source, target) in AUTOCORRECT_BASE {
        for &selector in VARIATION_SELECTORS {
            with_selector.clear();
            with_selector.push_str(source);
            with_selector.push(selector);
            text = text.replace(with_selector.as_str(), target);
        }
        text = text.replace(source, target);
    }
    for (source, target) in ASCII_AUTOCORRECT_PAIRS {
        text = text.replace(source, target);
    }
    // Step 7.9.
    text = remove_spaces_adjacent_to_punctuation(&text);
    // Step 7.10.
    text = text.replace('&', " & ");
    collapse_unicode_whitespace(&text)
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

/// Return the CQT 2.17 canonical UTF-8 byte stream for `plaintext`.
///
/// Total: every input produces output, and there are no error conditions.
pub fn algorithm_2_17(plaintext: &str) -> Vec<u8> {
    // Strip what cannot be plain text BEFORE recognizing anything. Otherwise an
    // override hidden inside a fence or a URL is copied through untouched, and
    // the span becomes a channel for exactly the spoof this removal prevents.
    let stripped = strip_disallowed(plaintext);
    let (text, protected) = protect(&stripped);
    let text = canonicalize_prose(&text);
    // Step 9: UTF-8, no byte order mark. A Rust String already is that.
    restore(&text, &protected).into_bytes()
}

/// Convenience wrapper for callers that want the canonical form as text.
pub fn canonicalize(plaintext: &str) -> String {
    String::from_utf8(algorithm_2_17(plaintext)).expect("output is UTF-8 by construction")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unicode_version_is_seventeen() {
        assert_unicode_version();
    }

    #[test]
    fn tables_are_sorted_and_disjoint() {
        for table in [OPEN_PUNCT, CLOSE_PUNCT, TERMINAL_PUNCTUATION, SPACELESS_SCRIPTS] {
            for window in table.windows(2) {
                assert!(window[0].0 <= window[0].1);
                assert!(window[0].1 < window[1].0, "{:?} not disjoint", window);
            }
        }
    }

    #[test]
    fn scheme_match_is_ascii_only() {
        // U+017F LATIN SMALL LETTER LONG S must not match the "s" of "https".
        let text: Vec<char> = "httpſ://example.test".chars().collect();
        assert_eq!(url_scheme_len(&text, 0, text.len()), None);
        let text: Vec<char> = "HTTPS://example.test".chars().collect();
        assert_eq!(url_scheme_len(&text, 0, text.len()), Some(8));
    }
}
