// Canonical Quoted Text 2.17 -- Java port of the reference implementation in cqt.py.
//
// Run the conformance vectors with the single-file source launcher (no build tool,
// no javac, no dependencies):
//
//     java Cqt.java [path/to/../../goldens/cqt2.17.json]
//
// Unicode: the spec requires Unicode 17.0.0 for every Character Database lookup.
// The JDK bundles its own version (Java 25 = Unicode 16.0.0), so the NFKC
// differences between 16 and 17 are corrected explicitly. See UNICODE_DELTA_FROM
// and CCC_DELTA below.

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class Cqt {

    public static final String UNICODE_VERSION = "17.0.0";

    // ---------------------------------------------------------------- Unicode delta

    // The JDK's java.text.Normalizer uses the Unicode version bundled with the
    // runtime, which for Java 25 is 16.0.0 (measured: every Unicode 16 addition is
    // assigned, no Unicode 17 addition is). Sweeps over all 1,114,112 code points
    // found exactly two kinds of difference between Unicode 16 and Unicode 17 that
    // CQT can observe, and no General_Category difference at all in the classes CQT
    // reads (Cc, Ps, Pi, Pe, Pf).
    //
    // First: one decomposition mapping.
    //
    //     U+A7F1 MODIFIER LETTER CAPITAL S  ->  "S"   (assigned in Unicode 17)
    //
    // U+A7F1 has ccc=0 and its compatibility decomposition is the single scalar "S",
    // which also has ccc=0, so substituting before normalization is exactly
    // equivalent to a Unicode 17 NFKC: NFKD would have performed the same
    // replacement in the same position, and the canonical composition that follows
    // then sees identical input.
    private static final String UNICODE_DELTA_FROM = "꟱";
    private static final String UNICODE_DELTA_TO = "S";

    // Second: five combining marks whose Canonical_Combining_Class changed from 0
    // (a starter) to a non-zero value. Under Unicode 16 a JDK normalizer treats them
    // as starters, so they act as barriers to canonical ordering and to composition;
    // under Unicode 17 they are marks that sort by class and let a following mark
    // compose with the base before them. "a" + U+1ADD + U+0301 is "a U+1ADD U+0301"
    // under 16 and "á U+1ADD" under 17.
    //
    // None of the five has a decomposition and none is the second element of a
    // primary composite, so their only effect on NFKC is through their class. That
    // makes them interchangeable, for normalization purposes, with any other mark of
    // the same class that also never composes -- which is what the correction below
    // exploits: swap each one for such a proxy, let the JDK's own Unicode 16 tables
    // do the ordering and composition, and swap back.
    //
    // {affected code point, the proxy that carries its Unicode 17 class}
    private static final int[][] CCC_DELTA = {
        {0x1ADD, 0x101FD},   // COMBINING DOT-AND-RING BELOW,        ccc 0 -> 220
        {0x1AE6, 0x101FD},   // COMBINING DOUBLE ARCH BELOW,         ccc 0 -> 220
        {0x10EFA, 0x101FD},  // ARABIC DOUBLE VERTICAL BAR BELOW,    ccc 0 -> 220
        {0x10EFB, 0x101FD},  // ARABIC SMALL LOW NOON,               ccc 0 -> 220
        {0x1AEB, 0x1DCD},    // COMBINING DOUBLE RIGHTWARDS ARROW ABOVE, ccc 0 -> 234
    };

    // The two proxies. U+101FD PHAISTOS DISC SIGN COMBINING OBLIQUE STROKE has ccc
    // 220 and U+1DCD COMBINING DOUBLE CIRCUMFLEX ABOVE has ccc 234, in Unicode 16 and
    // 17 alike. Neither has a decomposition, neither is the second element of a
    // primary composite, and neither appears in the compatibility decomposition of
    // any other scalar -- so normalization can neither manufacture one nor consume
    // one. Several occurrences of a proxy therefore come out of the normalizer in the
    // same relative order they went in: canonical ordering is a stable sort on class,
    // marks never cross a starter, and composition removes only marks that compose.
    // That is what lets one proxy stand in for four different characters at once, and
    // stand in for itself where the text already contained it -- restoration walks the
    // occurrences in order and puts each one back as what it was.
    private static final int CCC_PROXY_220 = 0x101FD;
    private static final int CCC_PROXY_234 = 0x1DCD;

    // ---------------------------------------------------------------- character sets

    private static boolean isWhiteSpace(int cp) {
        return (cp >= 0x0009 && cp <= 0x000D)
                || cp == 0x0020 || cp == 0x0085 || cp == 0x00A0 || cp == 0x1680
                || (cp >= 0x2000 && cp <= 0x200A)
                || cp == 0x2028 || cp == 0x2029 || cp == 0x202F || cp == 0x205F
                || cp == 0x3000;
    }

    private static boolean isDashPunctuation(int cp) {
        switch (cp) {
            case 0x002D: case 0x058A: case 0x05BE: case 0x1400: case 0x1806:
            case 0x2010: case 0x2011: case 0x2012: case 0x2013: case 0x2014:
            case 0x2015: case 0x2E17: case 0x2E1A: case 0x2E3A: case 0x2E3B:
            case 0x2E40: case 0x2E5D: case 0x301C: case 0x3030: case 0x30A0:
            case 0xFE31: case 0xFE32: case 0xFE58: case 0xFE63: case 0xFF0D:
            case 0x10D6E: case 0x10EAD:
                return true;
            default:
                return false;
        }
    }

    private static boolean isQuoteCharacter(int cp) {
        switch (cp) {
            case 0x0022: case 0x2018: case 0x2019: case 0x201C: case 0x201D:
            case 0x00AB: case 0x00BB: case 0x2039: case 0x203A:
            case 0x3008: case 0x3009: case 0x300A: case 0x300B:
            case 0x300C: case 0x300D:
                return true;
            default:
                return false;
        }
    }

    private static boolean isRemovedInvisible(int cp) {
        return cp == 0x00AD || cp == 0x200B || cp == 0x2060 || cp == 0xFEFF;
    }

    // Unicode 17.0.0 Terminal_Punctuation, from PropList.txt. Punctuation that ends
    // a sentence, clause or word, and so attaches to the text on its LEFT. The ASCII
    // members are exactly ! , . : ; ? -- deliberately NOT the whole Po category,
    // which would drag in the solidus and turn "A & B / C" into "A & B/ C", nor the
    // apostrophe, which the quote fold has already made ambiguous.
    private static final String[] TERMINAL_PUNCTUATION_RANGES = {
        "0021", "002C", "002E", "003A-003B", "003F", "037E", "0387", "0589", "05C3",
        "060C", "061B", "061D-061F", "06D4", "0700-070A", "070C", "07F8-07F9",
        "0830-0835", "0837-083E", "085E", "0964-0965", "0E5A-0E5B", "0F08",
        "0F0D-0F12", "104A-104B", "1361-1368", "166E", "16EB-16ED", "1735-1736",
        "17D4-17D6", "17DA", "1802-1805", "1808-1809", "1944-1945", "1AA8-1AAB",
        "1B4E-1B4F", "1B5A-1B5B", "1B5D-1B5F", "1B7D-1B7F", "1C3B-1C3F", "1C7E-1C7F",
        "2024", "203C-203D", "2047-2049", "2CF9-2CFB", "2E2E", "2E3C", "2E41", "2E4C",
        "2E4E-2E4F", "2E53-2E54", "3001-3002", "A4FE-A4FF", "A60D-A60F", "A6F3-A6F7",
        "A876-A877", "A8CE-A8CF", "A92F", "A9C7-A9C9", "AA5D-AA5F", "AADF",
        "AAF0-AAF1", "ABEB", "FE12", "FE15-FE16", "FE50-FE52", "FE54-FE57", "FF01",
        "FF0C", "FF0E", "FF1A-FF1B", "FF1F", "FF61", "FF64", "1039F", "103D0", "10857",
        "1091F", "10A56-10A57", "10AF0-10AF5", "10B3A-10B3F", "10B99-10B9C",
        "10F55-10F59", "10F86-10F89", "11047-1104D", "110BE-110C1", "11141-11143",
        "111C5-111C6", "111CD", "111DE-111DF", "11238-1123C", "112A9", "113D4-113D5",
        "1144B-1144D", "1145A-1145B", "115C2-115C5", "115C9-115D7", "11641-11642",
        "1173C-1173E", "11944", "11946", "11A42-11A43", "11A9B-11A9C", "11AA1-11AA2",
        "11C41-11C43", "11C71", "11EF7-11EF8", "11F43-11F44", "12470-12474",
        "16A6E-16A6F", "16AF5", "16B37-16B39", "16B44", "16D6E-16D6F", "16E97-16E98",
        "1BC9F", "1DA87-1DA8A",
    };

    // Unicode 17.0.0 Line_Break=SA, from LineBreak.txt: the scripts that do not
    // separate words with spaces and therefore need explicit break opportunities --
    // Thai, Lao, Khmer, Myanmar, Tai Tham, New Tai Lue, Ahom. In these scripts
    // U+200B is a real word separator rather than a layout artifact.
    private static final String[] SPACELESS_SCRIPT_RANGES = {
        "0E01-0E3A", "0E40-0E4E", "0E81-0E82", "0E84", "0E86-0E8A", "0E8C-0EA3",
        "0EA5", "0EA7-0EBD", "0EC0-0EC4", "0EC6", "0EC8-0ECE", "0EDC-0EDF",
        "1000-103F", "1050-108F", "109A-109F", "1780-17D3", "17D7", "17DC-17DD",
        "1950-196D", "1970-1974", "1980-19AB", "19B0-19C9", "19DE-19DF", "1A20-1A5E",
        "1A60-1A7C", "1AA0-1AAD", "A9E0-A9EF", "A9FA-A9FE", "AA60-AAC2", "AADB-AADF",
        "11700-1171A", "1171D-1172B", "1173A-1173B", "1173F-11746",
    };

    private static final int[][] TERMINAL_PUNCTUATION = parseRanges(TERMINAL_PUNCTUATION_RANGES);
    private static final int[][] SPACELESS_SCRIPTS = parseRanges(SPACELESS_SCRIPT_RANGES);

    private static int[][] parseRanges(String[] items) {
        int[][] out = new int[items.length][2];
        for (int i = 0; i < items.length; i++) {
            int dash = items[i].indexOf('-');
            if (dash < 0) {
                out[i][0] = Integer.parseInt(items[i], 16);
                out[i][1] = out[i][0];
            } else {
                out[i][0] = Integer.parseInt(items[i].substring(0, dash), 16);
                out[i][1] = Integer.parseInt(items[i].substring(dash + 1), 16);
            }
        }
        java.util.Arrays.sort(out, (a, b) -> Integer.compare(a[0], b[0]));
        return out;
    }

    private static boolean inRanges(int[][] ranges, int cp) {
        int lo = 0;
        int hi = ranges.length - 1;
        while (lo <= hi) {
            int mid = (lo + hi) >>> 1;
            if (cp < ranges[mid][0]) {
                hi = mid - 1;
            } else if (cp > ranges[mid][1]) {
                lo = mid + 1;
            } else {
                return true;
            }
        }
        return false;
    }

    private static boolean isTerminalPunctuation(int cp) {
        return inRanges(TERMINAL_PUNCTUATION, cp);
    }

    private static boolean isSpacelessScript(int cp) {
        return inRanges(SPACELESS_SCRIPTS, cp);
    }

    private static boolean isPeOrPf(int cp) {
        int type = Character.getType(cp);
        return type == Character.END_PUNCTUATION || type == Character.FINAL_QUOTE_PUNCTUATION;
    }

    private static boolean isPsOrPi(int cp) {
        int type = Character.getType(cp);
        return type == Character.START_PUNCTUATION || type == Character.INITIAL_QUOTE_PUNCTUATION;
    }

    // ---------------------------------------------------------------- autocorrect

    // Spelled numerically because the characters themselves are invisible in source.
    /** U+FE0F VARIATION SELECTOR-16, which asks for the emoji rendering. */
    private static final String VARIATION_SELECTOR_16 = Character.toString(0xFE0F);
    /** U+FE0E VARIATION SELECTOR-15, which asks for the text rendering. */
    private static final String VARIATION_SELECTOR_15 = Character.toString(0xFE0E);

    private static final String[][] AUTOCORRECT_BASE = {
        {"😊", ":-)"},          // U+1F60A
        {"😐", ":-|"},          // U+1F610
        {"☹", ":-("},           // U+2639
        {"😃", ":-D"},          // U+1F603
        {"😝", ":-p"},          // U+1F61D
        {"😲", ":-o"},          // U+1F632
        {"😉", ";-)"},          // U+1F609
        {"❤", "<3"},            // U+2764
        {"💔", "</3"},          // U+1F494
        {"©", "(c)"},           // U+00A9
        {"®", "(R)"},           // U+00AE
        {"•", "*"},             // U+2022
    };

    // A trailing variation selector belongs to the character it follows, for every
    // entry rather than the two that happened to be spelled out. U+FE0F asks for the
    // emoji rendering and U+FE0E for the text rendering; neither changes what the
    // character is, and pickers and keyboards add them without the user knowing. So
    // all three spellings of one character have to converge, which is what this step
    // exists to do. A selector form of each source is listed before the bare one, so
    // the longer source is always tried first.
    private static final String[][] AUTOCORRECT_PAIRS = withVariationSelectors(AUTOCORRECT_BASE);

    private static String[][] withVariationSelectors(String[][] base) {
        String[][] out = new String[base.length * 3][];
        for (int i = 0; i < base.length; i++) {
            out[3 * i] = new String[] {base[i][0] + VARIATION_SELECTOR_16, base[i][1]};
            out[3 * i + 1] = new String[] {base[i][0] + VARIATION_SELECTOR_15, base[i][1]};
            out[3 * i + 2] = base[i];
        }
        return out;
    }

    private static final String[][] ASCII_AUTOCORRECT_PAIRS = {
        {":)", ":-)"},
        {":|", ":-|"},
        {":(", ":-("},
        {":D", ":-D"},
        {":p", ":-p"},
        {":o", ":-o"},
        {";)", ";-)"},
    };

    // ---------------------------------------------------------------- patterns

    private static final Pattern FENCE_OPEN = Pattern.compile("^ {0,3}(`{3,})[^`\r\n]*$");
    private static final Pattern MULTI_HYPHEN = Pattern.compile("-{2,}");
    private static final Pattern LONG_DOTS = Pattern.compile("\\.{4,}");
    // The marker is built from NUL deliberately. Step 2 strips every Cc scalar from
    // the input before protection runs, so the text provably cannot contain one and a
    // marker cannot be forged. A marker made of noncharacters could be: an input
    // holding U+FDD0 CQT0 U+FDEF used to have span 0's content substituted into it.
    // Like U+FDD0, NUL is neither whitespace nor punctuation to any later step, so it
    // stands in for a span the way the spec requires.
    private static final String MARKER_OPEN = "\0";
    private static final String MARKER_CLOSE = "\0";
    private static final Pattern PROTECTED_MARKER = Pattern.compile("\0CQT[0-9]+\0");

    // ---------------------------------------------------------------- public API

    /** Return the CQT 2.17 canonical UTF-8 byte stream for {@code plaintext}. */
    public static byte[] algorithm217(String plaintext) {
        if (plaintext == null) {
            throw new NullPointerException("plaintext must not be null");
        }
        // Strip what cannot be plain text BEFORE recognizing anything. Otherwise an
        // override hidden inside a fence or a URL is copied through untouched, and
        // the span becomes a channel for exactly the spoof this removal prevents.
        String stripped = stripDisallowed(plaintext);
        Map<String, String> protectedSpans = new LinkedHashMap<>();
        String text = protect(stripped, protectedSpans);
        text = canonicalizeProse(text);
        text = restore(text, protectedSpans);
        return text.getBytes(StandardCharsets.UTF_8);
    }

    /** Convenience wrapper returning the canonical text rather than its bytes. */
    public static String canonicalize(String plaintext) {
        return new String(algorithm217(plaintext), StandardCharsets.UTF_8);
    }

    // ---------------------------------------------------------------- step 2

    /**
     * Remove what cannot belong to plain text.
     *
     * <p>Three groups, all artifacts rather than writing. Control characters outside
     * the White_Space set -- NUL and its neighbours -- are not plain text. Unpaired
     * surrogates are not Unicode scalar values at all and have no UTF-8 encoding; a
     * well-formed pair is one character and is left alone. And the two directional
     * overrides, LRO (U+202D) and RLO (U+202E), force every character in their scope
     * to render in a chosen direction regardless of what the character is, which is
     * an instruction to a rendering engine rather than a statement about the text.
     *
     * <p>The other bidi controls stay. Marks (ALM, LRM, RLM) only affect how
     * neighbouring neutral characters resolve, and isolates (LRI, RLI, FSI, PDI)
     * scope a direction without overriding anything.
     */
    private static String stripDisallowed(String text) {
        StringBuilder out = new StringBuilder(text.length());
        int i = 0;
        int n = text.length();
        while (i < n) {
            char c = text.charAt(i);
            if (c >= 0xD800 && c <= 0xDBFF) {
                if (i + 1 < n) {
                    char low = text.charAt(i + 1);
                    if (low >= 0xDC00 && low <= 0xDFFF) {
                        // A well-formed pair is one astral character, not two errors.
                        out.append(c).append(low);
                        i += 2;
                        continue;
                    }
                }
                i++;
                continue;
            }
            if (c >= 0xDC00 && c <= 0xDFFF) {
                i++;
                continue;
            }
            if (Character.getType(c) == Character.CONTROL && !isWhiteSpace(c)) {
                i++;
                continue;
            }
            if (c == 0x202D || c == 0x202E) {
                // The only two scalars whose Bidi_Class is LRO or RLO.
                i++;
                continue;
            }
            out.append(c);
            i++;
        }
        return out.toString();
    }

    // ---------------------------------------------------------------- step 3: spans

    private static final class Span {
        final int start;
        final int end;

        Span(int start, int end) {
            this.start = start;
            this.end = end;
        }
    }

    private static String lineBody(String line) {
        if (line.endsWith("\r\n")) {
            return line.substring(0, line.length() - 2);
        }
        if (line.endsWith("\r") || line.endsWith("\n")) {
            return line.substring(0, line.length() - 1);
        }
        return line;
    }

    /** Split on LF, CR and CRLF, keeping each line ending attached to its line. */
    private static List<String> linesWithEndings(String text) {
        List<String> lines = new ArrayList<>();
        int start = 0;
        int i = 0;
        int n = text.length();
        while (i < n) {
            char c = text.charAt(i);
            if (c == '\r') {
                i += (i + 1 < n && text.charAt(i + 1) == '\n') ? 2 : 1;
                lines.add(text.substring(start, i));
                start = i;
            } else if (c == '\n') {
                i += 1;
                lines.add(text.substring(start, i));
                start = i;
            } else {
                i++;
            }
        }
        if (start < n) {
            lines.add(text.substring(start));
        }
        return lines;
    }

    private static List<Span> fencedSpans(String text) {
        List<String> lines = linesWithEndings(text);
        List<Span> spans = new ArrayList<>();
        int[] offsets = new int[lines.size()];
        int offset = 0;
        for (int k = 0; k < lines.size(); k++) {
            offsets[k] = offset;
            offset += lines.get(k).length();
        }

        int i = 0;
        while (i < lines.size()) {
            Matcher opening = FENCE_OPEN.matcher(lineBody(lines.get(i)));
            if (!opening.matches()) {
                i++;
                continue;
            }

            int fenceLength = opening.group(1).length();
            Pattern closing = Pattern.compile("^ {0,3}`{" + fenceLength + ",}[ \t]*$");
            int j = i + 1;
            while (j < lines.size() && !closing.matcher(lineBody(lines.get(j))).matches()) {
                j++;
            }
            if (j == lines.size()) {
                // No closing line, so the pattern is not present. A run of backticks
                // in prose is prose. Failing to match is not an error; human text has
                // no syntax to get wrong.
                i++;
                continue;
            }

            int start = offsets[i];
            if (start >= 2 && text.startsWith("\r\n", start - 2)) {
                start -= 2;
            } else if (start > 0 && (text.charAt(start - 1) == '\r' || text.charAt(start - 1) == '\n')) {
                start -= 1;
            }
            if (!spans.isEmpty()) {
                start = Math.max(start, spans.get(spans.size() - 1).end);
            }
            int end = offsets[j] + lines.get(j).length();
            spans.add(new Span(start, end));
            i = j + 1;
        }
        return spans;
    }

    private static int indexOfWithin(String text, String needle, int from, int limit) {
        int last = limit - needle.length();
        for (int i = Math.max(from, 0); i <= last; i++) {
            if (text.startsWith(needle, i)) {
                return i;
            }
        }
        return -1;
    }

    private static int matchingBacktickRun(String text, int start, int limit, int length) {
        String needle = "`".repeat(length);
        int candidate = indexOfWithin(text, needle, start, limit);
        while (candidate != -1) {
            boolean beforeIsTick = candidate > start && text.charAt(candidate - 1) == '`';
            int after = candidate + length;
            boolean afterIsTick = after < limit && text.charAt(after) == '`';
            if (!beforeIsTick && !afterIsTick) {
                return candidate;
            }
            candidate = indexOfWithin(text, needle, candidate + length, limit);
        }
        return -1;
    }

    private static int urlEnd(String text, int start, int limit) {
        int i = start;
        int parenDepth = 0;
        while (i < limit) {
            char c = text.charAt(i);
            // The Cc test is unreachable defence in depth: stripDisallowed has already
            // removed every Cc scalar that is not White_Space, and the White_Space ones
            // terminate on the first test. Kept so a reordering of the passes cannot
            // silently swallow a control character into a URL.
            if (isWhiteSpace(c) || c == '<' || c == '>' || c == '"' || c == '`'
                    || Character.getType(c) == Character.CONTROL) {
                break;
            }
            if (c == '(') {
                parenDepth++;
            } else if (c == ')') {
                if (parenDepth == 0) {
                    break;
                }
                parenDepth--;
            }
            i++;
        }
        return i;
    }

    /**
     * Match {@code https?://} at {@code i}, ASCII-case-insensitively, and return the
     * offset just past the scheme, or -1.
     *
     * <p>The ASCII restriction is load-bearing. A Unicode case fold makes U+017F
     * LATIN SMALL LETTER LONG S match the "s" of "https", so "http{U+017F}://..."
     * would be protected as a URL. RFC 3986 section 3.1 restricts a scheme to ASCII
     * ALPHA, so that match is simply wrong. In Java, Pattern.CASE_INSENSITIVE without
     * Pattern.UNICODE_CASE is already ASCII-only; this hand-rolled comparison makes
     * the property explicit and independent of flag choices.
     */
    private static int matchUrlScheme(String text, int i, int limit) {
        if (asciiEqualsIgnoreCase(text, i, limit, "https://")) {
            return i + 8;
        }
        if (asciiEqualsIgnoreCase(text, i, limit, "http://")) {
            return i + 7;
        }
        return -1;
    }

    private static boolean asciiEqualsIgnoreCase(String text, int at, int limit, String lowerNeedle) {
        if (at + lowerNeedle.length() > limit) {
            return false;
        }
        for (int k = 0; k < lowerNeedle.length(); k++) {
            char c = text.charAt(at + k);
            if (c >= 'A' && c <= 'Z') {
                c = (char) (c + 32);
            }
            if (c != lowerNeedle.charAt(k)) {
                return false;
            }
        }
        return true;
    }

    private static void inlineAndUrlSpans(String text, int start, int end, List<Span> spans) {
        int i = start;
        while (i < end) {
            if (text.charAt(i) == '`') {
                int runEnd = i + 1;
                while (runEnd < end && text.charAt(runEnd) == '`') {
                    runEnd++;
                }
                int runLength = runEnd - i;
                int closing = matchingBacktickRun(text, runEnd, end, runLength);
                if (closing != -1) {
                    int spanEnd = closing + runLength;
                    spans.add(new Span(i, spanEnd));
                    i = spanEnd;
                    continue;
                }
                // An unmatched run is ordinary prose in its entirety, so resume AFTER
                // it. Advancing one character would re-examine a proper suffix of the
                // run as a shorter run, which can pair with a later run and protect
                // text the prose rules should have normalized.
                i = runEnd;
                continue;
            }

            int schemeEnd = matchUrlScheme(text, i, end);
            if (schemeEnd != -1) {
                int spanEnd = urlEnd(text, schemeEnd, end);
                spans.add(new Span(i, spanEnd));
                i = spanEnd;
                continue;
            }
            i++;
        }
    }

    /** Fenced code blocks first, then inline code spans and URLs in what remains. */
    private static List<Span> opaqueSpans(String text) {
        List<Span> fences = fencedSpans(text);
        List<Span> spans = new ArrayList<>();
        int cursor = 0;
        for (Span fence : fences) {
            inlineAndUrlSpans(text, cursor, fence.start, spans);
            spans.add(fence);
            cursor = fence.end;
        }
        inlineAndUrlSpans(text, cursor, text.length(), spans);
        return spans;
    }

    private static String protect(String text, Map<String, String> protectedSpans) {
        List<Span> spans = opaqueSpans(text);
        if (spans.isEmpty()) {
            return text;
        }
        StringBuilder out = new StringBuilder(text.length());
        int cursor = 0;
        int markerNumber = 0;
        for (Span span : spans) {
            String marker = MARKER_OPEN + "CQT" + markerNumber + MARKER_CLOSE;
            markerNumber++;
            out.append(text, cursor, span.start);
            out.append(marker);
            protectedSpans.put(marker, text.substring(span.start, span.end));
            cursor = span.end;
        }
        out.append(text, cursor, text.length());
        return out.toString();
    }

    private static String restore(String text, Map<String, String> protectedSpans) {
        if (protectedSpans.isEmpty()) {
            return text;
        }
        Matcher matcher = PROTECTED_MARKER.matcher(text);
        StringBuilder out = new StringBuilder(text.length());
        int cursor = 0;
        while (matcher.find()) {
            out.append(text, cursor, matcher.start());
            String replacement = protectedSpans.get(matcher.group());
            // Unreachable now that the marker is made of NUL, since no marker-shaped
            // run can survive step 2. Kept because CQT 2.17 never rejects text, so a
            // marker without an entry has to come out as the text it is.
            out.append(replacement != null ? replacement : matcher.group());
            cursor = matcher.end();
        }
        out.append(text, cursor, text.length());
        return out.toString();
    }

    // ---------------------------------------------------------------- steps 4-7

    /**
     * One pass, in order. Nothing here runs twice.
     *
     * <p>The autocorrect tables run before space removal. A client that swaps an emoji
     * for its emoticon spelling, or the reverse, is exactly the kind of tooling
     * transformation CQT exists to survive, so "hello <emoji>", "hello :)" and
     * "hello :-)" must all reach the same bytes. Mapping to the canonical spelling
     * first puts a colon where the space rule can see it.
     *
     * <p>The cost of a single pass is that ": )" ends at ":)" rather than ":-)", since
     * nothing revisits the tables after the space closes the gap.
     */
    private static String canonicalizeProse(String text) {
        text = normalizeNfkc17(text);
        text = removeInvisibles(text);
        text = collapseUnicodeWhitespace(text);
        text = mapCodePoints(text, cp -> isDashPunctuation(cp) ? "-" : null);
        text = MULTI_HYPHEN.matcher(text).replaceAll("-");
        text = text.replace("、", ",").replace("。", ".");
        text = text.replace("…", "...");
        text = LONG_DOTS.matcher(text).replaceAll("...");
        text = text.replace("⁄", "/");
        text = mapCodePoints(text, cp -> isQuoteCharacter(cp) ? "'" : null);
        for (String[] pair : AUTOCORRECT_PAIRS) {
            text = text.replace(pair[0], pair[1]);
        }
        for (String[] pair : ASCII_AUTOCORRECT_PAIRS) {
            text = text.replace(pair[0], pair[1]);
        }
        text = removeSpacesAdjacentToPunctuation(text);
        text = text.replace("&", " & ");
        return collapseUnicodeWhitespace(text);
    }

    /**
     * Step 4: NFKC as Unicode 17.0.0 defines it, on a runtime whose tables are older.
     *
     * <p>See UNICODE_DELTA_FROM and CCC_DELTA above for what is being corrected and
     * why each correction is exact. When the text contains none of the six affected
     * scalars -- which is the case for essentially all text -- this is the JDK's own
     * NFKC and nothing else.
     */
    private static String normalizeNfkc17(String text) {
        text = text.replace(UNICODE_DELTA_FROM, UNICODE_DELTA_TO);

        boolean affected = false;
        for (int[] delta : CCC_DELTA) {
            if (text.indexOf(delta[0]) >= 0) {
                affected = true;
                break;
            }
        }
        if (!affected) {
            return java.text.Normalizer.normalize(text, java.text.Normalizer.Form.NFKC);
        }

        // Rewrite every affected mark, and every pre-existing occurrence of a proxy,
        // as that proxy, remembering in order what each occurrence really was.
        List<Integer> tags220 = new ArrayList<>();
        List<Integer> tags234 = new ArrayList<>();
        StringBuilder substituted = new StringBuilder(text.length());
        int i = 0;
        while (i < text.length()) {
            int cp = text.codePointAt(i);
            i += Character.charCount(cp);
            int proxy = proxyFor(cp);
            if (proxy == CCC_PROXY_220) {
                tags220.add(cp);
            } else if (proxy == CCC_PROXY_234) {
                tags234.add(cp);
            }
            substituted.appendCodePoint(proxy >= 0 ? proxy : cp);
        }

        String normalized = java.text.Normalizer.normalize(
                substituted.toString(), java.text.Normalizer.Form.NFKC);

        StringBuilder out = new StringBuilder(normalized.length());
        int next220 = 0;
        int next234 = 0;
        int j = 0;
        while (j < normalized.length()) {
            int cp = normalized.codePointAt(j);
            j += Character.charCount(cp);
            if (cp == CCC_PROXY_220 && next220 < tags220.size()) {
                out.appendCodePoint(tags220.get(next220++));
            } else if (cp == CCC_PROXY_234 && next234 < tags234.size()) {
                out.appendCodePoint(tags234.get(next234++));
            } else {
                out.appendCodePoint(cp);
            }
        }
        return out.toString();
    }

    /** The proxy standing in for {@code cp} during normalization, or -1 for none. */
    private static int proxyFor(int cp) {
        if (cp == CCC_PROXY_220 || cp == CCC_PROXY_234) {
            return cp;
        }
        for (int[] delta : CCC_DELTA) {
            if (delta[0] == cp) {
                return delta[1];
            }
        }
        return -1;
    }

    private interface CodePointMapper {
        /** Return the replacement for {@code cp}, or null to keep it as it is. */
        String map(int cp);
    }

    private static String mapCodePoints(String text, CodePointMapper mapper) {
        StringBuilder out = new StringBuilder(text.length());
        int i = 0;
        int n = text.length();
        while (i < n) {
            int cp = text.codePointAt(i);
            String replacement = mapper.map(cp);
            if (replacement != null) {
                out.append(replacement);
            } else {
                out.appendCodePoint(cp);
            }
            i += Character.charCount(cp);
        }
        return out.toString();
    }

    /**
     * Step 5: drop the four layout-only characters.
     *
     * <p>U+200B survives between two scalars from a script that does not separate
     * words with spaces, where it is the word separator rather than an artifact. Both
     * neighbours must qualify, so a stray U+200B injected at a script boundary by a
     * mailer or sanitizer is still removed. Neighbours are scalars, not UTF-16 code
     * units: two of the qualifying scripts (Ahom, U+11700..U+11746) are astral.
     */
    private static String removeInvisibles(String text) {
        StringBuilder out = new StringBuilder(text.length());
        int i = 0;
        int n = text.length();
        while (i < n) {
            int cp = text.codePointAt(i);
            int width = Character.charCount(cp);
            if (!isRemovedInvisible(cp)) {
                out.appendCodePoint(cp);
                i += width;
                continue;
            }
            if (cp == 0x200B) {
                int before = i > 0 ? text.codePointBefore(i) : -1;
                int after = (i + width) < n ? text.codePointAt(i + width) : -1;
                if (before >= 0 && after >= 0 && isSpacelessScript(before) && isSpacelessScript(after)) {
                    out.appendCodePoint(cp);
                }
            }
            i += width;
        }
        return out.toString();
    }

    /** Step 6: each run of White_Space becomes one U+0020, then leading/trailing spaces go. */
    private static String collapseUnicodeWhitespace(String text) {
        StringBuilder out = new StringBuilder(text.length());
        boolean inWhitespace = false;
        for (int i = 0; i < text.length(); i++) {
            char c = text.charAt(i);
            if (isWhiteSpace(c)) {
                if (!inWhitespace) {
                    out.append(' ');
                }
                inWhitespace = true;
            } else {
                out.append(c);
                inWhitespace = false;
            }
        }
        // Python's str.strip(" ") trims ASCII spaces only; String.strip() would trim
        // Unicode whitespace, which is a different operation.
        int begin = 0;
        int end = out.length();
        while (begin < end && out.charAt(begin) == ' ') {
            begin++;
        }
        while (end > begin && out.charAt(end - 1) == ' ') {
            end--;
        }
        return out.substring(begin, end);
    }

    /**
     * Step 7.9: attach punctuation to the side it belongs to.
     *
     * <p>Punctuation is not symmetric. Opening punctuation binds to what follows it and
     * closing, final and terminal punctuation bind to what precedes, so a space is
     * removed on the side the punctuation attaches to and left alone on the other.
     * That keeps "ignorance, up" and "name: value" intact while still converging
     * "hello :)" and "hello {U+1F60A}" on "hello:-)".
     */
    private static String removeSpacesAdjacentToPunctuation(String text) {
        StringBuilder out = new StringBuilder(text.length());
        int n = text.length();
        int cursor = 0;
        int i = 0;
        while (i < n) {
            if (text.charAt(i) != ' ') {
                i++;
                continue;
            }
            int runStart = i;
            while (i < n && text.charAt(i) == ' ') {
                i++;
            }
            int runEnd = i;
            out.append(text, cursor, runStart);
            int before = runStart > 0 ? text.codePointBefore(runStart) : -1;
            int after = runEnd < n ? text.codePointAt(runEnd) : -1;
            boolean attachesLeft = after >= 0 && (isTerminalPunctuation(after) || isPeOrPf(after));
            boolean attachesRight = before >= 0 && isPsOrPi(before);
            if (!(attachesLeft || attachesRight)) {
                out.append(' ');
            }
            cursor = runEnd;
        }
        out.append(text, cursor, n);
        return out.toString();
    }

    // ---------------------------------------------------------------- conformance

    public static void main(String[] args) throws IOException {
        System.exit(Conformance.run(args));
    }
}

/**
 * The conformance runner. It lives in this file because the single-file source
 * launcher ({@code java Cqt.java}) compiles exactly one source file, and this repo
 * has no build tool.
 */
final class Conformance {

    private Conformance() {
    }

    static int run(String[] args) throws IOException {
        Path goldens = locate(args.length > 0 ? args[0] : null);
        if (goldens == null) {
            System.err.println("cannot find ../../goldens/cqt2.17.json; pass its path as the first argument");
            return 2;
        }
        String source = Files.readString(goldens, StandardCharsets.UTF_8);
        Object root = MiniJson.parse(source);
        Map<String, Object> doc = MiniJson.asObject(root);

        System.out.println("vectors:  " + goldens.toAbsolutePath());
        System.out.println("algorithm: " + doc.get("algorithm") + "  unicode: " + doc.get("unicode_version"));
        System.out.println("runtime:   Java " + System.getProperty("java.version")
                + "  (JDK Unicode 16 tables, corrected to " + Cqt.UNICODE_VERSION + ")");

        List<Object> cases = MiniJson.asArray(doc.get("cases"));
        int passed = 0;
        List<String> failures = new ArrayList<>();
        for (Object element : cases) {
            Map<String, Object> vector = MiniJson.asObject(element);
            String id = (String) vector.get("id");
            String input = (String) vector.get("input");
            String expected = (String) vector.get("output");
            byte[] expectedBytes = expected.getBytes(StandardCharsets.UTF_8);
            byte[] actualBytes;
            try {
                actualBytes = Cqt.algorithm217(input);
            } catch (RuntimeException e) {
                failures.add(id + "\n    threw " + e);
                continue;
            }
            if (java.util.Arrays.equals(expectedBytes, actualBytes)) {
                passed++;
            } else {
                failures.add(id
                        + "\n    input:    " + describe(input)
                        + "\n    expected: " + describe(expected)
                        + "\n    actual:   " + describe(new String(actualBytes, StandardCharsets.UTF_8)));
            }
        }

        for (String failure : failures) {
            System.out.println("FAIL " + failure);
        }
        System.out.println();
        System.out.println(passed + "/" + cases.size() + " vectors pass");
        return failures.isEmpty() ? 0 : 1;
    }

    private static Path locate(String explicit) {
        List<String> candidates = new ArrayList<>();
        if (explicit != null) {
            candidates.add(explicit);
        }
        candidates.add("../../goldens/cqt2.17.json");
        candidates.add("../../../goldens/cqt2.17.json");
        for (String candidate : candidates) {
            Path path = Path.of(candidate);
            if (Files.isReadable(path)) {
                return path;
            }
        }
        return null;
    }

    /** Render a string with every non-printable or non-ASCII scalar as U+XXXX. */
    private static String describe(String s) {
        StringBuilder out = new StringBuilder("\"");
        int i = 0;
        while (i < s.length()) {
            int cp = s.codePointAt(i);
            i += Character.charCount(cp);
            if (cp >= 0x20 && cp < 0x7F) {
                out.append((char) cp);
            } else {
                out.append(String.format("<U+%04X>", cp));
            }
        }
        return out.append('"').toString();
    }
}

/** A minimal JSON reader: enough for the machine-generated golden file, no more. */
final class MiniJson {

    private final String src;
    private int pos;

    private MiniJson(String src) {
        this.src = src;
    }

    static Object parse(String src) {
        MiniJson parser = new MiniJson(src);
        parser.skipWhitespace();
        Object value = parser.readValue();
        parser.skipWhitespace();
        if (parser.pos != src.length()) {
            throw new IllegalArgumentException("trailing data at offset " + parser.pos);
        }
        return value;
    }

    @SuppressWarnings("unchecked")
    static Map<String, Object> asObject(Object value) {
        return (Map<String, Object>) value;
    }

    @SuppressWarnings("unchecked")
    static List<Object> asArray(Object value) {
        return (List<Object>) value;
    }

    private void skipWhitespace() {
        while (pos < src.length()) {
            char c = src.charAt(pos);
            if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
                pos++;
            } else {
                return;
            }
        }
    }

    private char peek() {
        if (pos >= src.length()) {
            throw new IllegalArgumentException("unexpected end of input");
        }
        return src.charAt(pos);
    }

    private void expect(char c) {
        if (peek() != c) {
            throw new IllegalArgumentException("expected '" + c + "' at offset " + pos);
        }
        pos++;
    }

    private Object readValue() {
        char c = peek();
        switch (c) {
            case '{':
                return readObject();
            case '[':
                return readArray();
            case '"':
                return readString();
            case 't':
                return readLiteral("true", Boolean.TRUE);
            case 'f':
                return readLiteral("false", Boolean.FALSE);
            case 'n':
                return readLiteral("null", null);
            default:
                return readNumber();
        }
    }

    private Object readLiteral(String word, Object value) {
        if (!src.startsWith(word, pos)) {
            throw new IllegalArgumentException("bad literal at offset " + pos);
        }
        pos += word.length();
        return value;
    }

    private Object readNumber() {
        int start = pos;
        while (pos < src.length() && "+-.eE0123456789".indexOf(src.charAt(pos)) >= 0) {
            pos++;
        }
        if (start == pos) {
            throw new IllegalArgumentException("unexpected character at offset " + pos);
        }
        return Double.valueOf(src.substring(start, pos));
    }

    private Map<String, Object> readObject() {
        expect('{');
        Map<String, Object> out = new LinkedHashMap<>();
        skipWhitespace();
        if (peek() == '}') {
            pos++;
            return out;
        }
        while (true) {
            skipWhitespace();
            String key = readString();
            skipWhitespace();
            expect(':');
            skipWhitespace();
            out.put(key, readValue());
            skipWhitespace();
            char c = peek();
            pos++;
            if (c == '}') {
                return out;
            }
            if (c != ',') {
                throw new IllegalArgumentException("expected ',' or '}' at offset " + (pos - 1));
            }
        }
    }

    private List<Object> readArray() {
        expect('[');
        List<Object> out = new ArrayList<>();
        skipWhitespace();
        if (peek() == ']') {
            pos++;
            return out;
        }
        while (true) {
            skipWhitespace();
            out.add(readValue());
            skipWhitespace();
            char c = peek();
            pos++;
            if (c == ']') {
                return out;
            }
            if (c != ',') {
                throw new IllegalArgumentException("expected ',' or ']' at offset " + (pos - 1));
            }
        }
    }

    /**
     * Read a JSON string. A \\uXXXX escape is appended as a single UTF-16 code unit,
     * so a surrogate pair written as two escapes becomes one astral scalar and a lone
     * surrogate escape stays lone -- which is what the algorithm's first step is for.
     */
    private String readString() {
        expect('"');
        StringBuilder out = new StringBuilder();
        while (true) {
            char c = src.charAt(pos++);
            if (c == '"') {
                return out.toString();
            }
            if (c != '\\') {
                out.append(c);
                continue;
            }
            char esc = src.charAt(pos++);
            switch (esc) {
                case '"': out.append('"'); break;
                case '\\': out.append('\\'); break;
                case '/': out.append('/'); break;
                case 'b': out.append('\b'); break;
                case 'f': out.append('\f'); break;
                case 'n': out.append('\n'); break;
                case 'r': out.append('\r'); break;
                case 't': out.append('\t'); break;
                case 'u':
                    out.append((char) Integer.parseInt(src.substring(pos, pos + 4), 16));
                    pos += 4;
                    break;
                default:
                    throw new IllegalArgumentException("bad escape \\" + esc + " at offset " + (pos - 1));
            }
        }
    }
}
