#!/usr/bin/env bash
#
# mayhem/build.sh — build melo's cargo-fuzz target as a sanitized libFuzzer binary
# AND the project's own test suite (normal flags), so mayhem/test.sh only RUNS it.
#
# Runs inside the commit image as `mayhem` in /mayhem. Air-gapped contract
# (SPEC §6.5): this first (online) build populates the cargo registry under
# $CARGO_HOME; the PATCH tier re-runs this script OFFLINE (CARGO_NET_OFFLINE=true)
# and resolves crates from that cache — do NOT hard-code `--offline` here.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${MAYHEM_JOBS:=$(nproc)}"
# cargo-fuzz has no --jobs flag; cargo reads parallelism from CARGO_BUILD_JOBS.
export CARGO_BUILD_JOBS="$MAYHEM_JOBS"

cd "$SRC"

# ── 1. Sanitized libFuzzer fuzz target(s) (OSS-Fuzz Rust path) ────────────────
# -Zdwarf-version=3 keeps DWARF < 4 (§6.2 item 10 — Mayhem triage can't read DWARF>=4).
# Rust: ASan is enabled via RUSTFLAGS below, NOT $SANITIZER_FLAGS/$CFLAGS — those are
# clang flags for C/C++ code (skill: port-rust). The only C++ compiled here is
# libfuzzer-sys's bundled libFuzzer runtime; give it DWARF-3 debug info too.
export CFLAGS="${CFLAGS:-} -gdwarf-3"
export CXXFLAGS="${CXXFLAGS:-} -gdwarf-3"
# Thread $RUST_DEBUG_FLAGS (DWARF < 4 contract, §6.2 item 10) through RUSTFLAGS.
# All PROJECT (Rust) CUs are DWARF-3 via -Zdwarf-version=3 (+ --build-std below for std's CUs).
# The only DWARF-5 CUs left are rustc's PREBUILT ASan runtime (compiler-rt, clang-built) which
# has no rebuild knob. Mayhem triage reads the first CU, so link a DWARF-3 anchor object first
# (same first-CU approach the demangle integration uses for Go's fixed-DWARF4 gc output).
DWARF3_SHIM="$(mktemp -d)/dwarf3-anchor"
printf 'int mayhem_dwarf3_anchor;\n' > "$DWARF3_SHIM.c"
cc -c -gdwarf-3 -o "$DWARF3_SHIM.o" "$DWARF3_SHIM.c"
export RUSTFLAGS="${RUSTFLAGS:-} --cfg fuzzing -Zsanitizer=address -Cdebuginfo=2 ${RUST_DEBUG_FLAGS:--Zdwarf-version=3} -Cforce-frame-pointers -Zpre-link-arg=$DWARF3_SHIM.o"

FUZZ_DIR="mayhem/fuzz"
TRIPLE="x86_64-unknown-linux-gnu"

FUZZ_TARGETS=()
for f in "$FUZZ_DIR"/fuzz_targets/*.rs; do
  FUZZ_TARGETS+=("$(basename "${f%.*}")")
done
[ "${#FUZZ_TARGETS[@]}" -gt 0 ] || { echo "ERROR: no fuzz targets under $FUZZ_DIR/fuzz_targets/" >&2; exit 1; }

echo "=== cargo fuzz build (image nightly, ASan via RUSTFLAGS) ==="
echo "RUSTFLAGS=$RUSTFLAGS"
echo "targets: ${FUZZ_TARGETS[*]}"

for t in "${FUZZ_TARGETS[@]}"; do
  echo "--- building fuzz target: $t ---"
  # --build-std: recompile core/std with our RUSTFLAGS so the whole binary (incl.
  # std CUs) carries DWARF-3 debug info; the prebuilt std ships DWARF-5.
  cargo fuzz build --fuzz-dir "$FUZZ_DIR" --build-std -O --debug-assertions "$t"
  bin="$SRC/$FUZZ_DIR/target/$TRIPLE/release/$t"
  [ -x "$bin" ] || { echo "ERROR: expected fuzz binary not found at $bin" >&2; exit 1; }
  cp "$bin" "/mayhem/$t"
  echo "built /mayhem/$t"
done

# ── 2. The project's OWN test suite, with NORMAL flags (no sanitizers) ────────
# Upstream ships 82 #[test] unit tests across src/. Build (don't run) the libtest
# binary here; mayhem/test.sh executes it. Record the produced test executables
# in a manifest so test.sh never has to guess hashed filenames.
echo "=== cargo test --no-run (project's normal flags) ==="
# Upstream's Cargo.lock pins rustc-serialize 0.3.24, which no longer compiles on
# modern rustc; 0.3.25 (what the fuzz build resolves) does. Bump ONLY that pin,
# in the image's working tree, once (idempotent for the offline re-run).
if grep -A1 'name = "rustc-serialize"' Cargo.lock | grep -q '0\.3\.24'; then
  env -u RUSTFLAGS cargo update rustc-serialize@0.3.24 --precise 0.3.25
fi
env -u RUSTFLAGS cargo test --no-run --message-format=json \
  | python3 -c '
import json, sys
bins = []
for line in sys.stdin:
    try:
        m = json.loads(line)
    except ValueError:
        continue
    if m.get("reason") == "compiler-artifact" and m.get("profile", {}).get("test") and m.get("executable"):
        bins.append(m["executable"])
if not bins:
    sys.exit("ERROR: cargo test --no-run produced no test executables")
open("target/test-bins.txt", "w").write("\n".join(bins) + "\n")
print("test binaries:", *bins, sep="\n  ")
'

echo "build.sh complete"
