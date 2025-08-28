import Foundation

public struct Cqt {
    // MARK: - Public API

    /// Returns the canonical quoted text as UTF-8 data (same as Python function's `.encode("UTF-8")`).
    public static func canonicalQuotedData(from plaintext: String) -> Data {
        let s = canonicalQuotedString(from: plaintext)
        return s.data(using: .utf8) ?? Data()
    }

    /// Returns the canonical quoted text as String.
    public static func canonicalQuotedString(from plaintext: String) -> String {
        // Step 2: NFKC normalization
        // NSString.precomposedStringWithCompatibilityMapping approximates NFKC (compatibility composition).
        var x = (plaintext as NSString).precomposedStringWithCompatibilityMapping

        // Step 3: ampersands -> " and "
        x = replacingRegex(pattern: "[&\\uFE60\\uFF06]", in: x, with: " and ")

        // Step 4: specialized whitespace -> single space, trim, collapse multi-whitespace
        x = replacingRegex(pattern: "[\\u2028\\u2029\\u200B\\uFEFF\\u00A0\\u3000\\r\\n\\t]+", in: x, with: " ")
        x = x.trimmingCharacters(in: .whitespacesAndNewlines)
        x = replacingRegex(pattern: "\\s{2,}", in: x, with: " ")

        // Step 5: punctuation anomalies and others
        // 5.i replace many dash chars with '-'
        x = replacingRegex(pattern: "[\\u058A\\u05BE\\u1400\\u1806\\u2010\\u2011\\u2012\\u2013\\u2014\\u2015\\u2e17\\u2e1a\\u2e3a\\u2e3b\\u2e40\\u2e5d\\u301c\\u3030\\u30a0\\ufe31\\ufe32\\ufe58\\ufe63\\uff0d]+", in: x, with: "-")

        // 5.ii collapse multiple hyphens to single hyphen
        x = replacingRegex(pattern: "-{2,}", in: x, with: "-")

        // 5.iii CJK punctuation pairs
        let cjkPairs: [(String, String)] = [
            ("\u{3001}", ","), // IDEOGRAPHIC COMMA
            ("\u{3002}", ".")  // IDEOGRAPHIC FULL STOP
        ]
        for (cjk, ascii) in cjkPairs {
            x = x.replacingOccurrences(of: cjk, with: ascii)
        }

        // 5.iii (continued): fullwidth ASCII FF01..FF5E -> convert to ASCII by subtracting 0xFEE0
        x = mapFullwidthAsciiToAscii(x)

        // 5.iv replace HORIZONTAL ELLIPSIS with "..."
        x = x.replacingOccurrences(of: "\u{2026}", with: "...")

        // 5.v collapse long dots (4 or more) to "..."
        x = replacingRegex(pattern: "[.]{4,}", in: x, with: "...")

        // 5.vi replace fraction slash with '/'
        x = x.replacingOccurrences(of: "\u{2044}", with: "/")

        // 5.vii replace various quote characters with single quote
        x = replacingRegex(pattern: "[\"\u{2018}\u{2019}\u{201C}\u{201D}\u{00AB}\u{00BB}\u{2039}\u{203A}\u{3008}\u{3009}\u{300A}\u{300B}\u{300C}\u{300D}]", in: x, with: "'")

        // 5.viii whitespace around punctuation: remove whitespace when whitespace is adjacent to punctuation
        x = collapseWhitespaceAroundPunctuation(in: x)

        // 5.ix replace some unicode glyphs with ASCII pairs (autocorrect)
        let autocorrectPairs: [(String, String)] = [
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
            ("\u{2022}", "*")
        ]
        for (from, to) in autocorrectPairs {
            x = x.replacingOccurrences(of: from, with: to)
        }

        // 5.x replace ASCII emoji variants with canonical longer forms
        let asciiEmojiPairs: [(String, String)] = [
            (":)", ":-)"),
            (":|", ":-|"),
            (":(", ":-("),
            (":D", ":-D"),
            (":p", ":-p"),
            (":o", ":-o"),
            (";)", ";-)")
        ]
        for (from, to) in asciiEmojiPairs {
            x = x.replacingOccurrences(of: from, with: to)
        }

        // Step 6: return bytes (done in canonicalQuotedData), but we return String here
        return x
    }

    // MARK: - Helpers

    /// Replace using NSRegularExpression
    private static func replacingRegex(pattern: String, in text: String, with replacement: String) -> String {
        do {
            let re = try NSRegularExpression(pattern: pattern, options: [])
            let range = NSRange(location: 0, length: (text as NSString).length)
            return re.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacement)
        } catch {
            return text
        }
    }

    /// Convert fullwidth ASCII U+FF01..U+FF5E to ASCII by subtracting 0xFEE0
    private static func mapFullwidthAsciiToAscii(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        out.reserveCapacity(text.unicodeScalars.count)
        for scalar in text.unicodeScalars {
            let v = scalar.value
            if 0xFF01...0xFF5E ~= v {
                if let newScalar = Unicode.Scalar(v - 0xFEE0) {
                    out.append(newScalar)
                } else {
                    out.append(scalar)
                }
            } else {
                out.append(scalar)
            }
        }
        return String(out)
    }

    /// Remove whitespace when it's adjacent to punctuation characters.
    ///
    /// Algorithm: iterate over ANY_WHITESPACE_PAT matches (captures whitespace sequences).
    /// Keep a whitespace sequence only if the previous character is not punctuation and the next character is not punctuation.
    private static func collapseWhitespaceAroundPunctuation(in text: String) -> String {
        // Pattern to capture any run of whitespace
        let pattern = "(\\s+)"
        guard let re = try? NSRegularExpression(pattern: pattern, options: []) else {
            return text
        }
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        var result = ""
        var lastIndex = 0

        let matches = re.matches(in: text, options: [], range: fullRange)
        for match in matches {
            let matchRange = match.range(at: 1)
            // append substring before the whitespace
            let prefixRange = NSRange(location: lastIndex, length: matchRange.location - lastIndex)
            if prefixRange.length > 0 {
                result += nsText.substring(with: prefixRange)
            }

            // decide whether to keep this whitespace
            var keepSpace = true

            // check previous character (if any)
            if matchRange.location > 0 {
                let prevCharRange = NSRange(location: matchRange.location - 1, length: 1)
                let prevChar = nsText.substring(with: prevCharRange)
                if let prevScalar = prevChar.unicodeScalars.first, isPunctuationScalar(prevScalar) {
                    keepSpace = false
                }
            }

            // check next character (if any)
            let nextIndex = matchRange.location + matchRange.length
            if nextIndex < nsText.length {
                let nextCharRange = NSRange(location: nextIndex, length: 1)
                let nextChar = nsText.substring(with: nextCharRange)
                if let nextScalar = nextChar.unicodeScalars.first, isPunctuationScalar(nextScalar) {
                    keepSpace = false
                }
            }

            if keepSpace {
                // append the original whitespace sequence
                result += nsText.substring(with: matchRange)
            }
            lastIndex = matchRange.location + matchRange.length
        }

        // append the remainder of the string
        if lastIndex < nsText.length {
            let tailRange = NSRange(location: lastIndex, length: nsText.length - lastIndex)
            result += nsText.substring(with: tailRange)
        }

        return result
    }

    /// Determine if a Unicode scalar is punctuation (category starts with "P").
    private static func isPunctuationScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .connectorPunctuation,
             .dashPunctuation,
             .openPunctuation,
             .closePunctuation,
             .initialPunctuation,
             .finalPunctuation,
             .otherPunctuation:
            return true
        default:
            return false
        }
    }
}
