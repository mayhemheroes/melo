#!/usr/bin/env bash
#
# mayhem/test.sh — RUN melo's own unit-test suite (already built by mayhem/build.sh
# via `cargo test --no-run`; the binaries are listed in target/test-bins.txt).
# The 82 upstream #[test] cases assert parser/lexer/sequencer/MIDI behavior
# (known-answer tests with assert_eq!), so this is a behavioral oracle.
# Do NOT compile here — if the manifest/binaries are missing, that's a build.sh bug.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

MANIFEST="$SRC/target/test-bins.txt"
[ -f "$MANIFEST" ] || { echo "ERROR: $MANIFEST missing — mayhem/build.sh did not build the test suite" >&2; emit_ctrf cargo-test 0 1; exit 1; }

total_passed=0; total_failed=0; total_skipped=0; bad=0
while IFS= read -r bin; do
  [ -n "$bin" ] || continue
  [ -x "$bin" ] || { echo "ERROR: test binary missing: $bin" >&2; bad=1; continue; }
  echo "=== running $bin ==="
  # parsing::tests::quick is broken ON PRISTINE UPSTREAM: it is a leftover WIP test
  # that ends in an unconditional panic!("... ITS ACTAULLY FINE", ...) (src/parsing.rs).
  # Skip exactly that one test; the other 81 upstream tests all run.
  out="$("$bin" --skip parsing::tests::quick 2>&1)"; rc=$?
  echo "$out"
  # libtest summary: "test result: ok. 82 passed; 0 failed; 0 ignored; ..."
  summary="$(printf '%s\n' "$out" | grep -E '^test result: ' | tail -1)"
  if [ -z "$summary" ]; then
    echo "ERROR: no libtest summary from $bin (rc=$rc) — treating as failure" >&2
    bad=1; continue
  fi
  p="$(printf '%s' "$summary" | sed -nE 's/.* ([0-9]+) passed.*/\1/p')"
  f="$(printf '%s' "$summary" | sed -nE 's/.* ([0-9]+) failed.*/\1/p')"
  s="$(printf '%s' "$summary" | sed -nE 's/.* ([0-9]+) ignored.*/\1/p')"
  filt="$(printf '%s' "$summary" | sed -nE 's/.* ([0-9]+) filtered out.*/\1/p')"
  total_passed=$(( total_passed + ${p:-0} ))
  total_failed=$(( total_failed + ${f:-0} ))
  total_skipped=$(( total_skipped + ${s:-0} + ${filt:-0} ))
  [ $rc -ne 0 ] && bad=1
done < "$MANIFEST"

# A run where no test executed (or a binary vanished/died without a summary) is a failure,
# not a pass — an exit(0)-neutered suite must FAIL here.
if [ "$bad" -ne 0 ] || [ "$total_passed" -eq 0 ]; then
  [ "$total_failed" -eq 0 ] && total_failed=1
fi

emit_ctrf cargo-test "$total_passed" "$total_failed" "$total_skipped"
