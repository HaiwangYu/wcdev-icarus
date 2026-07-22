# Plan: split the single `WireCellToolkit` module into 4 per-TPC modules

## Context

The current ICARUS detsim fcl has **one** `WireCellToolkit` art module (label `daq`).
Internally its WCT graph runs four parallel actpipes (one per TPC) and four
`wclsFrameSaver` outputers. The outputers don't call `event.put()` until the
**outputers phase at the end of `wcls::WCLS::process()`** — i.e. after the
whole pgraph (all four TPCs) has finished. That is why all four TPCs' float
`SimpleTrace` collections live simultaneously at the late memory peak:

```
WireCellToolkit_module::produce()           [art module entry]
  → WCLS_tool::process(event)
    → inputers' visit(event)               [pull SimEnergyDeposits → WCT]
    → m_wcmain()                           [runs full pgraph, ALL 4 TPCs]
    → outputers' visit(event)              [event.put() for RawDigit, SimChannel]
```

Splitting into **4 art modules**, one per TPC, gives us four independent
`process()` calls per event. Each module's graph holds only its TPC's float
traces; after `event.put()` returns, those traces are eligible for free
before the next module starts.

The flush-timing assumption is load-bearing:
[FrameSaver::visit()](/cvmfs/larsoft.opensciencegrid.org/products/larwirecell/v10_03_02/include/larwirecell/Components/FrameSaver.h)
is invoked from
[WCLS_tool.cc:220-222](/cvmfs/larsoft.opensciencegrid.org/products/larwirecell/v10_03_02/include/larwirecell/Components/WCLS_tool.cc#L220-L222)
*after* `m_wcmain()` at line 217 has returned — confirmed by Explore agent
inspection.

## Decisions (from clarification)

- **Output labels**: keep instance names (`simdigits0..3`, `simpleSC0..359`); change
  module labels to `daq0..3`. Downstream code that previously read `daq:simdigits0`
  needs to read `daq0:simdigits0` (or use a module wildcard).
- **SimChannel placement**: each per-TPC module produces only its TPC's 90
  `wclsDepoFluxWriter` outputs. Total still 360 SimChannels across the event,
  spread across `daq0..3`.
- **Wall-time trade**: accept ~2× wall (drift sim runs 4×, one per module) in
  exchange for ~3 GB lower peak RSS.

## Estimated impact (from massif analysis)

Current late-peak heap breakdown (post-C5 + the no-fanin change):

| live thing at peak | size |
|---|---|
| Digitizer float SimpleTraces (4 TPCs worth) | 3.42 GB |
| CoherentAddNoise float SimpleTraces (1 TPC in flight) | 0.87 GB |
| Other (ROOT TBuffer, accumulated RawDigit, art) | ~2.7 GB |
| **peak heap** | **~7.0 GB** (matches VmHWM ≈ 9.0 GB native) |

Per-TPC split should reduce Digitizer footprint from 3.42 GB → ~0.86 GB
(only one TPC's traces alive), saving ~2.5 GB at peak. AddNoise stays at
~0.87 GB. Estimated post-split peak: ~4.5 GB heap / ~6-7 GB VmHWM.

## File layout

All artefacts will live in `/exp/icarus/app/users/yuhw/wcdev-icarus/`:

- `wcls-per-tpc-sim-drift-simchannel-yzsim.jsonnet` — new parameterized
  jsonnet, takes `tpc_idx` (0..3) as an extVar, builds the graph for only
  that TPC.
- `detsim-yz-per-tpc-v10_20_03.fcl` — new fcl that has four `WireCellToolkit`
  art modules (`daq0..3`) instead of one.

The current `wcls-multitpc-sim-drift-simchannel-yzsim-refactored.jsonnet` (in WCT
`cfg/pgrapher/experiment/icarus/`) is left untouched so the old single-module
path keeps working.

## Per-TPC jsonnet structure

New extVar:

```jsonnet
local tpc_idx = std.parseInt(std.extVar('tpc_idx'));   // 0..3
local n_lo = tpc_idx * 90;
local n_hi = (tpc_idx + 1) * 90;
```

Then in every place the current jsonnet loops `for n in std.range(0, 359)`,
change to `for n in std.range(n_lo, n_hi - 1)`. Affected blocks (line numbers from
the current `wcls-multitpc-sim-drift-simchannel-yzsim-refactored.jsonnet`):

| block | current range | per-TPC range |
|---|---|---|
| 360× `wclsICARUSDrifter` / `DepoSetDrifter` / `Scaler` / `DepoSetScaler` (lines ~195–270) | `std.range(0, 359)` | `std.range(n_lo, n_hi-1)` (90 of each) |
| 360× `wclsDepoFluxWriter` SimChannel sinks (lines ~328–359) | `std.range(0, 359)` | `std.range(n_lo, n_hi-1)` (90 of them, but **instance names must stay `simpleSC<n>` with the global n** so each module produces its TPC's 90-out-of-360 simchannel instances with their original labels) |
| 360× `DepoSetFilterYZ` (lines ~438–449) | `std.range(0, 359)` | `std.range(n_lo, n_hi-1)` |
| 4× `FrameSummerYZ` (lines ~429–436) | `std.range(0, 3)` | just `[tpc_idx]` — 1 of them |
| 4× actpipes (line ~454) | `std.range(0, 3)` | just `[tpc_idx]` — 1 of them |
| `wcls_output.sim_digits` (line ~151) | `for n in std.range(0,3)` array | single element for this TPC; instance name stays `simdigits<tpc_idx>` |
| `fandrifter` topology in `funcs.jsonnet` (the `pipe_drift` factory) | fanoutmult/faninmult = 360 | 90 for the per-TPC build |

The pgrapher pipeline:

```jsonnet
local graph = g.pipeline([
    wcls_input.deposet,        // wclsSimDepoSetSource — same in every module
    pipe_drift,                // 90-way fanout + N drift pipes + per-anode DumpFrames sinks
    // FrameSummerYZ for this TPC fans 90 inputs → 1 frame
    actpipe                    // reframer → noise → coh_noise → digitizer → wclsFrameSaver
]);
```

Note: the `simchan_label: 'simpleSC%d' %n` on each `wclsDepoFluxWriter` should
**use the global n** (`n_lo + i` if we iterate `i in std.range(0, 89)`), so the
SimChannel instance names stay identical to the single-module run. The
*module-label* changes (daq → daq0/1/2/3) but the instance-name stays
`simpleSC0..359` exactly.

## Per-TPC fcl structure

For each TPC `k ∈ 0..3`:

```fhicl
daq<k>: {
   module_type: "WireCellToolkit"
   wcls_main: {
      apps: [ "Pgrapher" ]
      configs: [ "wcls-per-tpc-sim-drift-simchannel-yzsim.jsonnet" ]
      logsinks: ["stdout"]
      loglevels: ["debug"]
      params: { tpc_idx: "<k>" }        // wcls passes this through as --ext-str
      inputers: [
         "wclsSimDepoSetSource:electron"
      ]
      outputers: [
         "wclsFrameSaver:simdigits<k>",
         "wclsDepoFluxWriter:postdrift<n_lo>",
         "wclsDepoFluxWriter:postdrift<n_lo+1>",
         ...
         "wclsDepoFluxWriter:postdrift<n_hi-1>"
      ]
   }
}
```

And the `simulate` path picks up all four:

```fhicl
simulate: [
   ...,
   "daq0", "daq1", "daq2", "daq3"
]
```

The 91 outputers (1 RawDigit + 90 SimChannel) per module × 4 modules = 364
outputer entries total in the fcl. Generation-time scripting (the fcl is
already produced by `fhicl-dump`) makes this manageable.

## Concerns + mitigations

1. **RNG state** — each art module gets its own `RandomNumberGenerator`
   slot, so noise/diffusion in the 4 modules will use independent streams.
   Event content will differ from the single-module run at the bit level
   but will be statistically equivalent. Acceptable for memory-driven runs;
   would need re-seeding for bit-reproducibility against the old config.
2. **Duplicate work** — depos are read 4× and drift+diffusion runs 4×. This
   is the ~2× wall-time cost you've agreed to. SimChannel paths are
   non-duplicated (each module handles only its own 90 anode-planes).
3. **`wclsDepoFluxWriter` instance collisions** — each instance is named
   `postdrift<n>` with `n ∈ [n_lo, n_hi)`. Names are disjoint across the
   four modules, so no art-product-tag collisions.
4. **`wclsFrameSaver` instance names** — each module's saver is
   `simdigits<tpc_idx>`. Disjoint across modules. ✓
5. **wclsSimDepoSetSource** — the same art product (e.g. `largeant:`
   SimEnergyDeposit) is read by each of the 4 modules; that's a normal art
   pattern and Explore confirmed each `WCLS_tool` instance has its own
   `m_depos` so there's no shared state between modules.
6. **Shared geometry / DetectorProperties services** — stateless, no issue.
7. **Output product accumulation in art Event** — note that the 4 RawDigit
   collections (plus 360 SimChannel collections) still all live in the
   `art::Event` together until the event is written to file at end-of-event.
   The split frees the **WCT-internal float SimpleTraces** between modules
   (~3 GB win), but the int16 RawDigit collections (~180 MB × 4 TPCs ≈
   720 MB) still accumulate in the Event. This is unavoidable in art's
   producer model.

## Implementation steps

1. **Author** `wcdev-icarus/wcls-per-tpc-sim-drift-simchannel-yzsim.jsonnet`:
   - Copy `cfg/pgrapher/experiment/icarus/wcls-multitpc-sim-drift-simchannel-yzsim-refactored.jsonnet`
     into the new file.
   - Add `local tpc_idx = std.parseInt(std.extVar('tpc_idx'));` and the n_lo/n_hi
     locals at the top.
   - Replace each `std.range(0, 359)` with `std.range(n_lo, n_hi-1)`.
   - Replace each `std.range(0, 3)` (the 4-TPC array constructions) with `[tpc_idx]`,
     keeping the indexing so instance names like `simdigits<tpc_idx>` and
     `simpleSC<n>` stay aligned with the original.
   - Set the final pipeline to use only this TPC's branches.

2. **Author** `wcdev-icarus/detsim-yz-per-tpc-v10_20_03.fcl`:
   - Copy `detsim-yz-v10_20_03.fcl`.
   - Replace the single `daq` block with 4 blocks `daq0..3`, each pointing
     at the new jsonnet and passing the appropriate `tpc_idx`.
   - Replace `"daq"` in `simulate:` with `"daq0", "daq1", "daq2", "daq3"`.
   - In each `daq<k>`'s `outputers:` list, include `wclsFrameSaver:simdigits<k>`
     plus the 90 `wclsDepoFluxWriter:postdrift<n>` instances for that TPC's
     range.
   - Update `outputs.rootoutput.outputCommands` if needed (current "keep *"
     should already retain all four RawDigit collections regardless of module
     label).

3. **Smoke test** (one event, native, no valgrind):
   `tools/in-sl7.sh bash -c "cd $WCDEV && lar -n 1 -c detsim-yz-per-tpc-v10_20_03.fcl -s xroot://... -o detsim.root"`
   - Check `detsim.root` contains 4× `raw::RawDigits` (with module labels
     `daq0..daq3`, instance names `simdigits0..3`) and 360× `SimChannel`
     (instance names `simpleSC0..359` across the four module labels).
   - Run `lar -c eventdump.fcl detsim.root` (or the equivalent) and confirm
     product counts match the single-module run.

4. **Memory check** with the `top.sh` sampler, into
   `wcdev-icarus/run-20260516-per-tpc-top/`. Compare peak RSS and time-series
   against the `+C5` baseline.

5. **Validation** (optional): drop ART_DEBUG_CONFIG or compare a histogram of
   ADC values in one TPC against the single-module run to confirm content is
   statistically reasonable (will not be bit-identical due to RNG ordering).

## Verification checklist

- [ ] `detsim.root` exists, size comparable to baseline (~274 MB).
- [ ] `TrigReport Events passed = 1`.
- [ ] All four `simdigits0..3` collections appear in the output art file.
- [ ] All 360 `simpleSC<n>` collections appear in the output art file.
- [ ] `MemReport VmHWM` lower than the +C5 run's 9.00 GB.
- [ ] Real wall time within 1.5×–2.5× of the +C5 run (~22 min × 2 = ~45 min expected).

## Open questions for you

- Are you OK if the **process_name** in art stays "DetSim" (so the full
  4-part handle becomes e.g. `daq0:simdigits0::DetSim` rather than
  `daq:simdigits0::DetSim`)? Downstream selectors that match on
  process_name keep working; selectors that match exact module label
  (`daq`) do not.
- Any downstream module that wires up `daq:` explicitly? If yes, list the
  fcls so we can either supply an alias / refer-by-process module or update
  those fcls in lockstep.
- Do you want a *fifth* "merge" producer module that re-publishes the four
  per-TPC `daq<k>:simdigits<k>` collections under one shared label `daq`
  (just rename, no copy)? art supports this via a tiny custom producer or
  via `mix` modules. Adds zero memory but means one extra producer in the
  path and the `daq` label re-emerges.

---

Once you confirm (or answer the questions above), I'll author the two
files in `wcdev-icarus/` and run the smoke test.
