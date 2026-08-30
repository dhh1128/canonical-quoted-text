package cqt

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"unicode"

	"golang.org/x/text/unicode/norm"
)

type manifest struct {
	Algorithm      string `json:"algorithm"`
	UnicodeVersion string `json:"unicode_version"`
	Encoding       string `json:"encoding"`
	Cases          []struct {
		ID     string `json:"id"`
		Input  string `json:"input"`
		Output string `json:"output"`
	} `json:"cases"`
}

func loadGoldens(t *testing.T) manifest {
	t.Helper()
	path := filepath.Join("..", "..", "goldens", "cqt3.17.json")
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("reading %s: %v", path, err)
	}
	var m manifest
	if err := json.Unmarshal(raw, &m); err != nil {
		t.Fatalf("parsing %s: %v", path, err)
	}
	if len(m.Cases) == 0 {
		t.Fatalf("%s has no cases", path)
	}
	return m
}

// TestUnicodeTables states the dependency this port cannot work without. Go's
// Unicode data moves with the toolchain -- go1.26 and earlier see 15.0.0 -- and
// a build against the wrong edition produces plausible bytes that are not
// cqt3.17.
func TestUnicodeTables(t *testing.T) {
	if norm.Version != UnicodeVersion {
		t.Errorf("golang.org/x/text normalization tables are Unicode %s, want %s",
			norm.Version, UnicodeVersion)
	}
	if unicode.Version != UnicodeVersion {
		t.Errorf("standard library tables are Unicode %s, want %s",
			unicode.Version, UnicodeVersion)
	}
	// U+A7F1 MODIFIER LETTER CAPITAL S gained its compatibility mapping to "S"
	// in Unicode 17.0.0. It is the only NFKC result that changed between 16 and
	// 17, so it is the cheapest live proof that the tables are 17 rather than
	// something older that merely claims to be.
	if got := norm.NFKC.String("꟱"); got != "S" {
		t.Errorf("NFKC(U+A7F1) = %q, want %q", got, "S")
	}
}

func TestGoldenManifest(t *testing.T) {
	m := loadGoldens(t)
	if m.Algorithm != "cqt3.17" {
		t.Errorf("algorithm = %q, want %q", m.Algorithm, "cqt3.17")
	}
	if m.UnicodeVersion != UnicodeVersion {
		t.Errorf("unicode_version = %q, want %q", m.UnicodeVersion, UnicodeVersion)
	}
	if m.Encoding != "UTF-8" {
		t.Errorf("encoding = %q, want %q", m.Encoding, "UTF-8")
	}
	seen := make(map[string]bool, len(m.Cases))
	for _, c := range m.Cases {
		if seen[c.ID] {
			t.Errorf("duplicate vector id %q", c.ID)
		}
		seen[c.ID] = true
	}
}

func TestNormativeGoldens(t *testing.T) {
	m := loadGoldens(t)
	passed := 0
	for _, c := range m.Cases {
		if t.Run(c.ID, func(t *testing.T) {
			got := Algorithm317(c.Input)
			want := []byte(c.Output)
			if !bytes.Equal(got, want) {
				t.Errorf("input  %s\nwant   %s\n       %x\ngot    %s\n       %x",
					show(c.Input), show(string(want)), want, show(string(got)), got)
			}
		}) {
			passed++
		}
	}
	t.Logf("%d/%d vectors pass", passed, len(m.Cases))
	if passed != len(m.Cases) {
		t.Errorf("%d of %d vectors pass", passed, len(m.Cases))
	}
}

// show spells out every scalar that would be invisible or ambiguous in a diff,
// so a divergence in a control character or an invisible is legible.
func show(text string) string {
	var b strings.Builder
	for _, r := range text {
		switch {
		case r == '\n':
			b.WriteString("\\n")
		case r == '\r':
			b.WriteString("\\r")
		case r == '\t':
			b.WriteString("\\t")
		case r < 0x20 || r == 0x7f:
			fmt.Fprintf(&b, "<%04X>", r)
		case r > 0x7e && !unicode.IsOneOf(printable, r):
			fmt.Fprintf(&b, "<%04X>", r)
		default:
			b.WriteRune(r)
		}
	}
	return b.String()
}

var printable = []*unicode.RangeTable{unicode.L, unicode.N, unicode.P, unicode.S}
