# Fuzz gate

An Airlock submission arrives from a foreign chain. A Q-Oracle report arrives from off chain. Both cross a trust boundary the rest of the stack does not, so the parser that reads them first is held to two properties no ordinary test suite proves: it never panics on any input, and it rejects every artifact that is not a genuine Quantova artifact. This gate holds a parser to both, against random and mutated input rather than only the cases a test author thought to write.

## The two properties

The first is that the parser never panics. A truncated artifact, an oversized one, a length field that lies about what follows, or bytes that are not structured at all, every one of them is handled by a checked read and returns an error. A bare index or an unchecked slice range panics instead of returning one, and the fuzz target catches it the moment the fuzzer finds an input that reaches it.

The second is that a foreign artifact is always rejected. A foreign artifact is anything that does not open with the parser's own Quantova header. The fuzz target checks this with a plain byte comparison written directly in the target, independent of whatever gate the parser itself uses to decide, so a bug in the parser's own gate cannot hide from the fuzz target by agreeing with itself.

## The pattern a fuzz target follows

`fixtures/fuzz/bridge-message-parsers` is the pattern in full. It is not the production Airlock or Q-Oracle message format, those live in the repository that implements the bridge and the repository that implements Q-Oracle. It is a small parser for each, correct against both properties, with a fuzz target for each under `fuzz/fuzz_targets`.

```
fuzz_target!(|data: &[u8]| {
    let result = parse_airlock_message(data);
    let is_native = data.get(..AIRLOCK_MAGIC.len()) == Some(&AIRLOCK_MAGIC[..]);
    if !is_native {
        assert!(result.is_err(), "foreign artifact was accepted: {data:?}");
    }
});
```

The assertion is the second property, checked on every execution. The first property needs no assertion of its own, a panic anywhere in the call is itself the failure libFuzzer reports.

A fuzz target commits a small seed corpus under `fuzz/corpus/<target>` (one or two well formed artifacts and a couple of foreign ones), so the mutator starts from something structurally close to the real format rather than searching for the four byte header from nothing.

## How a repository adopts it

A repository that owns the Airlock parser or the Q-Oracle message parser writes a fuzz target for it at `fuzz/fuzz_targets/<name>.rs` under a `cargo fuzz` project, following the pattern above, and imports the reusable workflow.

```yaml
jobs:
  fuzz:
    uses: Quantova/Quantova-Ci/.github/workflows/fuzz.yml@main
```

The workflow finds every file under `fuzz/fuzz_targets`, builds it on a nightly toolchain, and runs it for a bounded time. A repository with no fuzz targets passes untouched. No repo merges a change to either parser while this is red.

## The proof

Two more fixtures under `fixtures/fuzz` prove the gate fires and not only passes. `dirty-accepts-foreign` is the Airlock parser with its magic check weakened to a single byte, so it wrongly accepts some foreign artifacts, alongside one committed regression input crafted to reach the bug on its first execution. `dirty-panics` is the Q-Oracle parser with its payload read through a bare slice range instead of a checked one, alongside a regression input whose declared length claims more bytes than are present. Each dirty fixture's fuzz run against its regression input exits nonzero, one on the assertion, one on an out of bounds panic. `scripts/fuzz-selftest.sh` runs all three fixtures, the clean one and both dirty ones, and is itself wired into the shared pipeline as the `fuzz-selftest` job, guarded on the fixtures being present.

```
scripts/fuzz-selftest.sh
```

Requires a nightly toolchain named `nightly` and `cargo-fuzz` on `PATH`.
