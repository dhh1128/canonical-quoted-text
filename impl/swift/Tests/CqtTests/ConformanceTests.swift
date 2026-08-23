import XCTest
import Foundation
@testable import Cqt

/// Runs the normative vectors in `goldens/cqt2.17.json`.
///
/// Comparisons are on UTF-8 bytes, never on `String`. Swift's `==` for `String`
/// compares under canonical equivalence, so `"\u{0340}" == "\u{0300}"` is true;
/// a test written that way would pass while the port emitted the wrong bytes.
final class ConformanceTests: XCTestCase {

    struct Manifest: Decodable {
        struct Case: Decodable {
            let id: String
            let input: String
            let output: String
        }
        let algorithm: String
        let unicodeVersion: String
        let encoding: String
        let cases: [Case]

        enum CodingKeys: String, CodingKey {
            case algorithm
            case unicodeVersion = "unicode_version"
            case encoding
            case cases
        }
    }

    static func goldensURL() -> URL {
        // Tests/CqtTests/ConformanceTests.swift -> impl/swift -> impl -> repo root
        let here = URL(fileURLWithPath: #filePath)
        let repoRoot = here
            .deletingLastPathComponent()   // CqtTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // swift
            .deletingLastPathComponent()   // impl
            .deletingLastPathComponent()   // repo root
        let candidate = repoRoot.appendingPathComponent("goldens/cqt2.17.json")
        if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("../../goldens/cqt2.17.json")
    }

    func loadManifest() throws -> Manifest {
        let data = try Data(contentsOf: Self.goldensURL())
        return try JSONDecoder().decode(Manifest.self, from: data)
    }

    func testManifestIsTheExpectedAlgorithm() throws {
        let m = try loadManifest()
        XCTAssertEqual(m.algorithm, "cqt2.17")
        XCTAssertEqual(m.unicodeVersion, "17.0.0")
        XCTAssertEqual(m.encoding, "UTF-8")
        XCTAssertFalse(m.cases.isEmpty)
    }

    func testEveryVector() throws {
        let m = try loadManifest()
        var failures: [String] = []
        for c in m.cases {
            let got = Cqt.algorithm217(c.input)          // [UInt8], UTF-8
            let want = Array(c.output.utf8)
            if got != want {
                failures.append("""
                \(c.id):
                    input:    \(Self.debugScalars(c.input))
                    expected: \(Self.debugBytes(want))
                    actual:   \(Self.debugBytes(got))
                """)
            }
        }
        XCTAssertTrue(
            failures.isEmpty,
            "\(failures.count) of \(m.cases.count) vectors failed:\n" + failures.joined(separator: "\n")
        )
    }

    /// The String-returning convenience must agree with the byte-returning one.
    func testStringAndByteAPIsAgree() throws {
        let m = try loadManifest()
        for c in m.cases {
            XCTAssertEqual(
                Array(Cqt.canonicalize(c.input).utf8),
                Cqt.algorithm217(c.input),
                "APIs disagree for \(c.id)"
            )
        }
    }

    /// The algorithm is defined on scalars; a caller may hand us grapheme
    /// clusters that Swift would merge if we iterated `Character`.
    func testOperatesOnScalarsNotGraphemes() {
        // "e" + combining acute is one Character but two scalars, and the
        // combining acute must be free to compose under NFKC.
        XCTAssertEqual(Cqt.algorithm217("e\u{0301}"), Array("\u{00E9}".utf8))
        // A variation selector belongs to the same grapheme as the character
        // before it, and step 7.7 must still see the base character.
        XCTAssertEqual(Cqt.algorithm217("\u{00A9}\u{FE0F}"), Array("(c)".utf8))
    }

    // MARK: - The worked examples in README.md

    func testWorkedExampleMixedScriptsAndTypography() {
        let input = "\u{201C}Le rapport \u{FB01}nal \u{2014} R&D, 1\u{2044}2 fait \u{2014} "
            + "co\u{FB}te 3--4 k\u{20AC}\u{00A0}; voir https://example.test/a--b?q=1&r=2 "
            + "\u{2026} et c\u{2019}est pr\u{EA}t\u{00A0}!\u{201D} \u{1F60A}  "
            + "\u{65E5}\u{672C}\u{8A9E}\u{3082}\u{FF1A}\u{300C}\u{30C6}\u{30B9}\u{30C8}\u{300D}\u{3002}  "
            + "\u{0930}\u{093E}\u{092E}\u{0964} \u{0936}\u{094D}\u{092F}\u{093E}\u{092E}"
        let expected = "'Le rapport final - R & D, 1/2 fait - co\u{FB}te 3-4 k\u{20AC}; "
            + "voir https://example.test/a--b?q=1&r=2... et c'est pr\u{EA}t!':-) "
            + "\u{65E5}\u{672C}\u{8A9E}\u{3082}:'\u{30C6}\u{30B9}\u{30C8}'. "
            + "\u{0930}\u{093E}\u{092E}\u{0964} \u{0936}\u{094D}\u{092F}\u{093E}\u{092E}"
        XCTAssertEqual(Self.debugBytes(Cqt.algorithm217(input)),
                       Self.debugBytes(Array(expected.utf8)))
    }

    func testWorkedExampleProseAroundMachineReadableSyntax() {
        let input = """
            Before  the  fence, `A  &  B--C` stays.
            ```python
            x = "A  &  B--C"   # two  spaces survive
            ```
            After, an unclosed ``` is only prose.
            """
        let expected = """
            Before the fence, `A  &  B--C` stays.
            ```python
            x = "A  &  B--C"   # two  spaces survive
            ```
            After, an unclosed ``` is only prose.
            """
        XCTAssertEqual(Self.debugBytes(Cqt.algorithm217(input)),
                       Self.debugBytes(Array(expected.utf8)))
    }

    func testWorkedExampleInvisibleCharacters() {
        // The unpaired surrogate of the README's example is left out: a Swift
        // String cannot hold one, so step 2.1 is unreachable from this API.
        let thai = "\u{0E1B}\u{0E32}\u{0E01}"
        let kaa = "\u{0E01}\u{0E32}"
        let conjunct = "\u{0915}\u{094D}\u{200D}\u{0937}"
        let input = thai + "\u{200B}" + kaa + " a\u{200B}b  soft\u{00AD}hyphen  "
            + "file\u{202E}gnp.exe  a\u{0000}b  " + conjunct
        let expected = thai + "\u{200B}" + kaa + " ab softhyphen filegnp.exe ab " + conjunct
        XCTAssertEqual(Self.debugBytes(Cqt.algorithm217(input)),
                       Self.debugBytes(Array(expected.utf8)))
    }

    // MARK: - NFKC

    /// Sequences that Foundation's own NFKC gets wrong on Swift 6.1.3 / Linux,
    /// kept here so a regression in `nfkc17` is loud. Expected values come from
    /// the reference implementation.
    func testNFKCHandlesWhatFoundationGetsWrong() {
        func nfkc(_ values: [UInt32]) -> [UInt32] {
            Cqt.nfkc17(values.map { Unicode.Scalar($0)! }).map { $0.value }
        }
        // Supplementary-plane starter truncated to its low 16 bits, so that
        // U+10041 + U+0301 wrongly composed to U+00C1.
        XCTAssertEqual(nfkc([0x61, 0x10041, 0x0301]), [0x61, 0x10041, 0x0301])
        // Composition across marks that came out of a decomposition.
        XCTAssertEqual(nfkc([0x61, 0x0F73, 0x0301]), [0x00E1, 0x0F71, 0x0F72])
        XCTAssertEqual(nfkc([0x61, 0xFF9E, 0x0301]), [0x00E1, 0x3099])
        // A composite that must itself compose again.
        XCTAssertEqual(nfkc([0x0CC6, 0x0CC2, 0x0CD5]), [0x0CCB])
        // Unicode 17 combining classes, and Unicode 16/17 mappings.
        XCTAssertEqual(nfkc([0x61, 0x1ADD, 0x0301]), [0x00E1, 0x1ADD])
        XCTAssertEqual(nfkc([0x61, 0x10EFA, 0x0301]), [0x00E1, 0x10EFA])
        XCTAssertEqual(nfkc([0xA7F1]), [0x53])
        XCTAssertEqual(nfkc([0x1CCD6]), [0x41])
        // Hangul, which is algorithmic rather than in the composite table.
        XCTAssertEqual(nfkc([0x1100, 0x1161, 0x11A8]), [0xAC01])
        XCTAssertEqual(nfkc([0xAC00, 0x11A8]), [0xAC01])
    }

    // MARK: - The generated Unicode 17 tables check themselves

    /// Every patched combining class must either be news to the runtime or
    /// agree with it. A disagreement means the patch table is wrong, or that
    /// the runtime has moved on in a way that needs looking at.
    func testCombiningClassPatchesAgreeWithTheRuntime() {
        XCTAssertEqual(Cqt.combiningClassPatches.count, 34)
        for (value, patched) in Cqt.combiningClassPatches {
            let runtime = Unicode.Scalar(value)!.properties.canonicalCombiningClass.rawValue
            XCTAssertTrue(
                runtime == 0 || runtime == patched,
                String(format: "U+%04X: runtime says %d, table says %d", value, runtime, patched)
            )
        }
    }

    /// Same contract for the compatibility mappings: the runtime either does
    /// not know the scalar, or decomposes it exactly as the patch says.
    func testDecompositionPatchesAgreeWithTheRuntime() {
        XCTAssertEqual(Cqt.decompositionPatches.count, 57)
        for (value, patched) in Cqt.decompositionPatches {
            var view = String.UnicodeScalarView()
            view.append(Unicode.Scalar(value)!)
            let runtime = Array(
                (String(view) as NSString).decomposedStringWithCompatibilityMapping.unicodeScalars
            )
            XCTAssertTrue(
                runtime.map { $0.value } == [value] || runtime == patched,
                String(format: "U+%04X: runtime decomposes to %@, table says %@", value,
                       runtime.map { String(format: "U+%04X", $0.value) }.joined(separator: " "),
                       patched.map { String(format: "U+%04X", $0.value) }.joined(separator: " "))
            )
        }
    }

    /// The composite table is an inverted canonical decomposition, so the
    /// runtime can check every entry it is new enough to know: NFD of the
    /// composite has to be NFD of the pair.
    func testPrimaryCompositeTableMatchesTheRuntimesDecompositions() {
        XCTAssertEqual(Cqt.primaryComposites.count, 961)
        func nfd(_ values: [UInt32]) -> [UInt32] {
            var view = String.UnicodeScalarView()
            for value in values { view.append(Unicode.Scalar(value)!) }
            return Array(
                (String(view) as NSString).decomposedStringWithCanonicalMapping.unicodeScalars
            ).map { $0.value }
        }
        var unknownToRuntime = 0
        for (key, composite) in Cqt.primaryComposites {
            let first = UInt32(key >> 21)
            let second = UInt32(key & 0x1F_FFFF)
            XCTAssertEqual(Cqt.combiningClass(Unicode.Scalar(first)!), 0,
                           String(format: "U+%04X is not a starter", first))
            let decomposed = nfd([composite])
            if decomposed == [composite] {
                unknownToRuntime += 1   // added after the runtime's Unicode version
                continue
            }
            XCTAssertEqual(decomposed, nfd([first]) + nfd([second]),
                           String(format: "U+%04X decomposes wrongly", composite))
        }
        // The 33 composites Unicode 16 and 17 added are the only ones a
        // Unicode 15 runtime may not know; a newer runtime knows them all.
        XCTAssertLessThanOrEqual(unknownToRuntime, 33)
    }

    /// The four punctuation categories are enumerated rather than looked up, so
    /// that the port does not inherit the runtime's Unicode version. Check them
    /// against the runtime over the whole scalar range anyway: no
    /// General_Category in these four classes changed between Unicode 15 and 17.
    func testPunctuationCategoriesMatchTheRuntime() {
        for value in UInt32(0)...0x10FFFF {
            if value >= 0xD800 && value <= 0xDFFF { continue }
            let scalar = Unicode.Scalar(value)!
            switch scalar.properties.generalCategory {
            case .openPunctuation:
                XCTAssertTrue(Cqt.rangesContain(Cqt.openPunctuation, value),
                              String(format: "U+%04X is Ps and missing", value))
            case .closePunctuation:
                XCTAssertTrue(Cqt.rangesContain(Cqt.closePunctuation, value),
                              String(format: "U+%04X is Pe and missing", value))
            case .initialPunctuation:
                XCTAssertTrue(Cqt.rangesContain(Cqt.initialPunctuation, value),
                              String(format: "U+%04X is Pi and missing", value))
            case .finalPunctuation:
                XCTAssertTrue(Cqt.rangesContain(Cqt.finalPunctuation, value),
                              String(format: "U+%04X is Pf and missing", value))
            default:
                XCTAssertFalse(Cqt.isOpenOrInitial(value) || Cqt.isCloseOrFinal(value),
                               String(format: "U+%04X is not punctuation but is listed", value))
            }
        }
    }

    /// The three sets the specification enumerates, checked for the sizes it
    /// states, so a transcription slip shows up as a count.
    func testEnumeratedSetsHaveTheSizesTheSpecificationStates() {
        func size(_ ranges: [ClosedRange<UInt32>]) -> Int {
            ranges.reduce(0) { $0 + Int($1.upperBound - $1.lowerBound) + 1 }
        }
        XCTAssertEqual(size(Cqt.lineBreakSA), 757)          // step 5.2
        XCTAssertEqual(size(Cqt.terminalPunctuation), 291)  // step 7.9
        XCTAssertEqual(Cqt.dashPunctuation.count, 27)       // step 7.1
        for ranges in [Cqt.lineBreakSA, Cqt.terminalPunctuation, Cqt.openPunctuation,
                       Cqt.closePunctuation, Cqt.initialPunctuation, Cqt.finalPunctuation] {
            for (a, b) in zip(ranges, ranges.dropFirst()) {
                XCTAssertLessThan(a.upperBound + 1, b.lowerBound, "ranges must be sorted and disjoint")
            }
        }
    }

    // MARK: - diagnostics

    static func debugScalars(_ s: String) -> String {
        s.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: " ")
    }

    static func debugBytes(_ b: [UInt8]) -> String {
        let text = String(decoding: b, as: UTF8.self)
        let hex = b.map { String(format: "%02X", $0) }.joined(separator: " ")
        return "\(text.debugDescription)  [\(hex)]"
    }
}
