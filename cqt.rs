// NOTE: THIS CODE WAS PORTED FROM THE PYTHON REFERENCE IMPLEMENTATION BY AN AI.
// DO NOT USE WITHOUT PROVING IT IS CORRECT. ONCE YOU'VE PROVED THAT, PLEASE SUBMIT
// A PR THAT REMOVES THIS WARNING FROM THE FILE.
use regex::Regex;
use unicode_normalization::UnicodeNormalization;

lazy_static! {
    static ref AMPERS_PAT: Regex = Regex::new(r"[&\u{FE60}\u{FF06}]").unwrap();
    static ref SPECIALIZED_WHITESPACE_PAT: Regex = Regex::new(r"[\u{2028}\u{2029}\u{200B}\u{FEFF}\u{00A0}\u{3000}\r\n\t]+").unwrap();
    static ref MULTI_WHITESPACE_PAT: Regex = Regex::new(r"\s{2,}").unwrap();
    static ref DASHCHARS_PAT: Regex = Regex::new(r"[\u{058A}\u{05BE}\u{1400}\u{1806}\u{2010}\u{2011}\u{2012}\u{2013}\u{2014}\u{2015}\u{2E17}\u{2E1A}\u{2E3A}\u{2E3B}\u{2E40}\u{2E5D}\u{301C}\u{3030}\u{30A0}\u{FE31}\u{FE32}\u{FE58}\u{FE63}\u{FF0D}]+").unwrap();
    static ref MULTI_HYPHENS_PAT: Regex = Regex::new(r"-{2,}").unwrap();
    static ref LONG_DOTS_PAT: Regex = Regex::new(r"[.]{4,}").unwrap();
    static ref QUOTERS_PAT: Regex = Regex::new(r#"["\u{2018}\u{2019}\u{201C}\u{201D}\u{00AB}\u{00BB}\u{2039}\u{203A}\u{3008}\u{3009}\u{300A}\u{300B}\u{300C}\u{300D}]"#).unwrap();
    static ref ANY_WHITESPACE_PAT: Regex = Regex::new(r"(\s+)").unwrap();
}

fn algorithm_1_14(plaintext: &str) -> Vec<u8> {
    // step 1 is already complete, since Rust strings are already unicode.

    // step 2
    let x = plaintext.nfkc().collect::<String>();

    // step 3
    let x = AMPERS_PAT.replace_all(&x, " and ");

    // step 4
    let x = SPECIALIZED_WHITESPACE_PAT.replace_all(&x, " ");
    let x = x.trim();
    let x = MULTI_WHITESPACE_PAT.replace_all(&x, " ");

    // step 5
    let x = DASHCHARS_PAT.replace_all(&x, "-");
    let x = MULTI_HYPHENS_PAT.replace_all(&x, "-");
    let x = CJK_PUNCT_PAIRS.iter().fold(x, |acc, (cjk, ascii)| acc.replace(cjk, ascii));
    let x = x.chars().map(|c| {
        let n = c as u32;
        if 0xFF01 <= n && n <= 0xFF5E {
            (n - 0xFEE0) as char
        } else {
            c
        }
    }).collect::<String>();
    let x = x.replace("\u{2026}", "...");
    let x = LONG_DOTS_PAT.replace_all(&x, "...");
    let x = x.replace("\u{2044}", "/");
    let x = QUOTERS_PAT.replace_all(&x, "'");
    let x = ANY_WHITESPACE_PAT.replace_all(&x, |caps: &regex::Captures| {
        let i = caps.get(0).unwrap().start();
        let next = caps.get(0).unwrap().end();
        let mut txt = String::new();
        if i > 0 {
            txt.push_str(&x[..i]);
            if x.chars().nth(i - 1).unwrap().is_ascii_punctuation() {
                return txt;
            }
        }
        txt.push_str(caps.get(1).unwrap().as_str());
        if next < x.len() && x.chars().nth(next).unwrap().is_ascii_punctuation() {
            return txt;
        }
        txt
    });
    let x = AUTOCORRECT_PAIRS.iter().fold(x, |acc, (autocorrect, ascii)| acc.replace(autocorrect, ascii));
    let x = ASCII_EMOJI_PAIRS.iter().fold(x, |acc, (noncanonical, canonical)| acc.replace(noncanonical, canonical));

    // step 6
    x.into_bytes()
}
