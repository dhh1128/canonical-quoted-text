// NOTE: THIS CODE WAS PORTED FROM THE PYTHON REFERENCE IMPLEMENTATION BY AN AI.
// DO NOT USE WITHOUT PROVING IT IS CORRECT. ONCE YOU'VE PROVED THAT, PLEASE SUBMIT
// A PR THAT REMOVES THIS WARNING FROM THE FILE.
import java.util.regex.Pattern;

public class Cqt {
    private static final Pattern AMPERS_PAT = Pattern.compile("[&\uFE60\uFF06]");
    private static final Pattern SPECIALIZED_WHITESPACE_PAT = Pattern.compile("[\u2028\u2029\u200B\uFEFF\u00A0\u3000\r\n\t]+");
    private static final Pattern MULTI_WHITESPACE_PAT = Pattern.compile("\\s{2,}");
    private static final Pattern DASHCHARS_PAT = Pattern.compile("[\u058A\u05BE\u1400\u1806\u2010\u2011\u2012\u2013\u2014\u2015\u2e17\u2e1a\u2e3a\u2e3b\u2e40\u2e5d\u301c\u3030\u30a0\ufe31\ufe32\ufe58\ufe63\uff0d]+");
    private static final Pattern MULTI_HYPHENS_PAT = Pattern.compile("-{2,}");
    private static final String[][] CJK_PUNCT_PAIRS = {
        {"\u3001", ","},
        {"\u3002", "."}
    };
    private static final Pattern LONG_DOTS_PAT = Pattern.compile("[.]{4,}");
    private static final Pattern QUOTERS_PAT = Pattern.compile("['\u2018\u2019\u201C\u201D\u00AB\u00BB\u2039\u203A\u3008\u3009\u300A\u300B\u300C\u300D]");
    private static final Pattern ANY_WHITESPACE_PAT = Pattern.compile("(\\s+)");
    private static final String[][] AUTOCORRECT_PAIRS = {
        {"\u1f60A", ":-)"},
        {"\u1f610", ":-|"},
        {"\u2639", ":-("},
        {"\u1f603", ":-D"},
        {"\u1f61D", ":-p"},
        {"\u1f632", ":-o"},
        {"\u1f609", ";-)"},
        {"\u2764", "<3"},
        {"\u1f494", "</3"},
        {"\u00a9", "(c)"},
        {"\u00ae", "(R)"},
        {"\u2022", "*"}
    };
    private static final String[][] ASCII_EMOJI_PAIRS = {
        {":)", ":-)"},
        {":|", ":-|"},
        {":(", ":-("},
        {":D", ":-D"},
        {":p", ":-p"},
        {":o", ":-o"},
        {";)", ";-)"}
    };

    public static String algorithm_1_14(String plaintext) {
        // We start with step 1 already complete, since Java strings are already Unicode.

        // step 2
        String x = java.text.Normalizer.normalize(plaintext, java.text.Normalizer.Form.NFKC);

        // step 3
        x = step3(x);

        // step 4
        x = step4(x);

        // step 5
        x = step5(x);

        return x;
    }

    private static String step3(String ampersands) {
        return AMPERS_PAT.matcher(ampersands).replaceAll(" and ");
    }

    private static String step4(String whitespaceAnomalies) {
        String out = SPECIALIZED_WHITESPACE_PAT.matcher(whitespaceAnomalies).replaceAll(" ");
        out = out.trim();
        out = MULTI_WHITESPACE_PAT.matcher(out).replaceAll(" ");
        return out;
    }

    private static String step5(String punctAnomalies) {
        // 5.i
        String out = DASHCHARS_PAT.matcher(punctAnomalies).replaceAll("-");
        // 5.ii
        out = MULTI_HYPHENS_PAT.matcher(out).replaceAll("-");
        // 5.iii
        for (String[] pair : CJK_PUNCT_PAIRS) {
            out = out.replace(pair[0], pair[1]);
        }
        StringBuilder txt = new StringBuilder();
        for (char c : out.toCharArray()) {
            int n = (int) c;
            if (0xFF01 <= n && n <= 0xFF5E) {
                c = (char) (n - 0xFEE0);
            }
            txt.append(c);
        }
        // 5.iv
        out = txt.toString().replace("\u2026", "...");
        // 5.v
        out = LONG_DOTS_PAT.matcher(out).replaceAll("...");
        // 5.vi
        out = out.replace("\u2044", "/");
        // 5.vii
        out = QUOTERS_PAT.matcher(out).replaceAll("'");
        txt = new StringBuilder();
        int next = 0;
        // 5.viii
        java.util.regex.Matcher matcher = ANY_WHITESPACE_PAT.matcher(out);
        while (matcher.find()) {
            boolean keepSpace = true;
            int i = matcher.start();
            if (i > 0) {
                txt.append(out, next, i);
                if (Character.getType(out.charAt(i - 1)) == Character.CONNECTOR_PUNCTUATION) {
                    keepSpace = false;
                }
            }
            next = matcher.end();
            if (next < out.length()) {
                if (Character.getType(out.charAt(next)) == Character.CONNECTOR_PUNCTUATION) {
                    keepSpace = false;
                }
            }
            if (keepSpace) {
                txt.append(matcher.group(1));
            }
        }
        txt.append(out, next, out.length());
        out = txt.toString();
        // 5.ix

        return out;
    }
}
