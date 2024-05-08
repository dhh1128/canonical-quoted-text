// NOTE: THIS CODE WAS PORTED FROM THE PYTHON REFERENCE IMPLEMENTATION BY AN AI.
// DO NOT USE WITHOUT PROVING IT IS CORRECT. ONCE YOU'VE PROVED THAT, PLEASE SUBMIT
// A PR THAT REMOVES THIS WARNING FROM THE FILE.
package cqt

import (
	"fmt"
	"regexp"
	"strings"
	"unicode"
)

var AMPERS_PAT = regexp.MustCompile(`[&\uFE60\uFF06]`)
var SPECIALIZED_WHITESPACE_PAT = regexp.MustCompile(`[\u2028\u2029\u200B\uFEFF\u00A0\u3000\r\n\t]+`)
var MULTI_WHITESPACE_PAT = regexp.MustCompile(`\s{2,}`)
var DASHCHARS_PAT = regexp.MustCompile(`[\u058A\u05BE\u1400\u1806\u2010\u2011\u2012\u2013\u2014\u2015\u2e17\u2e1a\u2e3a\u2e3b\u2e40\u2e5d\u301c\u3030\u30a0\ufe31\ufe32\ufe58\ufe63\uff0d]+`)
var MULTI_HYPHENS_PAT = regexp.MustCompile(`-{2,}`)
var CJK_PUNCT_PAIRS = []struct {
	cjk   string
	ascii string
}{
	{"\u3001", ","},
	{"\u3002", "."},
}
var LONG_DOTS_PAT = regexp.MustCompile(`[.]{4,}`)
var QUOTERS_PAT = regexp.MustCompile(`["\u2018\u2019\u201C\u201D\u00AB\u00BB\u2039\u203A\u3008\u3009\u300A\u300B\u300C\u300D]`)
var ANY_WHITESPACE_PAT = regexp.MustCompile(`(\s+)`)
var AUTOCORRECT_PAIRS = []struct {
	autocorrect string
	ascii       string
}{
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
	{"\u2022", "*"},
}
var ASCII_EMOJI_PAIRS = []struct {
	noncanonical string
	canonical    string
}{
	{":)", ":-)"},
	{":|", ":-|"},
	{":(", ":-("},
	{":D", ":-D"},
	{":p", ":-p"},
	{":o", ":-o"},
	{";)", ";-)"},
}

func algorithm_1_14(plaintext string) []byte {
	// step 2
	x := []rune(plaintext)
	x = []rune(unicode.NFKC.String(string(x)))

	// step 3
	x = AMPERS_PAT.ReplaceAllString(string(x), " and ")

	// step 4
	x = SPECIALIZED_WHITESPACE_PAT.ReplaceAllString(string(x), " ")
	x = strings.TrimSpace(x)
	x = MULTI_WHITESPACE_PAT.ReplaceAllString(x, " ")

	// step 5
	x = DASHCHARS_PAT.ReplaceAllString(x, "-")
	x = MULTI_HYPHENS_PAT.ReplaceAllString(x, "-")
	for _, pair := range CJK_PUNCT_PAIRS {
		x = strings.ReplaceAll(x, pair.cjk, pair.ascii)
	}
	txt := ""
	for _, c := range x {
		n := int(c)
		if 0xFF01 <= n && n <= 0xFF5E {
			c = rune(n - 0xFEE0)
		}
		txt += string(c)
	}
	x = strings.ReplaceAll(txt, "\u2026", "...")
	x = LONG_DOTS_PAT.ReplaceAllString(x, "...")
	x = strings.ReplaceAll(x, "\u2044", "/")
	x = QUOTERS_PAT.ReplaceAllString(x, "'")
	txt = ""
	next := 0
	for _, match := range ANY_WHITESPACE_PAT.FindAllStringSubmatchIndex(x, -1) {
		keepSpace := true
		i := match[0]
		if i > 0 {
			txt += x[next:i]
			if unicode.IsPunct(rune(x[i-1])) {
				keepSpace = false
			}
		}
		next = match[1]
		if next < len(x) {
			if unicode.IsPunct(rune(x[next])) {
				keepSpace = false
			}
		}
		if keepSpace {
			txt += match[2]
		}
	}
	txt += x[next:]
	x = txt
	for _, pair := range AUTOCORRECT_PAIRS {
		x = strings.ReplaceAll(x, pair.autocorrect, pair.ascii)
	}
	for _, pair := range ASCII_EMOJI_PAIRS {
		x = strings.ReplaceAll(x, pair.noncanonical, pair.canonical)
	}

	// step 6
	return []byte(x)
}
