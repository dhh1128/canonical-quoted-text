//! Runs the normative vectors in `../../goldens/cqt2.17.json` against this port.
//!
//! The vectors are the conformance definition: an implementation is conformant
//! exactly insofar as it produces, byte for byte, the output every vector
//! specifies. There are no error cases -- cqt2.17 is a total function.

use std::path::PathBuf;

use serde_json::Value;

fn goldens_path() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../goldens/cqt2.17.json")
}

fn load() -> Value {
    let path = goldens_path();
    let raw = std::fs::read_to_string(&path)
        .unwrap_or_else(|e| panic!("cannot read {}: {e}", path.display()));
    serde_json::from_str(&raw).expect("goldens are valid JSON")
}

/// Render a byte string so a failure report is readable whatever it contains.
fn show(bytes: &[u8]) -> String {
    let mut out = String::new();
    match std::str::from_utf8(bytes) {
        Ok(text) => {
            for c in text.chars() {
                if c.is_control() || ((c as u32) >= 0x2000 && !c.is_alphanumeric()) {
                    out.push_str(&format!("<{:04X}>", c as u32));
                } else {
                    out.push(c);
                }
            }
        }
        Err(_) => out.push_str(&format!("{bytes:02X?}")),
    }
    out
}

#[test]
fn goldens_declare_the_expected_algorithm_and_unicode_version() {
    let doc = load();
    assert_eq!(doc["algorithm"], "cqt2.17");
    assert_eq!(doc["unicode_version"], "17.0.0");
    assert_eq!(doc["encoding"], "UTF-8");
    cqt::assert_unicode_version();
}

#[test]
fn every_vector_matches_byte_for_byte() {
    let doc = load();
    let cases = doc["cases"].as_array().expect("cases is an array");
    assert!(!cases.is_empty(), "no vectors found");

    let mut failures: Vec<String> = Vec::new();
    for case in cases {
        let id = case["id"].as_str().expect("case has a string id");
        let input = case["input"].as_str().expect("case has a string input");
        let expected = case["output"].as_str().expect("case has a string output");

        let actual = cqt::algorithm_2_17(input);
        if actual != expected.as_bytes() {
            failures.push(format!(
                "{id}\n     input: {}\n  expected: {}\n    actual: {}",
                show(input.as_bytes()),
                show(expected.as_bytes()),
                show(&actual),
            ));
        }
    }

    assert!(
        failures.is_empty(),
        "{} of {} vectors failed:\n\n{}",
        failures.len(),
        cases.len(),
        failures.join("\n\n")
    );
    eprintln!("all {} vectors pass", cases.len());
}

/// Output is always well-formed UTF-8 with no byte order mark (step 9).
#[test]
fn output_is_utf8_without_a_bom() {
    let doc = load();
    for case in doc["cases"].as_array().unwrap() {
        let input = case["input"].as_str().unwrap();
        let actual = cqt::algorithm_2_17(input);
        assert!(
            std::str::from_utf8(&actual).is_ok(),
            "{} produced invalid UTF-8",
            case["id"]
        );
        assert!(
            !actual.starts_with(&[0xEF, 0xBB, 0xBF]),
            "{} produced a BOM",
            case["id"]
        );
    }
}
