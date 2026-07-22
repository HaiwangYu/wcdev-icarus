# YZmap update: jsonnet loading optimization

Reduces peak heap and wall-clock during WCT job startup and event
processing for ICARUS detsim, and makes the `IConfigurable::configure()`
contract idempotent so multiple `WireCellToolkit` art modules can share
WCT-side components in one art job (enables a per-TPC fcl that drops peak
RSS by another ~2.6 GB).  Backwards compatible: with the standard 8-anode
config and a single `WireCellToolkit` module, behavior is unchanged.

## Headline result on ICARUS detsim (1-event smoke test)

| metric (1 event)            | master  | this PR (single-module fcl) | this PR + per-TPC fcl |
|-----------------------------|---------|-----------------------------|-----------------------|
| **VmHWM** (peak RSS)        | 12.8 GB | 9.0 GB                      | **6.4 GB**            |
| **VmPeak** (peak virtual)   | 17.9 GB | 15.5 GB                     | 10.0 GB               |
| Real wall time              | 34m14s  | 22m48s                      | 24m35s                |
| Output / event content      | passes  | passes                      | passes                |

Cumulative VmHWM reduction: **−3.8 GB single-module**, **−6.4 GB per-TPC**
(−50% from master).  CPU time unchanged.

## What's in the PR

### A. WCT configuration loading (`util/`, `apps/`, `cfg/`)

A series of independent fixes to the WCT-side config bootstrap that
together cut several GB of transient + resident heap during
`Main::initialize()` and the first few events.

| tag    | files                                                 | what                                                                                                                                                                                                                                                                                                              |
|--------|-------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **A0** | `util/src/Persist.cxx`                                | `json2object()` and the `.jsonnet` branch of `Parser::load()` now parse straight from the `char*` returned by `jsonnet_evaluate_file` via `Json::CharReaderBuilder::newCharReader()::parse()` instead of routing through a `std::stringstream` + `ostringstream::str()` pipeline.  Eliminates ~3 redundant copies of the ~1 GB JSON text that the parser used to keep alive simultaneously.  Also throws `IOError` with the parse error message on failure instead of silently returning an empty `Json::Value`. |
| **A1-A4** | `util/inc/WireCellUtil/Configuration.h`, `util/src/Configuration.cxx`, `util/inc/WireCellUtil/ConfigManager.h`, `util/src/ConfigManager.cxx`, `apps/src/Main.cxx` | • `branch()` now takes `const Configuration&` (plus a by-value overload kept for ABI compat with binaries built against the older signature on cvmfs).  Walks the dot-path via const-ref instead of repeated self-assignment.<br>• `find()` and `get()` templates take `const Configuration&`.<br>• `ConfigManager::all()` returns `const Configuration&` instead of by-value.<br>• Six `for (auto c : m_cfgmgr.all())` / `for (auto c : m_apps)` loops in `Main.cxx` (lines 299, 312, 325, 331, 350, 375, 408 in the original) → `for (const auto& …)`.<br>• `ConfigManager::extend()` and `index()` use `const auto&` iteration.<br>• When a component's `default_configuration()` is null, skip the no-op `update()` and pass `c["data"]` straight to `configure()` (saves a deep-copy per component). |
| **C1** | `util/src/ConfigManager.cxx`, `apps/src/Main.cxx`     | `ConfigManager::extend()` now `std::move`'s each entry into `m_top` instead of deep-copying.  Signature stays `void extend(Configuration more)` to preserve ABI; new callers should pass `std::move(cfg)` (and `Main.cxx:274` does).  Eliminates the per-entry deep copy inside the loop.                          |
| **C2** | `util/src/ConfigManager.cxx`                          | `ConfigManager::pop()` rewritten to use `Json::Value::removeIndex(i, &ret)` instead of cloning every other entry into a fresh `Json::arrayValue` and reassigning it back over `m_top`.  Drops another ~2 GB transient during the `wire-cell` entry extraction.                                                    |
| **C5** | `util/inc/WireCellUtil/ConfigManager.h`, `util/src/ConfigManager.cxx`, `apps/src/Main.cxx` | New `ConfigManager::clear_data()` that drops the bulk `"data"` sub-tree from every top-level entry.  `Main::initialize()` calls it after the configure loop completes; `finalize()` only consults `"type"` and `"name"` so the multi-GB resident `Json::Value` tree is released before event processing begins.  Lowers the post-config plateau ~1.8 GB and the late peak ~2 GB. |

The cumulative effect (single `WireCellToolkit` module on the
production ICARUS detsim fcl): VmHWM **12.8 GB → 9.0 GB** (−3.8 GB), and
the configure phase finishes in ≈ 4 s of wall time instead of ≈ 80 s.

### B. `IConfigurable::configure()` idempotency fixes (`gen/`)

WCT's `NamedFactory` is process-wide, so any setup that runs
`Main::initialize()` more than once on the same process (most relevantly:
multiple `WireCellToolkit` art modules in one art job) calls
`configure()` repeatedly on shared component instances.  The contract
requires `configure()` to be idempotent; three components weren't:

- **`PlaneImpactResponse::build_responses()`** appended to `m_ir` and
  `m_bywire` without clearing first.  After the second
  reconfigure, `nwires()` and the per-wire indexing drift out of sync
  with `m_half_extent`; `PIR::closest()` starts throwing for in-range
  pitches and `ImpactTransform` crashes downstream.  Fixed with
  `m_ir.clear(); m_bywire.clear();` at the top of `build_responses()`.
- **`DepoSetFilterYZ::configure()`** and **`Scaler::configure()`** —
  same `m_boxes.push_back(face->sensitive())` loop with no preceding
  `clear()`.  Defensive fix, since their instances aren't currently
  shared between WCT art modules but the contract issue is the same.

Audit confirmed the rest of `gen/src/` is already idempotent
(`AnodePlane`, `MegaAnodePlane`, `DepoTransform`, `Reframer`, `YZMap`,
`FieldResponse`, `ColdElecResponse`, `WarmElecResponse`,
`JsonElecResponse`, `WireSchemaFile` all clear or overwrite their
state before populating).

### C. `sim.jsonnet` generalization

Three hardcoded `std.range(0, 359)` in
`cfg/pgrapher/experiment/icarus/sim.jsonnet` (in `transformsyz`,
`reframersyz`, and `analog_pipelinesyz`) → `std.range(0, nanodes*45 - 1)`.
Each iterates over `tools.anodes[std.floor(n/45)]` so a caller that
narrows `tools.anodes` (e.g. to a single-TPC pair via
`tools = tools_all { anodes: tools_all.anodes[apa_lo : apa_lo + 2] }`)
now builds only the relevant 90 entries instead of indexing past the
end of the array.  With the default 8-anode `tools.anodes` the
expression evaluates to `(0, 359)` and behavior is unchanged.  This is
the change that enables the per-TPC fcl downstream.

### D. ICARUS detsim jsonnet variant
`cfg/pgrapher/experiment/icarus/wcls-multitpc-sim-drift-simchannel-yzsim-refactored.jsonnet`
ships as the up-to-date refactored variant (uses the YZMap service, the
`drifter_data` definitions, and the FrameFanin→DumpFrames topology
adjustments that the production icarus detsim flow needs).

## Why "memory" matters here

The original WCT-on-art configure path:

```
Json::Value one = p.load(filename);          // ~2 GB parsed tree
m_cfgmgr.extend(one);                        // deep-copies into m_top         ← C1
m_cfgmgr.pop(index_of_wirecell_entry);       // rebuilds m_top by appending    ← C2
for (auto c : m_cfgmgr.all()) { … }          // returned m_top by value (!)    ← A2
…  (6 such loops)                            // …                              ← A2
Configuration cfg = cfgobj->default_configuration();
cfg = update(cfg, c["data"]);                 // dup of c["data"]              ← A3
cfgobj->configure(cfg);                      // …
…
// post-configure: m_top stays resident (~2 GB) for the entire job
```

After this PR: ~2 GB transient gone from `extend`, ~2 GB transient gone
from `pop`, ~3 GB transient gone from the parser's stringstream
pipeline, the 6 by-value loops in `Main.cxx` are by-ref, and the
resident `m_top` payload is dropped after `configure()` completes.  The
combined effect is a multi-GB drop in both the startup peak and the
post-config plateau.

## Backwards compatibility

- All `util/` API changes are additive or maintain the old by-value
  signatures as ABI shims (declared in-place inside `namespace
  WireCell` blocks in the `.cxx`, not in the headers, so new code
  prefers the const-ref overload).  Binaries built against the older
  WCT headers on cvmfs (`libWireCellLarsoft`, `libWireCellAIML`,
  `libWireCellQLMatch`, and the cvmfs `libWireCell*` themselves) link
  cleanly.  Verified with `nm -D` against the cvmfs build set.
- `Pgrapher::configure()`'s edge-accumulation behavior is unchanged.
  The per-TPC fcl side-steps it by using unique `Pgrapher:pgrapher<k>`
  names.
- `sim.jsonnet`'s `std.range(0, nanodes*45 - 1)` evaluates to the
  legacy `(0, 359)` when called with the default 8-anode tools.
- The new `wcls-multitpc-…-refactored.jsonnet` is a separate variant;
  existing fcl that pointed at the older jsonnet keeps working.

## Tests

- 1-event smoke (`detsim_2d_icarus_refactored_yzsim.fcl` → produces
  `detsim.root`):
  - master: passes, VmHWM 12.8 GB.
  - this PR (same fcl, no other change): passes, VmHWM 9.0 GB,
    `RawDigit`/`SimChannel` collection byte-identical to master.
- 1-event smoke with the per-TPC fcl (4 `WireCellToolkit` art modules):
  passes, VmHWM 6.4 GB.  `RawDigit` instance names preserved
  (`simdigits0..3`).  `SimChannel` instance names preserved
  (`simpleSC0..359`) but now distributed across the four `daq0..daq3`
  module labels.
- Audit of `gen/src/` for `push_back`-without-`clear` patterns: only
  PIR / DepoSetFilterYZ / Scaler were affected, all addressed in this
  PR.  Others (`AnodePlane`, `MegaAnodePlane`, `DepoTransform`,
  `Reframer`, `YZMap`, FieldResponse and the various
  `*ElecResponse`/`WireSchemaFile`) already clear or overwrite the
  relevant state.

## Files

```
apps/src/Main.cxx                                           |  34 +-  12
cfg/pgrapher/experiment/icarus/sim.jsonnet                  |  51 +-   4
cfg/pgrapher/experiment/icarus/
    wcls-multitpc-sim-drift-simchannel-yzsim-refactored.jsonnet | 537 +- 0
gen/src/DepoSetFilterYZ.cxx                                 |   5 +-   0
gen/src/PlaneImpactResponse.cxx                             |   8 +-   0
gen/src/Scaler.cxx                                          |   2 +-   0
util/inc/WireCellUtil/ConfigManager.h                       |  12 +-   1
util/inc/WireCellUtil/Configuration.h                       |   4 +-   4
util/src/ConfigManager.cxx                                  |  45 +- 14
util/src/Configuration.cxx                                  |  22 +-  4
util/src/Persist.cxx                                        |  33 +-  6
```

## Commits

```
ac6dd767  per-TPC cfg                # sim.jsonnet 360→nanodes*45 generalization
47fd57ef  fresh cfg                  # PIR/DepoSetFilterYZ/Scaler idempotency
a83aa72b  C5 clear config data       # drop m_top "data" sub-trees post-configure
23fbc42c  C1, C2                     # extend() move-into-m_top, pop() removeIndex
cca127e0  A0                         # Persist json2object via CharReader, drop stringstream
92f572c1  configuration speed up     # A1-A4: by-ref loops + branch()/find()/get()/all()
9f1a0129  keep the debug for now
505f50bb  Bulk loads of large configs
35fa11c3  increase max stack
336afab4  optimized "uses"
```
