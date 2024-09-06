// NOTE: THIS CODE WAS PORTED FROM THE PYTHON REFERENCE IMPLEMENTATION BY AN AI.
// DO NOT USE WITHOUT PROVING IT IS CORRECT. ONCE YOU'VE PROVED THAT, PLEASE SUBMIT
// A PR THAT REMOVES THIS WARNING FROM THE FILE.

const AMPERS_PAT = /[&\uFE60\uFF06]/g;
const SPECIALIZED_WHITESPACE_PAT = /[\u2028\u2029\u200B\uFEFF\u00A0\u3000\r\n\t]+/g;
const MULTI_WHITESPACE_PAT = /\s{2,}/g;
const DASHCHARS_PAT = /[\u058A\u05BE\u1400\u1806\u2010\u2011\u2012\u2013\u2014\u2015\u2e17\u2e1a\u2e3a\u2e3b\u2e40\u2e5d\u301c\u3030\u30a0\ufe31\ufe32\ufe58\ufe63\uff0d]+/g;
const MULTI_HYPHENS_PAT = /-{2,}/g;
const CJK_PUNCT_PAIRS = [
    ["\u3001", ","],
    ["\u3002", "."]
];
const LONG_DOTS_PAT = /[.]{4,}/g;
const QUOTERS_PAT = /["\u2018\u2019\u201C\u201D\u00AB\u00BB\u2039\u203A\u3008\u3009\u300A\u300B\u300C\u300D]/g;
const ANY_WHITESPACE_PAT = /(\s+)/g;
const AUTOCORRECT_PAIRS = [
    ["\u1f60A", ":-)"],
    ["\u1f610", ":-|"],
    ["\u2639", ":-("],
    ["\u1f603", ":-D"],
    ["\u1f61D", ":-p"],
    ["\u1f632", ":-o"],
    ["\u1f609", ";-)"],
    ["\u2764", "<3"],
    ["\u1f494", "</3"],
    ["\u00a9", "(c)"],
    ["\u00ae", "(R)"],
    ["\u2022", "*"]
];
const ASCII_EMOJI_PAIRS = [
    [":)", ":-)"],
    [":|", ":-|"],
    [":(", ":-("],
    [":D", ":-D"],
    [":p", ":-p"],
    [":o", ":-o"],
    [";)", ";-)"]
];

function algorithm_1_14(plaintext) {
    // Step 1: Assume input is already unicode, so no conversion needed.

    // Step 2: Normalize using NFKC.
    let x = plaintext.normalize('NFKC');

    // Step 3: Replace ampersands with " and ".
    x = x.replace(AMPERS_PAT, ' and ');

    // Step 4: Normalize whitespace.
    function step4(whitespace_anomalies) {
        let out = whitespace_anomalies.replace(SPECIALIZED_WHITESPACE_PAT, ' ');
        out = out.trim();
        out = out.replace(MULTI_WHITESPACE_PAT, ' ');
        return out;
    }
    x = step4(x);

    // Step 5: Replace punctuations and symbols.
    function step5(punct_anomalies) {
        // 5.i
        let out = punct_anomalies.replace(DASHCHARS_PAT, '-');
        // 5.ii
        out = out.replace(MULTI_HYPHENS_PAT, '-');
        // 5.iii
        for (const [cjk, ascii] of CJK_PUNCT_PAIRS) {
            out = out.replace(new RegExp(cjk, 'g'), ascii);
        }
        // 5.iv
        out = out.replace(/\u2026/g, '...');
        // 5.v
        out = out.replace(LONG_DOTS_PAT, '...');
        // 5.vi
        out = out.replace(/\u2044/g, '/');
        // 5.vii
        out = out.replace(QUOTERS_PAT, "'");
        // 5.viii
        out = out.replace(ANY_WHITESPACE_PAT, (match, group1, index, str) => {
            let keep_space = true;
            if (index > 0 && str[index - 1].match(/\p{P}/u)) {
                keep_space = false;
            }
            if (index + match.length < str.length && str[index + match.length].match(/\p{P}/u)) {
                keep_space = false;
            }
            return keep_space ? match : group1;
        });
        // 5.ix
        for (const [autocorrect, ascii] of AUTOCORRECT_PAIRS) {
            out = out.replace(new RegExp(autocorrect, 'g'), ascii);
        }
        // 5.x
        for (const [noncanonical, canonical] of ASCII_EMOJI_PAIRS) {
            out = out.replace(new RegExp(noncanonical.replace(/[-\/\\^$*+?.()|[\]{}]/g, '\\$&'), 'g'), canonical);
        }
        return out;
    }
    x = step5(x);

    // Step 6: Convert to UTF-8 (JavaScript strings are UTF-16).
    return new TextEncoder('utf-8').encode(x);
}
