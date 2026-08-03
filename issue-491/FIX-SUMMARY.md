# Issue #491 — "empty waveform" crash in OmnibusSigProc

Branch: **`fix/issue-491-decon2d-oob-master`** (based on `master`, commit `501c5fe6`)
in `/exp/icarus/app/users/yuhw/wire-cell-toolkit`.
File changed: `sigproc/src/OmnibusSigProc.cxx` (+87 / −21).

## Root cause (confirmed)

`icaruscode v10_20_09p01` uses `wirecell v0_36_1`, whose production libraries are
built with `-DNDEBUG` (verified: cvmfs `libWireCellSigProc.so` has no
`__assert_fail` and no Eigen assert strings). With assertions off, an
**out-of-bounds Eigen `.block()`** in the 2D signal processing executes
silently.

In `OmnibusSigProc`, every 2D-decon helper extracts the physical wires with

```cpp
m_r_data[plane] = tm_r_data.block(m_pad_nwires[plane], 0, m_nwires[plane], m_nticks);
```

This assumes `tm_r_data` still carries the FFT wire-padding, i.e. has
`m_fft_nwires` rows. But for the ICARUS "twofaced" layout the induction planes
are split into ≥2 sub-planes, so `decon_2D_init()` calls `unpad_data()`, which
**shrinks the array to `m_nwires` rows** before the final
`m_c_data = fwd_r2c(m_r_data)`. The extraction then starts at row
`m_pad_nwires` and asks for `m_nwires` rows from an array that only has
`m_nwires` rows.

Observed at runtime (plane 0, TPC WW):

```
tm_r_data = (2112, 4296)   block(start_row=10, nwires=2112, nticks=4096)   fft_nwires=2132
```

→ rows [10, 2122) read from a 2112-row array → **10 rows out of bounds**.

In production (`-DNDEBUG`) this reads adjacent heap memory, which is
*occasionally* NaN/Inf (depends on allocator/run/data — hence "fails on event 2
in CI, not seen in production"). The NaN then reaches `restore_baseline()`:

```
baseline = median(signal)                 // -> NaN
keep samples with |x - baseline| < 500    // NaN comparison is false for ALL samples
baseline = median(temp_signal)            // temp_signal empty -> Waveform::percentile throws "empty waveform"
```

which is exactly the reported stack.

## Fix

### 1. Root cause — derive the padding offset from the actual row count (8 sites)

```cpp
// was: tm_r_data.block(m_pad_nwires[plane], 0, m_nwires[plane], m_nticks)
const int roi_row_pad = (tm_r_data.rows() - m_nwires[plane]) / 2;
m_r_data[plane] = tm_r_data.block(roi_row_pad, 0, m_nwires[plane], m_nticks);
```

Applied to all 7 `decon_2D_*` ROI/hits/charge extractions plus the `rawdecon`
finalization block that master added (`m_rawdecon_r_data`, gated by
`m_rawdecon_tag`).

- When `tm_r_data` has `m_fft_nwires` rows (collection plane / non-split
  configs), `roi_row_pad == m_pad_nwires` → **identical to the old behavior**.
- When `unpad_data()` already removed the padding (`m_nwires` rows),
  `roi_row_pad == 0` → in-bounds, correct wires.

So it is a no-op everywhere the code was already correct and only repairs the
overrun.

### 2. Defense-in-depth — make `restore_baseline()` NaN/Inf-safe

Skip non-finite samples when estimating the baseline (zeroing them in place),
and guard the second `median()` against an empty selection. No behavior change
for finite data; prevents any future non-finite source from re-triggering the
crash. Emits a `log->warn` when non-finite samples are seen.

## Validation

The fix was validated **end-to-end on `wirecell v0_36_1`** (the version in the
issue), because that is the version the ICARUS runtime
(`icaruscode v10_20_09p01`) actually loads:

- Rebuilt `libWireCellSigProc.so` from the v0.36.1 source with Eigen assertions
  ON. The **unpatched** build aborts at the out-of-bounds `.block()` in
  `decon_2D_tighterROI` during the WW-TPC deconvolution on the CI input file
  (`.../ci_14907/.../single_detsim_test_icaruscode_Current.root`) — captured via
  a custom `eigen_assert` backtrace, with the runtime dims shown above.
- With the fix applied and assertions still ON, the same job runs **both events**
  through the 2D signal processing with **no assertion, no "empty waveform",
  exit status 0**, and the `restore_baseline` non-finite guard never fires (i.e.
  removing the overrun removed the NaN at its source).

The `master` fix is the **same code**: `restore_baseline` and
`decon_2D_tighterROI` are byte-identical between the `master` fix branch and the
validated v0.36.1 fix branch (verified with `diff`), and master's
`decon_2D_init` still ends with `unpad_data()` → `fwd_r2c` producing `m_nwires`
rows, so the mechanism and the repair are identical.

### Note on testing `master` in-situ

A full `master` build/run could not be exercised in this ICARUS environment:
master's `WireCellUtil` now `#error`s unless SPDLOG is compiled against
**external fmtlib**, whereas `icaruscode v10_20_09p01` ships bundled-fmt
`spdlog v1_9_2`. master's libraries would therefore also be ABI-incompatible
with the v0.36.1 runtime, and there is no master-based `larwirecell`/`icaruscode`
to run. The byte-identical-code equivalence above is the applicable validation;
a native master run belongs in WCT's own CI once ICARUS moves to a master-era
toolchain.

## Artifacts in this directory

- `wct-src/`         — v0.36.1 source + instrumented build used for the in-situ
                       reproduction/validation (eigen_assert backtrace, dims log,
                       env-gated NaN-injection shim — all TEST-ONLY, not in the fix).
- `wct-master/`      — master (fix-branch) source; configures but cannot finish a
                       build here due to the spdlog/fmtlib requirement above.
- `fixlib/`          — patched `libWireCellSigProc.so` (v0.36.1) used for LD_PRELOAD tests.
- `repro2d*.fcl`, `in-sl7-clean.sh`, `*.log` — reproduction driver + run logs.
