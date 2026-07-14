# Lint proofs

This file records that both content lints fire on a violation and pass on a clean tree. A lint that has never failed is not yet a lint. Both scanners run over the tracked files of the repository and both are wired into the shared workflow as their own jobs.

## Emoji lint

The emoji scanner reports and exits nonzero when a tracked file holds a pictographic code point in the ranges U+1F300 to U+1FAFF, U+2600 to U+27BF, U+FE0F, U+2B00 to U+2BFF, or U+2300 to U+23FF. Box drawing in U+2500 to U+257F is permitted and is never reported.

To prove the scanner a scratch file was placed in the working tree and staged so that it counted as tracked. The scratch file carried one pictographic code point. The scanner ran and printed the offending path and code point and exited with status one. A second scratch file carrying only box drawing was staged and the scanner left it alone, which shows the permitted block passes. The scratch files were then removed from the tree. The scanner ran again over the clean tree and exited with status zero.

Any test fixture that ever becomes part of the tree writes the code point in the escaped textual form \u{1F680} rather than a live glyph, so the source stays plain and readable.

## Identifier format lint

The identifier format scanner reports and exits nonzero when a tracked file renders the two characters that open a hex literal and then six or more hexadecimal characters, which is the shape of an Ethereum hash or address. The pattern is permitted only as a bare Rust integer literal in a Rust source file for low level bit math. It is reported inside string and character literals, inside line comments, and in every file that is not Rust source.

To prove the scanner a scratch file that was not Rust source was placed in the tree and staged. It held one Ethereum style value. The scanner ran and printed the offending path and value and exited with status one. A Rust scratch file holding only bare bit math literals was then staged and the scanner left it alone, which shows the permitted case passes. A Rust scratch file holding the same value inside a string was staged and the scanner reported it, which shows the string case is still caught. The scratch files were then removed from the tree. The scanner ran again over the clean tree and exited with status zero.

## Result

Both lints are red on a violation and green on a clean tree. Rerun either proof at any time by staging a scratch file that carries the forbidden shape and running the matching scanner, then removing the scratch file and running the scanner again.
