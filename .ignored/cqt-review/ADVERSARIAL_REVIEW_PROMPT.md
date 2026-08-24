# Handoff prompt: adversarial review of CQT 2.17

You are orchestrating an adversarial, multi-model review of the Canonical Quoted Text 2.17 specification. Work read-only. Do not edit the repository or silently resolve disagreements. The goal is to find ambiguities, false equivalences, false distinctions, security hazards, and cross-runtime nondeterminism before release.

## Materials

Review these artifacts independently; none is presumed correct merely because it is called normative or a reference implementation:

- `README.md`: prose specification
- `goldens/cqt2.17.json`: normative conformance vectors
- `cqt.py`: Python reference implementation
- `test_cqt.py`: conformance harness and invariants
- `cqt1.14.md`, if present: legacy behavior and migration context
- `/home/daniel/code/bakobo/bemi/.ignored/cqt2-issues.md`, if accessible: originating consumer concerns

Run the test suite and construct additional inputs, but do not use the Python output as the expected answer without deriving the answer independently from the specification.

## Independent reviewers

Assign at least these roles to different models. Have each reviewer work independently before sharing conclusions:

1. **Specification lawyer:** Find undefined ordering, boundary behavior, contradictions, non-normative language, incomplete error behavior, and cases where finite goldens cannot resolve the prose.
2. **Unicode and internationalization specialist:** Audit Unicode 17 pinning, NFKC, whitespace and punctuation properties, join controls, format characters, variation selectors, scripts outside Latin, UTF-8 production, and version skew.
3. **Security reviewer:** Attack displayed-text versus signed-text correspondence using bidi controls, invisibles, confusables, malformed scalars, opaque spans, URL lookalikes, delimiter confusion, and resource-exhaustion inputs.
4. **Markdown and tokenization reviewer:** Attack fenced blocks, info strings, longer fences, inline backtick runs, unmatched delimiters, Markdown links, URL boundaries, balanced parentheses, punctuation adjacent to protected spans, and lost line structure.
5. **Protocol and cryptography integrator:** Check algorithm identification, domain separation requirements, error handling, downgrade risks, canonicalization idempotence, streaming assumptions, and what a signer/verifier must bind.
6. **Cross-language implementer:** Identify behavior likely to diverge in JavaScript, Java, Go, Rust, and Swift because of regex semantics, Unicode databases, indexing models, normalization libraries, or error APIs.

## Required attack method

For every suspected issue, provide:

- severity: release-blocking, high, medium, or low;
- the smallest concrete input, written both visibly and as Unicode code points or escaped scalars;
- the behavior required by a literal reading of the prose;
- the golden/Python behavior, if observable;
- why the difference matters for a signing or verification workflow;
- a precise proposed spec or vector change;
- whether the proposal intentionally changes canonical output.

Each reviewer must also attempt:

- equivalence attacks: semantically different inputs that canonicalize identically;
- stability attacks: plausibly equivalent editor transformations that fail to match;
- idempotence attacks: `CQT(CQT(x)) != CQT(x)`;
- boundary attacks between prose and protected fenced, inline-code, and HTTP(S) spans;
- very long and adversarial delimiter/URL inputs to expose pathological complexity;
- Unicode 17 cases absent from Unicode 14 and 16 runtimes.

## Reconciliation

After independent reviews, have the models challenge one another's findings. Deduplicate only genuinely identical issues. Preserve meaningful disagreement, especially over semantic equivalence and the acceptable balance between false positives and false negatives.

Produce a final report with:

1. a release-blocker summary;
2. a ranked issue table;
3. concrete missing golden vectors;
4. proposed exact wording changes;
5. cross-language implementation traps;
6. unresolved design disputes, including the strongest argument on each side;
7. a release recommendation: reject, revise and re-review, or ready for porting.

Do not approve the specification merely because all existing tests pass. The central question is whether independent implementations can produce identical bytes for every conforming input and whether those equivalences remain defensible when CQT is used as the integrity basis for signed human-readable messages.
