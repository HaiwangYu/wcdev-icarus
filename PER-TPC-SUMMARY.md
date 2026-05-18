# Per-TPC ICARUS detsim — change summary and production notes

Splits the single `WireCellToolkit` art module that processes all four ICARUS
TPCs into **four art modules** (`daq0..daq3`), one per TPC.  Each module's
`WCLS_tool::process()` flushes its TPC's `RawDigit` and `SimChannel`
collections to the art Event at the end of its own `produce()`, so the float
`SimpleTrace` working set from one TPC is GC'd before the next module starts.

## Headline result

| metric                            | no-fix master | + all in-tree fixes (single module) | **+ per-TPC (4 modules)** |
|-----------------------------------|---------------|-------------------------------------|---------------------------|
| **VmHWM** (peak RSS, MemReport)   | 12 835 MB     | 9 001 MB                            | **6 418 MB**              |
| **VmPeak** (peak virtual)         | 17 946 MB     | 15 525 MB                           | 10 007 MB                 |
| Top-sampled RSS peak              | 11.93 GB      | 8.42 GB                             | **6.01 GB**               |
| Real time (one event)             | 34m14s        | 22m48s                              | 24m35s                    |
| CPU time                          | 851 s         | 986 s                               | 937 s                     |
| Event content                     | passes        | passes                              | passes                    |

Cumulative reduction from no-fix master: **−6.4 GB VmHWM (−50%)**, **−7.9 GB
VmPeak (−44%)**, **−9m39s** wall.

The remaining ~6 GB peak is dominated by ICARUS geometry + Geant4 inside
art (~2 GB), ROOT `TBranch` buffers (~0.5 GB), the in-flight TPC's float
`SimpleTrace`s (~0.85 GB Digitizer + 0.85 GB AddNoise), shared
PIRs/FieldResponses (~1.3 GB), and wcls input bookkeeping.

## Files changed

| layer            | file                                                                                      | change                                                                                                                                                                                                                                                                                                              |
|------------------|-------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **WCT C++**      | `gen/src/PlaneImpactResponse.cxx`                                                         | `build_responses()` now `m_ir.clear(); m_bywire.clear();` at top. Latent idempotency bug — required for any setup that calls `IConfigurable::configure()` more than once on a shared PIR (e.g. multiple `WireCellToolkit` art modules sharing PIRs via WCT's NamedFactory singleton).                                |
| **WCT C++**      | `gen/src/DepoSetFilterYZ.cxx`                                                             | Defensive `m_boxes.clear();` before the `face->sensitive()` push loop.                                                                                                                                                                                                                                              |
| **WCT C++**      | `gen/src/Scaler.cxx`                                                                      | Same defensive `m_boxes.clear();`.                                                                                                                                                                                                                                                                                  |
| **WCT jsonnet**  | `cfg/pgrapher/experiment/icarus/sim.jsonnet`                                              | Three `std.range(0, 359)` → `std.range(0, nanodes*45 - 1)` (in `transformsyz`, `reframersyz`, `analog_pipelinesyz`).  Backwards-compatible: with the full 8 anodes still evaluates to `(0, 359)`.  Also synced with the icaruscode-bundled copy that defines `drifter_data` / `overlay_drifter_data`. |
| **fcl**          | `wcdev-icarus/detsim-yz-per-tpc-v10_20_03.fcl`                                            | 4 `WireCellToolkit` modules `daq0..daq3` instead of 1.  Each `wcls_main` sets `configs: ["wcls-per-tpc-sim-drift-simchannel-yzsim.jsonnet"]`, `apps: ["Pgrapher:pgrapher<k>"]`, `params: { tpc_idx: "<k>" }`, and an `outputers:` list containing this TPC's 1 `wclsFrameSaver:simdigits<k>` + 90 `wclsDepoFluxWriter:postdrift<n>`.  `physics.simulate` lists `daq0, daq1, daq2, daq3` in order. |
| **jsonnet**      | `wcdev-icarus/wcls-per-tpc-sim-drift-simchannel-yzsim.jsonnet`                            | Reads `tpc_idx` extVar.  Narrows `tools.anodes` to that TPC's pair: `tools = tools_all { anodes: tools_all.anodes[apa_lo : apa_lo + 2] }`.  `sim_maker(params, tools)` then auto-scopes `analog_pipelinesyz` to 90 entries.  Per-TPC-named Pgrapher, fanout, summer, actpipe, MegaAnodePlane, FrameSaver.  Other component instance names (drifters, scalers, simchannel-sinks, filters) keep their global numbering so SimChannel and RawDigit product instance names match the reference single-module run. |
| **setup**        | `wcdev-icarus/setup.sh`                                                                   | Uncommented `path-prepend /exp/icarus/app/users/yuhw/wire-cell-toolkit/cfg WIRECELL_PATH`.  Without this, lar silently resolves `sim.jsonnet` / `funcs.jsonnet` from the (older) icaruscode-bundled cvmfs copy and any local edits to those files are ignored. |

## Why the WCT C++ patch matters

WCT's `NamedFactory` is process-wide.  Multiple `WireCellToolkit` art modules
in the same job share component instances by `(type, name)`.  Each module's
`Main::initialize()` calls `IConfigurable::configure()` on every component
its config references, so a shared component gets `configure()`'d once per
module.

`PlaneImpactResponse::build_responses()` was appending to `m_ir` and
`m_bywire` without clearing first.  After N reconfigures the per-wire
indexing tables drift out of sync with `m_half_extent`, and
`PIR::closest()` starts throwing for in-range pitches —
`ImpactTransform` then crashes downstream.

`DepoSetFilterYZ` and `Scaler` have the same `push_back`-without-`clear`
shape on `m_boxes`.  In our per-TPC config those instances are *not*
shared between modules (each module owns its own filters and scalers, named
uniquely by global index), so the bug doesn't fire there today — but the
fix is one line each and keeps the IConfigurable contract honest.

## Why the WCT jsonnet patch matters

`sim.jsonnet` had three loops hardcoded to `std.range(0, 359)` (= 8 anodes
× 45 entries).  These iterate over `tools.anodes[std.floor(n/45)]` so if
a caller narrows `tools.anodes` (e.g. the per-TPC jsonnet that does
`tools = tools_all { anodes: tools_all.anodes[apa_lo : apa_lo + 2] }`),
the loop tries to index past the end of the array and the jsonnet
evaluator throws.

Replacing 359 with `nanodes*45 - 1` lets the same `sim.jsonnet` serve both
the single-module (8 anodes → 360 entries) and the per-TPC (2 anodes → 90
entries) callers without behavior change for existing users.

## What to use for production

### 1. Push WCT C++ + jsonnet patches upstream

Suggested commit shape:

- **commit A**: PIR idempotency + audit fixes (3 files in `gen/src/`).
  Title: *"PIR: make configure() idempotent; defensive clears in DepoSetFilterYZ/Scaler"*.
- **commit B**: `sim.jsonnet` — derive YZ-transform count from `tools.anodes`.
  Title: *"icarus sim.jsonnet: derive YZ transform count from tools.anodes (so per-TPC callers can narrow anodes)"*.

### 2. Use the per-TPC fcl as the new ICARUS detsim baseline

[`wcdev-icarus/detsim-yz-per-tpc-v10_20_03.fcl`](detsim-yz-per-tpc-v10_20_03.fcl).
Downstream considerations:

- The art module label changes from `daq` to `daq0..daq3`.  Anything
  downstream that hardcodes `daq:` needs to be updated, or a tiny
  re-labeling producer can be added in art.
- The art `process_name` stays `DetSim` — the full product handle is
  e.g. `daq0:simdigits0::DetSim`.

If you want to keep the single-module fcl available for cases where
wall-clock matters more than memory, leave the original
`detsim-yz-v10_20_03.fcl` in place — the WCT patches are backwards
compatible.

### 3. Install the per-TPC jsonnet where production WIRECELL_PATH can find it

[`wcdev-icarus/wcls-per-tpc-sim-drift-simchannel-yzsim.jsonnet`](wcls-per-tpc-sim-drift-simchannel-yzsim.jsonnet).
Either:

- Commit it under `cfg/pgrapher/experiment/icarus/` in WCT (next to
  `wcls-multitpc-sim-drift-simchannel-yzsim-refactored.jsonnet`) so it
  ships with the toolkit, or
- Ship it via `icarus_data` / `icaruscode`'s `wire-cell-cfg` tree.

Either way, ensure `WIRECELL_PATH` at run time can resolve it.

### 4. WIRECELL_PATH for grid / batch

For interactive dev (this sandbox) the `path-prepend` line in
[`setup.sh`](setup.sh) puts the local WCT cfg ahead of cvmfs so subsequent
edits take effect immediately.  For grid jobs, set `WIRECELL_PATH` to
include whatever path ships the per-TPC jsonnet.

## Cost / benefit summary

| dimension              | cost                                                                                                                                       | benefit                                                                  |
|------------------------|--------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------|
| **Memory (VmHWM)**     | —                                                                                                                                          | **−2.6 GB** vs all-in-tree-fixes single module, **−6.4 GB** vs no-fix    |
| **Wall time**          | +1m47s vs single-module run (drift sim runs 4×, one per module — but the bulk of CPU is event-processing which is similar)                | —                                                                        |
| **Output**             | 4 RawDigit collections under module labels `daq0..daq3` instead of one `daq` label (instance names preserved: `simdigits0..3`, `simpleSC0..359`) | identical event content                                                  |
| **Code complexity**    | One additional fcl + one additional jsonnet to maintain                                                                                    | per-module flush behavior used cleanly; PIR/IConfigurable idempotency is now safe by design |

## Quick reproduce recipe

```bash
# build WCT with the C++ patches (idempotent reconfigure)
cd /exp/icarus/app/users/yuhw/wire-cell-toolkit
tools/in-sl7.sh ./wcb -p --notests build install

# run with the per-TPC fcl
tools/in-sl7.sh bash -c "
  cd /exp/icarus/app/users/yuhw/wcdev-icarus &&
  lar -n 1 \
      -c detsim-yz-per-tpc-v10_20_03.fcl \
      -s xroot://...input.root \
      -o detsim.root
"
```

The reference 1-event smoke test takes ~24 min wall, ends with
`TrigReport Events passed = 1`, peak RSS ~6.4 GB, and produces 4
`raw::RawDigits` collections + 360 `sim::SimChannel` collections in
`detsim.root`.

## See also

- [`PLAN-per-tpc-modules.md`](PLAN-per-tpc-modules.md) — the original
  design plan (pre-implementation analysis).
- The C++ idempotency fixes are also a general WCT bugfix and should be
  upstreamed regardless of whether the per-TPC fcl ships with production.
