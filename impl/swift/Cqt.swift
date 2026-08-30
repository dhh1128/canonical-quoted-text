// Canonical Quoted Text 3.17 — Swift port.
//
// The algorithm is specified in ../../README.md and pinned by the vectors in
// ../../goldens/cqt3.17.json. Every operation that consults the Unicode
// Character Database must use Unicode 17.0.0.
//
// Two Swift-specific hazards shape this file.
//
// 1. The algorithm is defined on Unicode scalar values. `String` is a
//    collection of `Character` (grapheme clusters), which would silently glue a
//    base character to a following combining mark or variation selector, so
//    everything here works on `[Unicode.Scalar]`.
//
// 2. `String` equality compares under canonical equivalence, so
//    `"\u{0340}" == "\u{0300}"` is true. Output is therefore returned as UTF-8
//    bytes, and the tests compare bytes.
//
// See `nfkc17` for why normalization is not simply delegated to Foundation.

import Foundation

public enum Cqt {

    // MARK: - Public API

    /// The Unicode edition every property lookup below must use.
    public static let unicodeVersion = "17.0.0"

    /// The CQT 3.17 canonical form of `plaintext`, as the UTF-8 byte stream of
    /// step 9. This is what a hash or a signature is taken over.
    public static func algorithm317(_ plaintext: String) -> [UInt8] {
        var view = String.UnicodeScalarView()
        for scalar in canonicalScalars(Array(plaintext.unicodeScalars)) { view.append(scalar) }
        return Array(String(view).utf8)
    }

    /// The CQT 3.17 canonical form of `plaintext`, as a `String`. Convenience
    /// for callers that are not about to hash the bytes.
    ///
    /// Prefer `algorithm317(_:)` when comparing: `String` equality in Swift is
    /// canonical-equivalence equality, which is not what CQT means by "same".
    public static func canonicalize(_ plaintext: String) -> String {
        String(decoding: algorithm317(plaintext), as: UTF8.self)
    }

    // MARK: - The algorithm

    static func canonicalScalars(_ input: [Unicode.Scalar]) -> [Unicode.Scalar] {
        // Step 1 is the caller's: text arrives as Unicode scalars. Swift's
        // `String` cannot hold an unpaired surrogate, so step 2.1 has already
        // happened by the time any input reaches us.
        var plain = makePlain(input)                            // step 2.1-2.3
        plain = removeArtifacts(plain)                          // step 2.4
        plain = normalizeLineTerminators(plain)                 // step 2.5
        plain = rightTrimLines(plain)                           // step 2.6
        let (prose, spans) = setAsideProtectedSpans(plain)      // step 3
        var text = nfkc17(prose)                                // step 4
        text = removeInvisibles(text)                           // step 5
        text = normalizeQuotation(text)                         // step 6.1
        text = normalizeWhitespace(text)                        // step 6.2-6.3
        text = normalizePunctuation(text)                       // step 7
        return restore(spans, into: text)                       // step 8
    }

    // MARK: - Step 2: finish making the text plain

    static func makePlain(_ scalars: [Unicode.Scalar]) -> [Unicode.Scalar] {
        scalars.filter { scalar in
            let v = scalar.value
            // 2.2 — General_Category Cc, except the six that are White_Space.
            // Cc is U+0000..U+001F and U+007F..U+009F, fixed for all time.
            if v <= 0x1F || (v >= 0x7F && v <= 0x9F) {
                return (v >= 0x09 && v <= 0x0D) || v == 0x85
            }
            // 2.3 — the two directional overrides.
            return v != 0x202D && v != 0x202E
        }
    }

    /// Step 2.4: drop the byte order mark. U+FEFF is a serialization signature
    /// rather than writing, so it is not text and does not belong to the author.
    /// Removing it here, before recognition, is why it also comes out of a fence.
    static func removeArtifacts(_ scalars: [Unicode.Scalar]) -> [Unicode.Scalar] {
        scalars.filter { $0.value != 0xFEFF }
    }

    static func isLineTerminator(_ v: UInt32) -> Bool {
        (v >= 0x0A && v <= 0x0D) || v == 0x85 || v == 0x2028 || v == 0x2029
    }

    static func isHorizontalWhiteSpace(_ v: UInt32) -> Bool {
        isWhiteSpace(v) && v != 0x0A
    }

    /// Step 2.5: every line terminator becomes LF. Prose is unaffected, because
    /// step 6.2 collapses any of them to one space either way; what changes is
    /// the interior of a protected span, where CRLF and LF used to give
    /// different bytes for the same block. MIME text/plain is CRLF-canonical.
    static func normalizeLineTerminators(_ scalars: [Unicode.Scalar]) -> [Unicode.Scalar] {
        var out: [Unicode.Scalar] = []
        out.reserveCapacity(scalars.count)
        var i = 0
        while i < scalars.count {
            if scalars[i].value == 0x0D, i + 1 < scalars.count, scalars[i + 1].value == 0x0A {
                out.append("\u{000A}")
                i += 2
                continue
            }
            out.append(isLineTerminator(scalars[i].value) ? "\u{000A}" : scalars[i])
            i += 1
        }
        return out
    }

    /// Step 2.6: remove the whole run of horizontal whitespace before a line
    /// ending or the end of the input. A pending run is emitted verbatim
    /// otherwise -- emitting spaces instead would turn a tab inside an inline
    /// code span into a space, which is not this step's business.
    static func rightTrimLines(_ scalars: [Unicode.Scalar]) -> [Unicode.Scalar] {
        var out: [Unicode.Scalar] = []
        out.reserveCapacity(scalars.count)
        var pending: [Unicode.Scalar] = []
        for scalar in scalars {
            if isHorizontalWhiteSpace(scalar.value) {
                pending.append(scalar)
                continue
            }
            if scalar.value != 0x0A { out += pending }
            pending.removeAll(keepingCapacity: true)
            out.append(scalar)
        }
        return out
    }

    // MARK: - Step 3: protected content

    /// A protected span, as half-open scalar offsets into the step-2 text.
    enum SpanKind { case fence, inline, url }

    struct Span {
        let start: Int
        let end: Int
        let kind: SpanKind
    }

    /// A line of the input: content is `[start, contentEnd)`, its line ending
    /// (LF, CR or CRLF, empty at end of input) is `[contentEnd, end)`.
    private struct Line {
        let start: Int
        let contentEnd: Int
        let end: Int
    }

    static func setAsideProtectedSpans(
        _ scalars: [Unicode.Scalar]
    ) -> ([Unicode.Scalar], [[Unicode.Scalar]]) {
        var spans: [Span] = []
        var cursor = 0
        for fence in fenceSpans(scalars) {
            spans += inlineAndURLSpans(scalars, from: cursor, to: fence.start)
            spans.append(fence)
            cursor = fence.end
        }
        spans += inlineAndURLSpans(scalars, from: cursor, to: scalars.count)

        var prose: [Unicode.Scalar] = []
        var contents: [[Unicode.Scalar]] = []
        prose.reserveCapacity(scalars.count)
        cursor = 0
        for span in spans {
            prose += scalars[cursor..<span.start]
            prose += placeholder(contents.count)
            contents.append(normalizeSpan(span.kind, Array(scalars[span.start..<span.end])))
            cursor = span.end
        }
        prose += scalars[cursor...]
        return (prose, contents)
    }

    /// U+0000 CQT <ordinal> U+0000. Step 2 removed U+0000 from the input, so a
    /// placeholder cannot be forged; and no step between 4 and 7 touches NUL,
    /// the three ASCII letters or the ASCII digits.
    static func placeholder(_ ordinal: Int) -> [Unicode.Scalar] {
        var out: [Unicode.Scalar] = ["\u{0000}", "C", "Q", "T"]
        for ch in String(ordinal).unicodeScalars { out.append(ch) }
        out.append("\u{0000}")
        return out
    }

    // MARK: Step 3: fenced code blocks

    private static func lines(_ scalars: [Unicode.Scalar]) -> [Line] {
        var out: [Line] = []
        var start = 0
        var i = 0
        while i < scalars.count {
            let v = scalars[i].value
            if v == 0x0A {
                out.append(Line(start: start, contentEnd: i, end: i + 1))
                i += 1
                start = i
            } else {
                i += 1
            }
        }
        out.append(Line(start: start, contentEnd: scalars.count, end: scalars.count))
        return out
    }

    /// Length of the backtick run of an opening fence, or nil.
    private static func openingFenceRun(_ scalars: [Unicode.Scalar], _ line: Line) -> Int? {
        var i = line.start
        while i < line.contentEnd && isHorizontalWhiteSpace(scalars[i].value) {
            i += 1
        }
        var run = 0
        while i < line.contentEnd && scalars[i].value == 0x60 {
            run += 1
            i += 1
        }
        if run < 3 { return nil }
        // The info string may hold anything except another backtick.
        while i < line.contentEnd {
            if scalars[i].value == 0x60 { return nil }
            i += 1
        }
        return run
    }

    private static func isClosingFence(
        _ scalars: [Unicode.Scalar], _ line: Line, atLeast opening: Int
    ) -> Bool {
        var i = line.start
        while i < line.contentEnd && isHorizontalWhiteSpace(scalars[i].value) {
            i += 1
        }
        var run = 0
        while i < line.contentEnd && scalars[i].value == 0x60 {
            run += 1
            i += 1
        }
        if run < opening { return false }
        while i < line.contentEnd {
            if !isHorizontalWhiteSpace(scalars[i].value) { return false }
            i += 1
        }
        return true
    }

    private static func fenceSpans(_ scalars: [Unicode.Scalar]) -> [Span] {
        let rows = lines(scalars)
        var spans: [Span] = []
        var claimed = 0   // end of the previous span; a line ending it took is gone
        var i = 0
        while i < rows.count {
            guard let run = openingFenceRun(scalars, rows[i]) else {
                i += 1
                continue
            }
            var closer = -1
            var j = i + 1
            while j < rows.count {
                if isClosingFence(scalars, rows[j], atLeast: run) {
                    closer = j
                    break
                }
                j += 1
            }
            var start = rows[i].start
            if i > 0 && rows[i - 1].contentEnd >= claimed {
                start = rows[i - 1].contentEnd   // take the preceding line ending
            }
            // An opener with no closer runs to the end of the input rather than
            // decaying into prose. Truncation is ordinary, and under the old
            // rule losing one line reinterpreted a whole block.
            if closer < 0 {
                spans.append(Span(start: start, end: scalars.count, kind: .fence))
                break
            }
            spans.append(Span(start: start, end: rows[closer].end, kind: .fence))
            claimed = rows[closer].end
            i = closer + 1
        }
        return spans
    }

    // MARK: Step 3: inline code spans and HTTP(S) URLs

    /// Scans one prose segment left to right, taking whichever span begins first.
    private static func inlineAndURLSpans(
        _ scalars: [Unicode.Scalar], from lo: Int, to hi: Int
    ) -> [Span] {
        var spans: [Span] = []
        var i = lo
        while i < hi {
            if scalars[i].value == 0x60 {
                var runEnd = i
                while runEnd < hi && scalars[runEnd].value == 0x60 { runEnd += 1 }
                let run = runEnd - i
                if let closer = matchingBacktickRun(scalars, from: runEnd, to: hi, length: run) {
                    spans.append(Span(start: i, end: closer + run, kind: .inline))
                    i = closer + run
                } else {
                    i = runEnd   // an unmatched run is prose in its entirety
                }
                continue
            }
            if let end = urlSpanEnd(scalars, from: i, to: hi) {
                spans.append(Span(start: i, end: end, kind: .url))
                i = end
                continue
            }
            i += 1
        }
        return spans
    }

    /// Start of the next maximal backtick run of exactly `length`.
    private static func matchingBacktickRun(
        _ scalars: [Unicode.Scalar], from lo: Int, to hi: Int, length: Int
    ) -> Int? {
        var i = lo
        while i < hi {
            guard scalars[i].value == 0x60 else {
                i += 1
                continue
            }
            var end = i
            while end < hi && scalars[end].value == 0x60 { end += 1 }
            if end - i == length { return i }
            i = end
        }
        return nil
    }

    /// End of the URL span starting at `i`, or nil if no scheme matches there.
    private static func urlSpanEnd(
        _ scalars: [Unicode.Scalar], from i: Int, to hi: Int
    ) -> Int? {
        // ASCII-only case folding: a Unicode case fold would let U+017F match
        // "s" and protect text that is not a URL.
        func matches(_ scheme: [UInt8]) -> Bool {
            guard i + scheme.count <= hi else { return false }
            for (k, expected) in scheme.enumerated() {
                let v = scalars[i + k].value
                let lowered = (v >= 0x41 && v <= 0x5A) ? v + 0x20 : v
                if lowered != UInt32(expected) { return false }
            }
            return true
        }
        func isTokenScalar(_ v: UInt32) -> Bool {
            if v <= 0x20 || v >= 0x7F { return false }
            return ![0x28, 0x29, 0x3C, 0x3E, 0x40, 0x2C, 0x3B, 0x3A,
                     0x5C, 0x22, 0x2F, 0x5B, 0x5D, 0x3F, 0x3D].contains(v)
        }
        func runOfTokens(_ at: Int) -> Int? {
            var k = at
            while k < hi && isTokenScalar(scalars[k].value) { k += 1 }
            return k > at ? k : nil
        }
        /// An RFC 2397 header: optional type/subtype, zero or more
        /// ";attribute=value" parameters, an optional ";base64", and the
        /// mandatory comma. Returns the offset just past the comma.
        func dataHeader(_ at: Int) -> Int? {
            var k = at
            if let slash = runOfTokens(k), slash < hi, scalars[slash].value == 0x2F,
               let after = runOfTokens(slash + 1) {
                k = after
            }
            while k < hi && scalars[k].value == 0x3B {
                if matchesAt(k, base64Flag), k + 7 < hi, scalars[k + 7].value == 0x2C {
                    return k + 8
                }
                guard let name = runOfTokens(k + 1), name < hi, scalars[name].value == 0x3D,
                      let value = runOfTokens(name + 1) else { return nil }
                k = value
            }
            return (k < hi && scalars[k].value == 0x2C) ? k + 1 : nil
        }
        func matchesAt(_ at: Int, _ want: [UInt8]) -> Bool {
            guard at + want.count <= hi else { return false }
            for (k, expected) in want.enumerated() {
                let v = scalars[at + k].value
                let lowered = (v >= 0x41 && v <= 0x5A) ? v + 0x20 : v
                if lowered != UInt32(expected) { return false }
            }
            return true
        }

        // Three forms. Any scheme followed by "://" is safe because "://" does
        // not occur in prose; a bare scheme is not, because "note:" and "here
        // is the data:" are ordinary English. The two bare schemes admitted
        // here carry structure a sentence does not.
        var p: Int
        let first = scalars[i].value
        let isAlpha = (first >= 0x41 && first <= 0x5A) || (first >= 0x61 && first <= 0x7A)
        var schemeEnd = i + 1
        if isAlpha {
            while schemeEnd < hi {
                let v = scalars[schemeEnd].value
                let ok = (v >= 0x41 && v <= 0x5A) || (v >= 0x61 && v <= 0x7A)
                    || (v >= 0x30 && v <= 0x39) || v == 0x2B || v == 0x2D || v == 0x2E
                if !ok { break }
                schemeEnd += 1
            }
        }
        if isAlpha && matchesAt(schemeEnd, slashes) {
            p = schemeEnd + 3
        } else if matches(mailtoScheme) {
            var n = i + mailtoScheme.count
            var found = false
            while n < hi && !isWhiteSpace(scalars[n].value) {
                if scalars[n].value == 0x40 { found = true; break }
                n += 1
            }
            if !found { return nil }
            p = i + mailtoScheme.count
        } else if matches(dataScheme) {
            guard let end = dataHeader(i + dataScheme.count) else { return nil }
            p = end
        } else {
            return nil
        }
        var depth = 0
        while p < hi {
            let v = scalars[p].value
            if isWhiteSpace(v) || v == 0x3C || v == 0x3E || v == 0x22 || v == 0x60 { break }
            if v == 0x28 {
                depth += 1
            } else if v == 0x29 {
                if depth == 0 { break }
                depth -= 1
            }
            p += 1
        }
        return p
    }

    private static let httpsScheme = Array("https://".utf8)
    private static let httpScheme = Array("http://".utf8)
    private static let mailtoScheme = Array("mailto:".utf8)
    private static let dataScheme = Array("data:".utf8)
    private static let slashes = Array("://".utf8)
    private static let base64Flag = Array(";base64".utf8)

    // MARK: - Step 4: NFKC, in Unicode 17.0.0

    /// Foundation's `precomposedStringWithCompatibilityMapping` is not usable
    /// here, on two counts, both measured against the reference implementation
    /// on Swift 6.1.3 / Linux:
    ///
    /// * It is Unicode 15.1. It lacks 57 compatibility mappings that Unicode 16
    ///   and 17 added (U+A7F1, the outlined alphanumerics at U+1CCD6, and the
    ///   Todhri / Tulu-Tigalari / Sunuwar / Kirat Rai composites), and it gives
    ///   combining class 0 to 34 marks that Unicode 17 gives a non-zero class.
    ///   A mark of class 0 blocks canonical composition, so that changes NFKC
    ///   for every sequence containing one.
    /// * Its composition pass is wrong even for Unicode 15 input. It truncates
    ///   a supplementary-plane starter to its low 16 bits before looking for a
    ///   composite, so `"a" + U+10041 + U+0301` normalizes to `"a" + U+00C1`;
    ///   it will not compose across a mark that came out of a decomposition, so
    ///   `"a" + U+0F73 + U+0301` fails to reach U+00E1; and it does not
    ///   re-compose a composite it has just formed, so U+0CC6 U+0CC2 U+0CD5
    ///   stops at U+0CCA U+0CD5 instead of reaching U+0CCB.
    ///
    /// Decomposition, in contrast, measured clean over all 1,112,064 scalar
    /// values: the only disagreements with Unicode 17 are the 57 missing
    /// mappings. So NFKD comes from Foundation with those 57 patched in on the
    /// way, and canonical ordering and canonical composition happen here, with
    /// Unicode 17 data.
    static func nfkc17(_ scalars: [Unicode.Scalar]) -> [Unicode.Scalar] {
        var patched: [Unicode.Scalar] = []
        patched.reserveCapacity(scalars.count)
        for scalar in scalars {
            if let replacement = decompositionPatches[scalar.value] {
                patched += replacement
            } else {
                patched.append(scalar)
            }
        }

        var view = String.UnicodeScalarView()
        view.reserveCapacity(patched.count)
        for scalar in patched { view.append(scalar) }
        let decomposed = (String(view) as NSString).decomposedStringWithCompatibilityMapping

        var out = Array(decomposed.unicodeScalars)
        canonicalOrder(&out)
        return compose(out)
    }

    /// Canonical_Combining_Class in Unicode 17.
    static func combiningClass(_ scalar: Unicode.Scalar) -> UInt8 {
        if let patched = combiningClassPatches[scalar.value] { return patched }
        return scalar.properties.canonicalCombiningClass.rawValue
    }

    /// Canonical ordering: a stable sort by combining class within each run of
    /// non-starters. Re-running it over Foundation's output is safe because the
    /// only scalars the two disagree about are the 34 that Foundation treats as
    /// starters, and a starter is a boundary nothing moves across; so no two
    /// scalars of equal Unicode 17 class can already have been swapped.
    static func canonicalOrder(_ scalars: inout [Unicode.Scalar]) {
        var i = 0
        while i < scalars.count {
            if combiningClass(scalars[i]) == 0 {
                i += 1
                continue
            }
            var end = i
            while end < scalars.count && combiningClass(scalars[end]) != 0 { end += 1 }
            // Insertion sort: stable, and these runs are tiny.
            var j = i + 1
            while j < end {
                let scalar = scalars[j]
                let cc = combiningClass(scalar)
                var k = j
                while k > i && combiningClass(scalars[k - 1]) > cc {
                    scalars[k] = scalars[k - 1]
                    k -= 1
                }
                scalars[k] = scalar
                j += 1
            }
            i = end
        }
    }

    /// Canonical composition, per UAX #15, over canonically ordered input.
    static func compose(_ scalars: [Unicode.Scalar]) -> [Unicode.Scalar] {
        var out: [Unicode.Scalar] = []
        out.reserveCapacity(scalars.count)
        var starter = -1                  // index in `out` of the live starter
        var lastClass: UInt8 = 0
        var appendedSinceStarter = false

        for scalar in scalars {
            let cc = combiningClass(scalar)
            // A character is blocked from the starter when something between
            // them has class 0 or a class no smaller than its own. The input is
            // canonically ordered, so the last thing appended decides.
            let blocked = appendedSinceStarter && lastClass >= cc
            if starter >= 0, !blocked,
               let composite = primaryComposite(out[starter].value, scalar.value) {
                out[starter] = Unicode.Scalar(composite)!
                continue
            }
            if cc == 0 {
                starter = out.count
                appendedSinceStarter = false
            } else {
                appendedSinceStarter = true
            }
            lastClass = cc
            out.append(scalar)
        }
        return out
    }

    private static let hangulSBase: UInt32 = 0xAC00
    private static let hangulLBase: UInt32 = 0x1100
    private static let hangulVBase: UInt32 = 0x1161
    private static let hangulTBase: UInt32 = 0x11A7
    private static let hangulVCount: UInt32 = 21
    private static let hangulTCount: UInt32 = 28
    private static let hangulSCount: UInt32 = 11172   // LCount * VCount * TCount

    static func primaryComposite(_ first: UInt32, _ second: UInt32) -> UInt32? {
        // Hangul composition is algorithmic and so is not in the table.
        let l = first &- hangulLBase
        if l < 19, second >= hangulVBase, second < hangulVBase + hangulVCount {
            return hangulSBase + (l * hangulVCount + (second - hangulVBase)) * hangulTCount
        }
        let s = first &- hangulSBase
        if s < hangulSCount, s % hangulTCount == 0,
           second > hangulTBase, second < hangulTBase + hangulTCount {
            return first + (second - hangulTBase)
        }
        return primaryComposites[UInt64(first) << 21 | UInt64(second)]
    }

    // MARK: - Step 5: invisible characters

    static func removeInvisibles(_ scalars: [Unicode.Scalar]) -> [Unicode.Scalar] {
        var out: [Unicode.Scalar] = []
        out.reserveCapacity(scalars.count)
        for (i, scalar) in scalars.enumerated() {
            switch scalar.value {
            case 0x00AD, 0x2060, 0xFEFF:
                continue
            case 0x200B:
                // Kept only between two characters that both have
                // Line_Break=SA. Neighbors are the characters adjacent in the
                // text as it stands when this step begins, not the ones that
                // survive it.
                let before = i > 0 ? scalars[i - 1].value : nil
                let after = i + 1 < scalars.count ? scalars[i + 1].value : nil
                guard let b = before, let a = after,
                      isLineBreakSA(b), isLineBreakSA(a) else { continue }
                out.append(scalar)
            default:
                out.append(scalar)
            }
        }
        return out
    }

    // MARK: - Span normalization

    private static func dropLeadingHorizontal(_ scalars: ArraySlice<Unicode.Scalar>) -> [Unicode.Scalar] {
        let out = Array(scalars)
        var i = 0
        while i < out.count && isHorizontalWhiteSpace(out[i].value) { i += 1 }
        return Array(out[i...])
    }

    /// Strip leading horizontal whitespace from a fence's delimiter lines. Only
    /// the two lines that are pure syntax; indentation inside the block is
    /// content -- it is what Python means -- and is never touched.
    static func normalizeFenceIndent(_ body: [Unicode.Scalar]) -> [Unicode.Scalar] {
        let rows = lines(body)
        // `lines` always appends a final row, empty when the body ends with a
        // line ending -- and a fence span does, having taken the one after its
        // closer. The closing delimiter is therefore the last row with content.
        let lastWithContent = rows.lastIndex { $0.start < $0.contentEnd } ?? rows.count - 1
        var fenceRun: Int? = nil
        var out: [Unicode.Scalar] = []
        for (index, row) in rows.enumerated() {
            var piece = Array(body[row.start..<row.end])
            if fenceRun == nil {
                if let run = openingFenceRun(body, row) {
                    fenceRun = run
                    piece = dropLeadingHorizontal(body[row.start..<row.end])
                }
                out += piece
                continue
            }
            if index == lastWithContent, let run = fenceRun,
               isClosingFence(body, row, atLeast: run) {
                piece = dropLeadingHorizontal(body[row.start..<row.end])
            }
            out += piece
        }
        return out
    }

    /// Each run of line endings inside an inline span, with any horizontal
    /// whitespace after it, becomes one space. That is what makes an inline
    /// span rewrap-safe, and it is the difference between the two
    /// backtick-delimited kinds: an inline span carries no line structure.
    static func foldInlineNewlines(_ body: [Unicode.Scalar]) -> [Unicode.Scalar] {
        var out: [Unicode.Scalar] = []
        var i = 0
        while i < body.count {
            if body[i].value != 0x0A {
                out.append(body[i])
                i += 1
                continue
            }
            while i < body.count
                && (body[i].value == 0x0A || isHorizontalWhiteSpace(body[i].value)) {
                i += 1
            }
            out.append(" ")
        }
        return out
    }

    private static func asciiLower(_ scalars: [Unicode.Scalar]) -> [Unicode.Scalar] {
        scalars.map { $0.value >= 0x41 && $0.value <= 0x5A
            ? Unicode.Scalar($0.value + 0x20)! : $0 }
    }

    /// Lowercase what RFC 2045 section 5.1 defines as case-insensitive and
    /// nothing else: the type, the subtype and each parameter's attribute NAME.
    /// A value is not case-insensitive in general, so it is reproduced exactly.
    /// ";base64" is an attribute name with no value and folds with them.
    private static func lowerDataHeader(_ header: [Unicode.Scalar]) -> [Unicode.Scalar] {
        var out: [Unicode.Scalar] = []
        var part: [Unicode.Scalar] = []
        var isFirst = true
        func emit() {
            if let eq = part.firstIndex(where: { $0.value == 0x3D }), !isFirst {
                out += asciiLower(Array(part[..<eq])) + Array(part[eq...])
            } else {
                out += asciiLower(part)
            }
            part.removeAll(keepingCapacity: true)
        }
        for scalar in header {
            if scalar.value == 0x3B {
                emit()
                isFirst = false
                out.append(";")
                continue
            }
            part.append(scalar)
        }
        emit()
        return out
    }

    /// Lowercase the scheme, and the host of a URI that has an authority; RFC
    /// 3986 defines both as case-insensitive. A data: URI carries its own
    /// case-insensitive fields, defined by RFC 2045. Nothing else folds.
    static func normalizeURI(_ body: [Unicode.Scalar]) -> [Unicode.Scalar] {
        func indexOf(_ needle: [UInt32], from: Int) -> Int? {
            guard body.count >= needle.count else { return nil }
            var i = from
            while i + needle.count <= body.count {
                var hit = true
                for (k, want) in needle.enumerated() where body[i + k].value != want {
                    hit = false
                    break
                }
                if hit { return i }
                i += 1
            }
            return nil
        }
        if let slash = indexOf([0x3A, 0x2F, 0x2F], from: 0), slash > 0 {
            let scheme = asciiLower(Array(body[..<slash]))
            let rest = Array(body[(slash + 3)...])
            var end = rest.count
            for (k, scalar) in rest.enumerated()
            where scalar.value == 0x2F || scalar.value == 0x3F || scalar.value == 0x23 {
                end = k
                break
            }
            var authority = Array(rest[..<end])
            let tail = Array(rest[end...])
            var userinfo: [Unicode.Scalar] = []
            if let at = authority.lastIndex(where: { $0.value == 0x40 }) {
                userinfo = Array(authority[...at])
                authority = Array(authority[(at + 1)...])
            }
            return scheme + Array("://".unicodeScalars) + userinfo + asciiLower(authority) + tail
        }
        guard let colon = body.firstIndex(where: { $0.value == 0x3A }) else { return body }
        let scheme = asciiLower(Array(body[..<colon]))
        guard String(String.UnicodeScalarView(scheme)) == "data" else {
            return scheme + Array(body[colon...])
        }
        guard let comma = body[(colon + 1)...].firstIndex(where: { $0.value == 0x2C }) else {
            return scheme + Array(body[colon...])
        }
        return scheme + [":"] + lowerDataHeader(Array(body[(colon + 1)..<comma]))
            + Array(body[comma...])
    }

    /// A protected span is not untouched bytes. It is text canonicalized under
    /// a reduced rule set: line structure belongs to the channel, everything
    /// else belongs to the author.
    static func normalizeSpan(_ kind: SpanKind, _ body: [Unicode.Scalar]) -> [Unicode.Scalar] {
        switch kind {
        case .fence: return normalizeFenceIndent(body)
        case .inline: return foldInlineNewlines(body)
        case .url: return normalizeURI(body)
        }
    }

    // MARK: - Step 6.1: quotation

    /// The marker first: a leading run of horizontal whitespace, a ">", and
    /// every following character that is horizontal whitespace or another ">"
    /// all become a single ">". A line that is nothing but the prefix is
    /// dropped, as is a blank line.
    ///
    /// Then the structure. Consecutive lines of the same kind are joined, so
    /// the number of markers stops tracking how a client wrapped the text; and
    /// the line ending is kept wherever the kind changes, so a quoted question
    /// cannot absorb the reply beneath it.
    static func normalizeQuotation(_ scalars: [Unicode.Scalar]) -> [Unicode.Scalar] {
        var parts: [[Unicode.Scalar]] = []
        var current: [[Unicode.Scalar]] = []
        var kind: Bool? = nil

        func flush(_ quoted: Bool) {
            var joined: [Unicode.Scalar] = quoted ? [">"] : []
            for (index, piece) in current.enumerated() {
                if index > 0 { joined.append(" ") }
                joined += piece
            }
            parts.append(joined)
            current.removeAll(keepingCapacity: true)
        }

        for row in lines(scalars) {
            var i = row.start
            while i < row.contentEnd && isHorizontalWhiteSpace(scalars[i].value) { i += 1 }
            let quoted = i < row.contentEnd && scalars[i].value == 0x3E
            if quoted {
                i += 1
                while i < row.contentEnd
                    && (scalars[i].value == 0x3E || isHorizontalWhiteSpace(scalars[i].value)) {
                    i += 1
                }
            } else {
                i = row.start
            }
            let body = Array(scalars[i..<row.contentEnd])
            if body.allSatisfy({ isWhiteSpace($0.value) }) { continue }
            if let previous = kind, previous != quoted { flush(previous) }
            kind = quoted
            current.append(body)
        }
        if let previous = kind { flush(previous) }

        var out: [Unicode.Scalar] = []
        for (index, part) in parts.enumerated() {
            if index > 0 { out.append("\u{000A}") }
            out += part
        }
        return out
    }

    // MARK: - Step 6.2: whitespace

    static func normalizeWhitespace(_ scalars: [Unicode.Scalar]) -> [Unicode.Scalar] {
        var out: [Unicode.Scalar] = []
        out.reserveCapacity(scalars.count)
        var i = 0
        while i < scalars.count {
            if isWhiteSpace(scalars[i].value) {
                var sawNewline = false
                while i < scalars.count && isWhiteSpace(scalars[i].value) {
                    if scalars[i].value == 0x0A { sawNewline = true }
                    i += 1
                }
                // A run collapses to one space, or to one line ending if it
                // contains one. Step 6.1 has already joined every line within a
                // passage, so the only line endings left are the boundaries it
                // chose to keep, and those carry meaning a space would destroy.
                out.append(sawNewline ? "\u{000A}" : " ")
            } else {
                out.append(scalars[i])
                i += 1
            }
        }
        return trimSpaces(out)
    }

    private static func trimSpaces(_ scalars: [Unicode.Scalar]) -> [Unicode.Scalar] {
        var lo = 0
        var hi = scalars.count
        while lo < hi && (scalars[lo].value == 0x20 || scalars[lo].value == 0x0A) { lo += 1 }
        while hi > lo && (scalars[hi - 1].value == 0x20 || scalars[hi - 1].value == 0x0A) { hi -= 1 }
        return Array(scalars[lo..<hi])
    }

    // MARK: - Step 7: punctuation

    static func normalizePunctuation(_ scalars: [Unicode.Scalar]) -> [Unicode.Scalar] {
        var text = scalars

        // 7.1 Dash_Punctuation becomes the ASCII hyphen.
        text = text.map { dashPunctuation.contains($0.value) ? "-" : $0 }

        // 7.2 A run of two or more hyphens becomes one.
        text = collapseRuns(text, of: 0x2D, keeping: 1)

        // 7.3 Ideographic comma and full stop.
        text = text.map { scalar in
            switch scalar.value {
            case 0x3001: return ","
            case 0x3002: return "."
            default: return scalar
            }
        }

        // 7.4 Ellipsis, then a run of four or more full stops becomes three.
        var expanded: [Unicode.Scalar] = []
        expanded.reserveCapacity(text.count)
        for scalar in text {
            if scalar.value == 0x2026 {
                expanded += [".", ".", "."]
            } else {
                expanded.append(scalar)
            }
        }
        text = collapseRuns(expanded, of: 0x2E, keeping: 3, whenLongerThan: 3)

        // 7.5 Fraction slash.
        text = text.map { $0.value == 0x2044 ? "/" : $0 }

        // 7.6 Every quote character becomes the ASCII apostrophe.
        text = text.map { quoteCharacters.contains($0.value) ? "'" : $0 }

        // 7.7 Autocorrect, absorbing one trailing variation selector.
        var undone: [Unicode.Scalar] = []
        undone.reserveCapacity(text.count)
        var i = 0
        while i < text.count {
            if let replacement = autocorrect[text[i].value] {
                undone += replacement
                i += 1
                if i < text.count, text[i].value == 0xFE0F || text[i].value == 0xFE0E {
                    i += 1   // exactly one selector is absorbed
                }
            } else {
                undone.append(text[i])
                i += 1
            }
        }
        text = undone

        // 7.8 ASCII emoticons gain their nose.
        var nosed: [Unicode.Scalar] = []
        nosed.reserveCapacity(text.count)
        i = 0
        while i < text.count {
            if i + 1 < text.count,
               let canonical = emoticons[UInt64(text[i].value) << 32 | UInt64(text[i + 1].value)],
               !isGuardedEmoticonBlocked(text, i) {
                nosed += canonical
                i += 2
            } else {
                nosed.append(text[i])
                i += 1
            }
        }
        text = nosed

        // 7.9 Punctuation attaches to the side it binds to.
        var attached: [Unicode.Scalar] = []
        attached.reserveCapacity(text.count)
        i = 0
        while i < text.count {
            guard text[i].value == 0x20 else {
                attached.append(text[i])
                i += 1
                continue
            }
            var end = i
            while end < text.count && text[end].value == 0x20 { end += 1 }
            let before = attached.last?.value
            let after = end < text.count ? text[end].value : nil
            var drop = false
            if let a = after, isCloseOrFinal(a) || isTerminalPunctuation(a) { drop = true }
            if let b = before, isOpenOrInitial(b) { drop = true }
            if !drop { attached += text[i..<end] }
            i = end
        }
        text = attached

        // 7.10 Every ampersand gets a space on each side.
        var spaced: [Unicode.Scalar] = []
        spaced.reserveCapacity(text.count)
        for scalar in text {
            if scalar.value == 0x26 {
                spaced += [" ", "&", " "]
            } else {
                spaced.append(scalar)
            }
        }
        return trimSpaces(collapseRuns(spaced, of: 0x20, keeping: 1))
    }

    /// Collapses each run of `value` longer than `threshold` down to `keeping`.
    private static func collapseRuns(
        _ scalars: [Unicode.Scalar], of value: UInt32, keeping: Int,
        whenLongerThan threshold: Int = 1
    ) -> [Unicode.Scalar] {
        var out: [Unicode.Scalar] = []
        out.reserveCapacity(scalars.count)
        var i = 0
        while i < scalars.count {
            guard scalars[i].value == value else {
                out.append(scalars[i])
                i += 1
                continue
            }
            var end = i
            while end < scalars.count && scalars[end].value == value { end += 1 }
            let run = end - i
            for _ in 0..<(run > threshold ? keeping : run) { out.append(scalars[i]) }
            i = end
        }
        return out
    }

    // MARK: - Step 8: put the spans back

    static func restore(
        _ contents: [[Unicode.Scalar]], into scalars: [Unicode.Scalar]
    ) -> [Unicode.Scalar] {
        guard !contents.isEmpty else { return scalars }
        var out: [Unicode.Scalar] = []
        out.reserveCapacity(scalars.count)
        var i = 0
        while i < scalars.count {
            if scalars[i].value == 0x0000,
               let found = readPlaceholder(scalars, at: i),
               found.ordinal < contents.count {
                out += contents[found.ordinal]
                i = found.end
                continue
            }
            out.append(scalars[i])
            i += 1
        }
        return out
    }

    private static func readPlaceholder(
        _ scalars: [Unicode.Scalar], at i: Int
    ) -> (ordinal: Int, end: Int)? {
        var p = i + 1
        for expected in "CQT".unicodeScalars {
            guard p < scalars.count, scalars[p] == expected else { return nil }
            p += 1
        }
        var digits = ""
        while p < scalars.count, scalars[p].value >= 0x30, scalars[p].value <= 0x39 {
            digits.unicodeScalars.append(scalars[p])
            p += 1
        }
        guard !digits.isEmpty, p < scalars.count, scalars[p].value == 0x0000,
              let ordinal = Int(digits) else { return nil }
        return (ordinal, p + 1)
    }

    // MARK: - Character sets from the specification

    /// Unicode 17 `White_Space`, enumerated in step 6.1.
    static func isWhiteSpace(_ v: UInt32) -> Bool {
        switch v {
        case 0x09...0x0D, 0x20, 0x85, 0xA0, 0x1680, 0x2000...0x200A,
             0x2028, 0x2029, 0x202F, 0x205F, 0x3000:
            return true
        default:
            return false
        }
    }

    /// Unicode 17 `Dash_Punctuation`, enumerated in step 7.1.
    static let dashPunctuation: Set<UInt32> = [
        0x002D, 0x058A, 0x05BE, 0x1400, 0x1806, 0x2010, 0x2011, 0x2012,
        0x2013, 0x2014, 0x2015, 0x2E17, 0x2E1A, 0x2E3A, 0x2E3B, 0x2E40,
        0x2E5D, 0x301C, 0x3030, 0x30A0, 0xFE31, 0xFE32, 0xFE58, 0xFE63,
        0xFF0D, 0x10D6E, 0x10EAD,
    ]

    /// The quote characters of step 7.6.
    static let quoteCharacters: Set<UInt32> = [
        0x0022, 0x2018, 0x2019, 0x201C, 0x201D, 0x00AB, 0x00BB, 0x2039,
        0x203A, 0x3008, 0x3009, 0x300A, 0x300B, 0x300C, 0x300D,
    ]

    /// The autocorrect table of step 7.7.
    static let autocorrect: [UInt32: [Unicode.Scalar]] = [
        0x1F60A: [":", "-", ")"],
        0x1F610: [":", "-", "|"],
        0x2639: [":", "-", "("],
        0x1F603: [":", "-", "D"],
        0x1F61D: [":", "-", "p"],
        0x1F632: [":", "-", "o"],
        0x1F609: [";", "-", ")"],
        0x2764: ["<", "3"],
        0x1F494: ["<", "/", "3"],
        0x00A9: ["(", "c", ")"],
        0x00AE: ["(", "R", ")"],
        0x2022: ["*"],
    ]

    /// The three emoticons whose second character is a letter carry a trailing
    /// guard: they convert only when what follows is not an ASCII letter,
    /// digit, "-" or "_". Without it the table rewrites URI schemes --
    /// "did:peer" became "did:-peer". Trailing only; a leading guard would also
    /// stop converting "lol:p", which people type.
    static func isGuardedEmoticonBlocked(_ text: [Unicode.Scalar], _ i: Int) -> Bool {
        let second = text[i + 1].value
        guard second == 0x44 || second == 0x70 || second == 0x6F else { return false }
        guard i + 2 < text.count else { return false }
        let v = text[i + 2].value
        return (v >= 0x41 && v <= 0x5A) || (v >= 0x61 && v <= 0x7A)
            || (v >= 0x30 && v <= 0x39) || v == 0x2D || v == 0x5F
    }

    /// The ASCII emoticons of step 7.8, keyed by their two scalars.
    static let emoticons: [UInt64: [Unicode.Scalar]] = [
        0x3A_00000029: [":", "-", ")"],
        0x3A_0000007C: [":", "-", "|"],
        0x3A_00000028: [":", "-", "("],
        0x3A_00000044: [":", "-", "D"],
        0x3A_00000070: [":", "-", "p"],
        0x3A_0000006F: [":", "-", "o"],
        0x3B_00000029: [";", "-", ")"],
    ]

    static func isOpenOrInitial(_ v: UInt32) -> Bool {
        rangesContain(openPunctuation, v) || rangesContain(initialPunctuation, v)
    }

    static func isCloseOrFinal(_ v: UInt32) -> Bool {
        rangesContain(closePunctuation, v) || rangesContain(finalPunctuation, v)
    }

    static func isTerminalPunctuation(_ v: UInt32) -> Bool {
        rangesContain(terminalPunctuation, v)
    }

    static func isLineBreakSA(_ v: UInt32) -> Bool {
        rangesContain(lineBreakSA, v)
    }

    /// Binary search of a sorted, non-overlapping range table.
    static func rangesContain(_ ranges: [ClosedRange<UInt32>], _ v: UInt32) -> Bool {
        var lo = 0
        var hi = ranges.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if v < ranges[mid].lowerBound {
                hi = mid - 1
            } else if v > ranges[mid].upperBound {
                lo = mid + 1
            } else {
                return true
            }
        }
        return false
    }

    /// Unicode 17 `Line_Break=SA`, the 757 scalars enumerated in step 5.2.
    static let lineBreakSA: [ClosedRange<UInt32>] = [
        0x0E01...0x0E3A, 0x0E40...0x0E4E, 0x0E81...0x0E82, 0x0E84...0x0E84,
        0x0E86...0x0E8A, 0x0E8C...0x0EA3, 0x0EA5...0x0EA5, 0x0EA7...0x0EBD,
        0x0EC0...0x0EC4, 0x0EC6...0x0EC6, 0x0EC8...0x0ECE, 0x0EDC...0x0EDF,
        0x1000...0x103F, 0x1050...0x108F, 0x109A...0x109F, 0x1780...0x17D3,
        0x17D7...0x17D7, 0x17DC...0x17DD, 0x1950...0x196D, 0x1970...0x1974,
        0x1980...0x19AB, 0x19B0...0x19C9, 0x19DE...0x19DF, 0x1A20...0x1A5E,
        0x1A60...0x1A7C, 0x1AA0...0x1AAD, 0xA9E0...0xA9EF, 0xA9FA...0xA9FE,
        0xAA60...0xAAC2, 0xAADB...0xAADF, 0x11700...0x1171A, 0x1171D...0x1172B,
        0x1173A...0x1173B, 0x1173F...0x11746,
    ]

    /// Unicode 17 `Terminal_Punctuation`, the 291 scalars enumerated in step 7.9.
    static let terminalPunctuation: [ClosedRange<UInt32>] = [
        0x0021...0x0021, 0x002C...0x002C, 0x002E...0x002E, 0x003A...0x003B,
        0x003F...0x003F, 0x037E...0x037E, 0x0387...0x0387, 0x0589...0x0589,
        0x05C3...0x05C3, 0x060C...0x060C, 0x061B...0x061B, 0x061D...0x061F,
        0x06D4...0x06D4, 0x0700...0x070A, 0x070C...0x070C, 0x07F8...0x07F9,
        0x0830...0x0835, 0x0837...0x083E, 0x085E...0x085E, 0x0964...0x0965,
        0x0E5A...0x0E5B, 0x0F08...0x0F08, 0x0F0D...0x0F12, 0x104A...0x104B,
        0x1361...0x1368, 0x166E...0x166E, 0x16EB...0x16ED, 0x1735...0x1736,
        0x17D4...0x17D6, 0x17DA...0x17DA, 0x1802...0x1805, 0x1808...0x1809,
        0x1944...0x1945, 0x1AA8...0x1AAB, 0x1B4E...0x1B4F, 0x1B5A...0x1B5B,
        0x1B5D...0x1B5F, 0x1B7D...0x1B7F, 0x1C3B...0x1C3F, 0x1C7E...0x1C7F,
        0x2024...0x2024, 0x203C...0x203D, 0x2047...0x2049, 0x2CF9...0x2CFB,
        0x2E2E...0x2E2E, 0x2E3C...0x2E3C, 0x2E41...0x2E41, 0x2E4C...0x2E4C,
        0x2E4E...0x2E4F, 0x2E53...0x2E54, 0x3001...0x3002, 0xA4FE...0xA4FF,
        0xA60D...0xA60F, 0xA6F3...0xA6F7, 0xA876...0xA877, 0xA8CE...0xA8CF,
        0xA92F...0xA92F, 0xA9C7...0xA9C9, 0xAA5D...0xAA5F, 0xAADF...0xAADF,
        0xAAF0...0xAAF1, 0xABEB...0xABEB, 0xFE12...0xFE12, 0xFE15...0xFE16,
        0xFE50...0xFE52, 0xFE54...0xFE57, 0xFF01...0xFF01, 0xFF0C...0xFF0C,
        0xFF0E...0xFF0E, 0xFF1A...0xFF1B, 0xFF1F...0xFF1F, 0xFF61...0xFF61,
        0xFF64...0xFF64, 0x1039F...0x1039F, 0x103D0...0x103D0, 0x10857...0x10857,
        0x1091F...0x1091F, 0x10A56...0x10A57, 0x10AF0...0x10AF5, 0x10B3A...0x10B3F,
        0x10B99...0x10B9C, 0x10F55...0x10F59, 0x10F86...0x10F89, 0x11047...0x1104D,
        0x110BE...0x110C1, 0x11141...0x11143, 0x111C5...0x111C6, 0x111CD...0x111CD,
        0x111DE...0x111DF, 0x11238...0x1123C, 0x112A9...0x112A9, 0x113D4...0x113D5,
        0x1144B...0x1144D, 0x1145A...0x1145B, 0x115C2...0x115C5, 0x115C9...0x115D7,
        0x11641...0x11642, 0x1173C...0x1173E, 0x11944...0x11944, 0x11946...0x11946,
        0x11A42...0x11A43, 0x11A9B...0x11A9C, 0x11AA1...0x11AA2, 0x11C41...0x11C43,
        0x11C71...0x11C71, 0x11EF7...0x11EF8, 0x11F43...0x11F44, 0x12470...0x12474,
        0x16A6E...0x16A6F, 0x16AF5...0x16AF5, 0x16B37...0x16B39, 0x16B44...0x16B44,
        0x16D6E...0x16D6F, 0x16E97...0x16E98, 0x1BC9F...0x1BC9F, 0x1DA87...0x1DA8A,
    ]

    // MARK: - Unicode 17 data tables
    //
    // Generated from the Unicode 17.0.0 character database. The test suite
    // re-derives every one of these from the runtime and from the vectors, so a
    // transcription error would not go unnoticed.

    /// Unicode 17 General_Category Ps (`Open_Punctuation`), 79 scalars.
    static let openPunctuation: [ClosedRange<UInt32>] = [
        0x28...0x28, 0x5B...0x5B, 0x7B...0x7B, 0xF3A...0xF3A, 0xF3C...0xF3C,
        0x169B...0x169B, 0x201A...0x201A, 0x201E...0x201E, 0x2045...0x2045, 0x207D...0x207D,
        0x208D...0x208D, 0x2308...0x2308, 0x230A...0x230A, 0x2329...0x2329, 0x2768...0x2768,
        0x276A...0x276A, 0x276C...0x276C, 0x276E...0x276E, 0x2770...0x2770, 0x2772...0x2772,
        0x2774...0x2774, 0x27C5...0x27C5, 0x27E6...0x27E6, 0x27E8...0x27E8, 0x27EA...0x27EA,
        0x27EC...0x27EC, 0x27EE...0x27EE, 0x2983...0x2983, 0x2985...0x2985, 0x2987...0x2987,
        0x2989...0x2989, 0x298B...0x298B, 0x298D...0x298D, 0x298F...0x298F, 0x2991...0x2991,
        0x2993...0x2993, 0x2995...0x2995, 0x2997...0x2997, 0x29D8...0x29D8, 0x29DA...0x29DA,
        0x29FC...0x29FC, 0x2E22...0x2E22, 0x2E24...0x2E24, 0x2E26...0x2E26, 0x2E28...0x2E28,
        0x2E42...0x2E42, 0x2E55...0x2E55, 0x2E57...0x2E57, 0x2E59...0x2E59, 0x2E5B...0x2E5B,
        0x3008...0x3008, 0x300A...0x300A, 0x300C...0x300C, 0x300E...0x300E, 0x3010...0x3010,
        0x3014...0x3014, 0x3016...0x3016, 0x3018...0x3018, 0x301A...0x301A, 0x301D...0x301D,
        0xFD3F...0xFD3F, 0xFE17...0xFE17, 0xFE35...0xFE35, 0xFE37...0xFE37, 0xFE39...0xFE39,
        0xFE3B...0xFE3B, 0xFE3D...0xFE3D, 0xFE3F...0xFE3F, 0xFE41...0xFE41, 0xFE43...0xFE43,
        0xFE47...0xFE47, 0xFE59...0xFE59, 0xFE5B...0xFE5B, 0xFE5D...0xFE5D, 0xFF08...0xFF08,
        0xFF3B...0xFF3B, 0xFF5B...0xFF5B, 0xFF5F...0xFF5F, 0xFF62...0xFF62,
    ]

    /// Unicode 17 General_Category Pe (`Close_Punctuation`), 77 scalars.
    static let closePunctuation: [ClosedRange<UInt32>] = [
        0x29...0x29, 0x5D...0x5D, 0x7D...0x7D, 0xF3B...0xF3B, 0xF3D...0xF3D,
        0x169C...0x169C, 0x2046...0x2046, 0x207E...0x207E, 0x208E...0x208E, 0x2309...0x2309,
        0x230B...0x230B, 0x232A...0x232A, 0x2769...0x2769, 0x276B...0x276B, 0x276D...0x276D,
        0x276F...0x276F, 0x2771...0x2771, 0x2773...0x2773, 0x2775...0x2775, 0x27C6...0x27C6,
        0x27E7...0x27E7, 0x27E9...0x27E9, 0x27EB...0x27EB, 0x27ED...0x27ED, 0x27EF...0x27EF,
        0x2984...0x2984, 0x2986...0x2986, 0x2988...0x2988, 0x298A...0x298A, 0x298C...0x298C,
        0x298E...0x298E, 0x2990...0x2990, 0x2992...0x2992, 0x2994...0x2994, 0x2996...0x2996,
        0x2998...0x2998, 0x29D9...0x29D9, 0x29DB...0x29DB, 0x29FD...0x29FD, 0x2E23...0x2E23,
        0x2E25...0x2E25, 0x2E27...0x2E27, 0x2E29...0x2E29, 0x2E56...0x2E56, 0x2E58...0x2E58,
        0x2E5A...0x2E5A, 0x2E5C...0x2E5C, 0x3009...0x3009, 0x300B...0x300B, 0x300D...0x300D,
        0x300F...0x300F, 0x3011...0x3011, 0x3015...0x3015, 0x3017...0x3017, 0x3019...0x3019,
        0x301B...0x301B, 0x301E...0x301F, 0xFD3E...0xFD3E, 0xFE18...0xFE18, 0xFE36...0xFE36,
        0xFE38...0xFE38, 0xFE3A...0xFE3A, 0xFE3C...0xFE3C, 0xFE3E...0xFE3E, 0xFE40...0xFE40,
        0xFE42...0xFE42, 0xFE44...0xFE44, 0xFE48...0xFE48, 0xFE5A...0xFE5A, 0xFE5C...0xFE5C,
        0xFE5E...0xFE5E, 0xFF09...0xFF09, 0xFF3D...0xFF3D, 0xFF5D...0xFF5D, 0xFF60...0xFF60,
        0xFF63...0xFF63,
    ]

    /// Unicode 17 General_Category Pi (`Initial_Punctuation`), 12 scalars.
    static let initialPunctuation: [ClosedRange<UInt32>] = [
        0xAB...0xAB, 0x2018...0x2018, 0x201B...0x201C, 0x201F...0x201F, 0x2039...0x2039,
        0x2E02...0x2E02, 0x2E04...0x2E04, 0x2E09...0x2E09, 0x2E0C...0x2E0C, 0x2E1C...0x2E1C,
        0x2E20...0x2E20,
    ]

    /// Unicode 17 General_Category Pf (`Final_Punctuation`), 10 scalars.
    static let finalPunctuation: [ClosedRange<UInt32>] = [
        0xBB...0xBB, 0x2019...0x2019, 0x201D...0x201D, 0x203A...0x203A, 0x2E03...0x2E03,
        0x2E05...0x2E05, 0x2E0A...0x2E0A, 0x2E0D...0x2E0D, 0x2E1D...0x2E1D, 0x2E21...0x2E21,
    ]

    /// The 34 marks whose Canonical_Combining_Class a runtime is likely to be
    /// too old to know: the complete set of disagreements measured between
    /// `Unicode.Scalar.Properties.canonicalCombiningClass` on Swift 6.1.3 and
    /// Unicode 17.0.0. The values are the Unicode 17 ones, so this is a no-op
    /// on a runtime that already agrees.
    static let combiningClassPatches: [UInt32: UInt8] = {
        var out: [UInt32: UInt8] = [:]
        for scalar in UInt32(0x1ACF)...UInt32(0x1ADC) { out[scalar] = 230 }
        out[0x1ADD] = 220
        for scalar in UInt32(0x1AE0)...UInt32(0x1AE5) { out[scalar] = 230 }
        out[0x1AE6] = 220
        for scalar in UInt32(0x1AE7)...UInt32(0x1AEA) { out[scalar] = 230 }
        out[0x1AEB] = 234
        out[0x10EFA] = 220
        out[0x10EFB] = 220
        for scalar in [0x1E6E3, 0x1E6E6, 0x1E6EE, 0x1E6EF, 0x1E6F5] as [UInt32] {
            out[scalar] = 230
        }
        return out
    }()

    /// The compatibility mappings Unicode 16 and 17 added, which a Unicode 15
    /// runtime will not perform: the complete set of scalars whose Unicode 17
    /// NFKD differs from Foundation's. Each value is already fully decomposed,
    /// so applying it before NFKD is equivalent to NFKD knowing it, and
    /// applying it on a runtime that also knows it is a no-op.
    static let decompositionPatches: [UInt32: [Unicode.Scalar]] = {
        var out: [UInt32: [Unicode.Scalar]] = [:]
        for token in decompositionPatchTable.split(whereSeparator: { $0 == " " || $0 == "\n" }) {
            let halves = token.split(separator: ":")
            out[UInt32(halves[0], radix: 16)!] = halves[1].split(separator: ",").map {
                Unicode.Scalar(UInt32($0, radix: 16)!)!
            }
        }
        return out
    }()

    private static let decompositionPatchTable = """
        A7F1:53 105C9:105D2,307 105E4:105DA,307 11383:11382,113C9
        11385:11384,113BB 1138E:1138B,113C2 11391:11390,113C9 113C5:113C2,113C2
        113C7:113C2,113B8 113C8:113C2,113C9 16121:1611E,1611E 16122:1611E,16129
        16123:1611E,1611F 16124:16129,1611F 16125:1611E,16120 16126:1611E,1611E,1611F
        16127:1611E,16129,1611F 16128:1611E,1611E,16120 16D68:16D67,16D67
        16D69:16D63,16D67 16D6A:16D63,16D67,16D67 1CCD6:41 1CCD7:42 1CCD8:43
        1CCD9:44 1CCDA:45 1CCDB:46 1CCDC:47 1CCDD:48 1CCDE:49 1CCDF:4A 1CCE0:4B
        1CCE1:4C 1CCE2:4D 1CCE3:4E 1CCE4:4F 1CCE5:50 1CCE6:51 1CCE7:52 1CCE8:53
        1CCE9:54 1CCEA:55 1CCEB:56 1CCEC:57 1CCED:58 1CCEE:59 1CCEF:5A 1CCF0:30
        1CCF1:31 1CCF2:32 1CCF3:33 1CCF4:34 1CCF5:35 1CCF6:36 1CCF7:37 1CCF8:38
        1CCF9:39
        """

    /// Every Unicode 17 primary composite that is not Hangul: 961 triples of
    /// `first,second,composite` in hex. A canonical decomposition that is a
    /// composition exclusion is absent, which is what makes this a composition
    /// table rather than an inverted decomposition table.
    static let primaryComposites: [UInt64: UInt32] = {
        var out = [UInt64: UInt32](minimumCapacity: 2048)
        for token in primaryCompositeTable.split(whereSeparator: { $0 == " " || $0 == "\n" }) {
            let parts = token.split(separator: ",")
            let first = UInt64(parts[0], radix: 16)!
            let second = UInt64(parts[1], radix: 16)!
            out[first << 21 | second] = UInt32(parts[2], radix: 16)!
        }
        return out
    }()

    private static let primaryCompositeTable = """
        41,300,C0 41,301,C1 41,302,C2 41,303,C3 41,308,C4
        41,30A,C5 43,327,C7 45,300,C8 45,301,C9 45,302,CA
        45,308,CB 49,300,CC 49,301,CD 49,302,CE 49,308,CF
        4E,303,D1 4F,300,D2 4F,301,D3 4F,302,D4 4F,303,D5
        4F,308,D6 55,300,D9 55,301,DA 55,302,DB 55,308,DC
        59,301,DD 61,300,E0 61,301,E1 61,302,E2 61,303,E3
        61,308,E4 61,30A,E5 63,327,E7 65,300,E8 65,301,E9
        65,302,EA 65,308,EB 69,300,EC 69,301,ED 69,302,EE
        69,308,EF 6E,303,F1 6F,300,F2 6F,301,F3 6F,302,F4
        6F,303,F5 6F,308,F6 75,300,F9 75,301,FA 75,302,FB
        75,308,FC 79,301,FD 79,308,FF 41,304,100 61,304,101
        41,306,102 61,306,103 41,328,104 61,328,105 43,301,106
        63,301,107 43,302,108 63,302,109 43,307,10A 63,307,10B
        43,30C,10C 63,30C,10D 44,30C,10E 64,30C,10F 45,304,112
        65,304,113 45,306,114 65,306,115 45,307,116 65,307,117
        45,328,118 65,328,119 45,30C,11A 65,30C,11B 47,302,11C
        67,302,11D 47,306,11E 67,306,11F 47,307,120 67,307,121
        47,327,122 67,327,123 48,302,124 68,302,125 49,303,128
        69,303,129 49,304,12A 69,304,12B 49,306,12C 69,306,12D
        49,328,12E 69,328,12F 49,307,130 4A,302,134 6A,302,135
        4B,327,136 6B,327,137 4C,301,139 6C,301,13A 4C,327,13B
        6C,327,13C 4C,30C,13D 6C,30C,13E 4E,301,143 6E,301,144
        4E,327,145 6E,327,146 4E,30C,147 6E,30C,148 4F,304,14C
        6F,304,14D 4F,306,14E 6F,306,14F 4F,30B,150 6F,30B,151
        52,301,154 72,301,155 52,327,156 72,327,157 52,30C,158
        72,30C,159 53,301,15A 73,301,15B 53,302,15C 73,302,15D
        53,327,15E 73,327,15F 53,30C,160 73,30C,161 54,327,162
        74,327,163 54,30C,164 74,30C,165 55,303,168 75,303,169
        55,304,16A 75,304,16B 55,306,16C 75,306,16D 55,30A,16E
        75,30A,16F 55,30B,170 75,30B,171 55,328,172 75,328,173
        57,302,174 77,302,175 59,302,176 79,302,177 59,308,178
        5A,301,179 7A,301,17A 5A,307,17B 7A,307,17C 5A,30C,17D
        7A,30C,17E 4F,31B,1A0 6F,31B,1A1 55,31B,1AF 75,31B,1B0
        41,30C,1CD 61,30C,1CE 49,30C,1CF 69,30C,1D0 4F,30C,1D1
        6F,30C,1D2 55,30C,1D3 75,30C,1D4 DC,304,1D5 FC,304,1D6
        DC,301,1D7 FC,301,1D8 DC,30C,1D9 FC,30C,1DA DC,300,1DB
        FC,300,1DC C4,304,1DE E4,304,1DF 226,304,1E0 227,304,1E1
        C6,304,1E2 E6,304,1E3 47,30C,1E6 67,30C,1E7 4B,30C,1E8
        6B,30C,1E9 4F,328,1EA 6F,328,1EB 1EA,304,1EC 1EB,304,1ED
        1B7,30C,1EE 292,30C,1EF 6A,30C,1F0 47,301,1F4 67,301,1F5
        4E,300,1F8 6E,300,1F9 C5,301,1FA E5,301,1FB C6,301,1FC
        E6,301,1FD D8,301,1FE F8,301,1FF 41,30F,200 61,30F,201
        41,311,202 61,311,203 45,30F,204 65,30F,205 45,311,206
        65,311,207 49,30F,208 69,30F,209 49,311,20A 69,311,20B
        4F,30F,20C 6F,30F,20D 4F,311,20E 6F,311,20F 52,30F,210
        72,30F,211 52,311,212 72,311,213 55,30F,214 75,30F,215
        55,311,216 75,311,217 53,326,218 73,326,219 54,326,21A
        74,326,21B 48,30C,21E 68,30C,21F 41,307,226 61,307,227
        45,327,228 65,327,229 D6,304,22A F6,304,22B D5,304,22C
        F5,304,22D 4F,307,22E 6F,307,22F 22E,304,230 22F,304,231
        59,304,232 79,304,233 A8,301,385 391,301,386 395,301,388
        397,301,389 399,301,38A 39F,301,38C 3A5,301,38E 3A9,301,38F
        3CA,301,390 399,308,3AA 3A5,308,3AB 3B1,301,3AC 3B5,301,3AD
        3B7,301,3AE 3B9,301,3AF 3CB,301,3B0 3B9,308,3CA 3C5,308,3CB
        3BF,301,3CC 3C5,301,3CD 3C9,301,3CE 3D2,301,3D3 3D2,308,3D4
        415,300,400 415,308,401 413,301,403 406,308,407 41A,301,40C
        418,300,40D 423,306,40E 418,306,419 438,306,439 435,300,450
        435,308,451 433,301,453 456,308,457 43A,301,45C 438,300,45D
        443,306,45E 474,30F,476 475,30F,477 416,306,4C1 436,306,4C2
        410,306,4D0 430,306,4D1 410,308,4D2 430,308,4D3 415,306,4D6
        435,306,4D7 4D8,308,4DA 4D9,308,4DB 416,308,4DC 436,308,4DD
        417,308,4DE 437,308,4DF 418,304,4E2 438,304,4E3 418,308,4E4
        438,308,4E5 41E,308,4E6 43E,308,4E7 4E8,308,4EA 4E9,308,4EB
        42D,308,4EC 44D,308,4ED 423,304,4EE 443,304,4EF 423,308,4F0
        443,308,4F1 423,30B,4F2 443,30B,4F3 427,308,4F4 447,308,4F5
        42B,308,4F8 44B,308,4F9 627,653,622 627,654,623 648,654,624
        627,655,625 64A,654,626 6D5,654,6C0 6C1,654,6C2 6D2,654,6D3
        928,93C,929 930,93C,931 933,93C,934 9C7,9BE,9CB 9C7,9D7,9CC
        B47,B56,B48 B47,B3E,B4B B47,B57,B4C B92,BD7,B94 BC6,BBE,BCA
        BC7,BBE,BCB BC6,BD7,BCC C46,C56,C48 CBF,CD5,CC0 CC6,CD5,CC7
        CC6,CD6,CC8 CC6,CC2,CCA CCA,CD5,CCB D46,D3E,D4A D47,D3E,D4B
        D46,D57,D4C DD9,DCA,DDA DD9,DCF,DDC DDC,DCA,DDD DD9,DDF,DDE
        1025,102E,1026 1B05,1B35,1B06 1B07,1B35,1B08 1B09,1B35,1B0A 1B0B,1B35,1B0C
        1B0D,1B35,1B0E 1B11,1B35,1B12 1B3A,1B35,1B3B 1B3C,1B35,1B3D 1B3E,1B35,1B40
        1B3F,1B35,1B41 1B42,1B35,1B43 41,325,1E00 61,325,1E01 42,307,1E02
        62,307,1E03 42,323,1E04 62,323,1E05 42,331,1E06 62,331,1E07
        C7,301,1E08 E7,301,1E09 44,307,1E0A 64,307,1E0B 44,323,1E0C
        64,323,1E0D 44,331,1E0E 64,331,1E0F 44,327,1E10 64,327,1E11
        44,32D,1E12 64,32D,1E13 112,300,1E14 113,300,1E15 112,301,1E16
        113,301,1E17 45,32D,1E18 65,32D,1E19 45,330,1E1A 65,330,1E1B
        228,306,1E1C 229,306,1E1D 46,307,1E1E 66,307,1E1F 47,304,1E20
        67,304,1E21 48,307,1E22 68,307,1E23 48,323,1E24 68,323,1E25
        48,308,1E26 68,308,1E27 48,327,1E28 68,327,1E29 48,32E,1E2A
        68,32E,1E2B 49,330,1E2C 69,330,1E2D CF,301,1E2E EF,301,1E2F
        4B,301,1E30 6B,301,1E31 4B,323,1E32 6B,323,1E33 4B,331,1E34
        6B,331,1E35 4C,323,1E36 6C,323,1E37 1E36,304,1E38 1E37,304,1E39
        4C,331,1E3A 6C,331,1E3B 4C,32D,1E3C 6C,32D,1E3D 4D,301,1E3E
        6D,301,1E3F 4D,307,1E40 6D,307,1E41 4D,323,1E42 6D,323,1E43
        4E,307,1E44 6E,307,1E45 4E,323,1E46 6E,323,1E47 4E,331,1E48
        6E,331,1E49 4E,32D,1E4A 6E,32D,1E4B D5,301,1E4C F5,301,1E4D
        D5,308,1E4E F5,308,1E4F 14C,300,1E50 14D,300,1E51 14C,301,1E52
        14D,301,1E53 50,301,1E54 70,301,1E55 50,307,1E56 70,307,1E57
        52,307,1E58 72,307,1E59 52,323,1E5A 72,323,1E5B 1E5A,304,1E5C
        1E5B,304,1E5D 52,331,1E5E 72,331,1E5F 53,307,1E60 73,307,1E61
        53,323,1E62 73,323,1E63 15A,307,1E64 15B,307,1E65 160,307,1E66
        161,307,1E67 1E62,307,1E68 1E63,307,1E69 54,307,1E6A 74,307,1E6B
        54,323,1E6C 74,323,1E6D 54,331,1E6E 74,331,1E6F 54,32D,1E70
        74,32D,1E71 55,324,1E72 75,324,1E73 55,330,1E74 75,330,1E75
        55,32D,1E76 75,32D,1E77 168,301,1E78 169,301,1E79 16A,308,1E7A
        16B,308,1E7B 56,303,1E7C 76,303,1E7D 56,323,1E7E 76,323,1E7F
        57,300,1E80 77,300,1E81 57,301,1E82 77,301,1E83 57,308,1E84
        77,308,1E85 57,307,1E86 77,307,1E87 57,323,1E88 77,323,1E89
        58,307,1E8A 78,307,1E8B 58,308,1E8C 78,308,1E8D 59,307,1E8E
        79,307,1E8F 5A,302,1E90 7A,302,1E91 5A,323,1E92 7A,323,1E93
        5A,331,1E94 7A,331,1E95 68,331,1E96 74,308,1E97 77,30A,1E98
        79,30A,1E99 17F,307,1E9B 41,323,1EA0 61,323,1EA1 41,309,1EA2
        61,309,1EA3 C2,301,1EA4 E2,301,1EA5 C2,300,1EA6 E2,300,1EA7
        C2,309,1EA8 E2,309,1EA9 C2,303,1EAA E2,303,1EAB 1EA0,302,1EAC
        1EA1,302,1EAD 102,301,1EAE 103,301,1EAF 102,300,1EB0 103,300,1EB1
        102,309,1EB2 103,309,1EB3 102,303,1EB4 103,303,1EB5 1EA0,306,1EB6
        1EA1,306,1EB7 45,323,1EB8 65,323,1EB9 45,309,1EBA 65,309,1EBB
        45,303,1EBC 65,303,1EBD CA,301,1EBE EA,301,1EBF CA,300,1EC0
        EA,300,1EC1 CA,309,1EC2 EA,309,1EC3 CA,303,1EC4 EA,303,1EC5
        1EB8,302,1EC6 1EB9,302,1EC7 49,309,1EC8 69,309,1EC9 49,323,1ECA
        69,323,1ECB 4F,323,1ECC 6F,323,1ECD 4F,309,1ECE 6F,309,1ECF
        D4,301,1ED0 F4,301,1ED1 D4,300,1ED2 F4,300,1ED3 D4,309,1ED4
        F4,309,1ED5 D4,303,1ED6 F4,303,1ED7 1ECC,302,1ED8 1ECD,302,1ED9
        1A0,301,1EDA 1A1,301,1EDB 1A0,300,1EDC 1A1,300,1EDD 1A0,309,1EDE
        1A1,309,1EDF 1A0,303,1EE0 1A1,303,1EE1 1A0,323,1EE2 1A1,323,1EE3
        55,323,1EE4 75,323,1EE5 55,309,1EE6 75,309,1EE7 1AF,301,1EE8
        1B0,301,1EE9 1AF,300,1EEA 1B0,300,1EEB 1AF,309,1EEC 1B0,309,1EED
        1AF,303,1EEE 1B0,303,1EEF 1AF,323,1EF0 1B0,323,1EF1 59,300,1EF2
        79,300,1EF3 59,323,1EF4 79,323,1EF5 59,309,1EF6 79,309,1EF7
        59,303,1EF8 79,303,1EF9 3B1,313,1F00 3B1,314,1F01 1F00,300,1F02
        1F01,300,1F03 1F00,301,1F04 1F01,301,1F05 1F00,342,1F06 1F01,342,1F07
        391,313,1F08 391,314,1F09 1F08,300,1F0A 1F09,300,1F0B 1F08,301,1F0C
        1F09,301,1F0D 1F08,342,1F0E 1F09,342,1F0F 3B5,313,1F10 3B5,314,1F11
        1F10,300,1F12 1F11,300,1F13 1F10,301,1F14 1F11,301,1F15 395,313,1F18
        395,314,1F19 1F18,300,1F1A 1F19,300,1F1B 1F18,301,1F1C 1F19,301,1F1D
        3B7,313,1F20 3B7,314,1F21 1F20,300,1F22 1F21,300,1F23 1F20,301,1F24
        1F21,301,1F25 1F20,342,1F26 1F21,342,1F27 397,313,1F28 397,314,1F29
        1F28,300,1F2A 1F29,300,1F2B 1F28,301,1F2C 1F29,301,1F2D 1F28,342,1F2E
        1F29,342,1F2F 3B9,313,1F30 3B9,314,1F31 1F30,300,1F32 1F31,300,1F33
        1F30,301,1F34 1F31,301,1F35 1F30,342,1F36 1F31,342,1F37 399,313,1F38
        399,314,1F39 1F38,300,1F3A 1F39,300,1F3B 1F38,301,1F3C 1F39,301,1F3D
        1F38,342,1F3E 1F39,342,1F3F 3BF,313,1F40 3BF,314,1F41 1F40,300,1F42
        1F41,300,1F43 1F40,301,1F44 1F41,301,1F45 39F,313,1F48 39F,314,1F49
        1F48,300,1F4A 1F49,300,1F4B 1F48,301,1F4C 1F49,301,1F4D 3C5,313,1F50
        3C5,314,1F51 1F50,300,1F52 1F51,300,1F53 1F50,301,1F54 1F51,301,1F55
        1F50,342,1F56 1F51,342,1F57 3A5,314,1F59 1F59,300,1F5B 1F59,301,1F5D
        1F59,342,1F5F 3C9,313,1F60 3C9,314,1F61 1F60,300,1F62 1F61,300,1F63
        1F60,301,1F64 1F61,301,1F65 1F60,342,1F66 1F61,342,1F67 3A9,313,1F68
        3A9,314,1F69 1F68,300,1F6A 1F69,300,1F6B 1F68,301,1F6C 1F69,301,1F6D
        1F68,342,1F6E 1F69,342,1F6F 3B1,300,1F70 3B5,300,1F72 3B7,300,1F74
        3B9,300,1F76 3BF,300,1F78 3C5,300,1F7A 3C9,300,1F7C 1F00,345,1F80
        1F01,345,1F81 1F02,345,1F82 1F03,345,1F83 1F04,345,1F84 1F05,345,1F85
        1F06,345,1F86 1F07,345,1F87 1F08,345,1F88 1F09,345,1F89 1F0A,345,1F8A
        1F0B,345,1F8B 1F0C,345,1F8C 1F0D,345,1F8D 1F0E,345,1F8E 1F0F,345,1F8F
        1F20,345,1F90 1F21,345,1F91 1F22,345,1F92 1F23,345,1F93 1F24,345,1F94
        1F25,345,1F95 1F26,345,1F96 1F27,345,1F97 1F28,345,1F98 1F29,345,1F99
        1F2A,345,1F9A 1F2B,345,1F9B 1F2C,345,1F9C 1F2D,345,1F9D 1F2E,345,1F9E
        1F2F,345,1F9F 1F60,345,1FA0 1F61,345,1FA1 1F62,345,1FA2 1F63,345,1FA3
        1F64,345,1FA4 1F65,345,1FA5 1F66,345,1FA6 1F67,345,1FA7 1F68,345,1FA8
        1F69,345,1FA9 1F6A,345,1FAA 1F6B,345,1FAB 1F6C,345,1FAC 1F6D,345,1FAD
        1F6E,345,1FAE 1F6F,345,1FAF 3B1,306,1FB0 3B1,304,1FB1 1F70,345,1FB2
        3B1,345,1FB3 3AC,345,1FB4 3B1,342,1FB6 1FB6,345,1FB7 391,306,1FB8
        391,304,1FB9 391,300,1FBA 391,345,1FBC A8,342,1FC1 1F74,345,1FC2
        3B7,345,1FC3 3AE,345,1FC4 3B7,342,1FC6 1FC6,345,1FC7 395,300,1FC8
        397,300,1FCA 397,345,1FCC 1FBF,300,1FCD 1FBF,301,1FCE 1FBF,342,1FCF
        3B9,306,1FD0 3B9,304,1FD1 3CA,300,1FD2 3B9,342,1FD6 3CA,342,1FD7
        399,306,1FD8 399,304,1FD9 399,300,1FDA 1FFE,300,1FDD 1FFE,301,1FDE
        1FFE,342,1FDF 3C5,306,1FE0 3C5,304,1FE1 3CB,300,1FE2 3C1,313,1FE4
        3C1,314,1FE5 3C5,342,1FE6 3CB,342,1FE7 3A5,306,1FE8 3A5,304,1FE9
        3A5,300,1FEA 3A1,314,1FEC A8,300,1FED 1F7C,345,1FF2 3C9,345,1FF3
        3CE,345,1FF4 3C9,342,1FF6 1FF6,345,1FF7 39F,300,1FF8 3A9,300,1FFA
        3A9,345,1FFC 2190,338,219A 2192,338,219B 2194,338,21AE 21D0,338,21CD
        21D4,338,21CE 21D2,338,21CF 2203,338,2204 2208,338,2209 220B,338,220C
        2223,338,2224 2225,338,2226 223C,338,2241 2243,338,2244 2245,338,2247
        2248,338,2249 3D,338,2260 2261,338,2262 224D,338,226D 3C,338,226E
        3E,338,226F 2264,338,2270 2265,338,2271 2272,338,2274 2273,338,2275
        2276,338,2278 2277,338,2279 227A,338,2280 227B,338,2281 2282,338,2284
        2283,338,2285 2286,338,2288 2287,338,2289 22A2,338,22AC 22A8,338,22AD
        22A9,338,22AE 22AB,338,22AF 227C,338,22E0 227D,338,22E1 2291,338,22E2
        2292,338,22E3 22B2,338,22EA 22B3,338,22EB 22B4,338,22EC 22B5,338,22ED
        304B,3099,304C 304D,3099,304E 304F,3099,3050 3051,3099,3052 3053,3099,3054
        3055,3099,3056 3057,3099,3058 3059,3099,305A 305B,3099,305C 305D,3099,305E
        305F,3099,3060 3061,3099,3062 3064,3099,3065 3066,3099,3067 3068,3099,3069
        306F,3099,3070 306F,309A,3071 3072,3099,3073 3072,309A,3074 3075,3099,3076
        3075,309A,3077 3078,3099,3079 3078,309A,307A 307B,3099,307C 307B,309A,307D
        3046,3099,3094 309D,3099,309E 30AB,3099,30AC 30AD,3099,30AE 30AF,3099,30B0
        30B1,3099,30B2 30B3,3099,30B4 30B5,3099,30B6 30B7,3099,30B8 30B9,3099,30BA
        30BB,3099,30BC 30BD,3099,30BE 30BF,3099,30C0 30C1,3099,30C2 30C4,3099,30C5
        30C6,3099,30C7 30C8,3099,30C9 30CF,3099,30D0 30CF,309A,30D1 30D2,3099,30D3
        30D2,309A,30D4 30D5,3099,30D6 30D5,309A,30D7 30D8,3099,30D9 30D8,309A,30DA
        30DB,3099,30DC 30DB,309A,30DD 30A6,3099,30F4 30EF,3099,30F7 30F0,3099,30F8
        30F1,3099,30F9 30F2,3099,30FA 30FD,3099,30FE 105D2,307,105C9 105DA,307,105E4
        11099,110BA,1109A 1109B,110BA,1109C 110A5,110BA,110AB 11131,11127,1112E 11132,11127,1112F
        11347,1133E,1134B 11347,11357,1134C 11382,113C9,11383 11384,113BB,11385 1138B,113C2,1138E
        11390,113C9,11391 113C2,113C2,113C5 113C2,113B8,113C7 113C2,113C9,113C8 114B9,114BA,114BB
        114B9,114B0,114BC 114B9,114BD,114BE 115B8,115AF,115BA 115B9,115AF,115BB 11935,11930,11938
        1611E,1611E,16121 1611E,16129,16122 1611E,1611F,16123 16129,1611F,16124 1611E,16120,16125
        16121,1611F,16126 16122,1611F,16127 16121,16120,16128 16D67,16D67,16D68 16D63,16D67,16D69
        16D69,16D67,16D6A
        """
}
