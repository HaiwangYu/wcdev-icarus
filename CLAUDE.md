# wcdev-icarus

ICARUS / Wire-Cell development workspace. Drives `lar` jobs against ICARUS
detsim and validates Wire-Cell jsonnet configurations.

## Environment

All `lar`, `wirecell-*`, `jsonnet`, and `valgrind` commands must run inside
the Fermilab SL7 apptainer. The host shell does not have the right toolchain.

- Container entrypoint: `/exp/icarus/app/users/yuhw/wire-cell-toolkit/tools/in-sl7.sh`
  - Non-interactive wrapper around `apptainer exec` on
    `/cvmfs/singularity.opensciencegrid.org/fermilab/fnal-dev-sl7:latest`.
  - Sources `setup.sh` and `cd`s to `wire-cell-toolkit` before running the
    passed command.
  - Usage: `/exp/icarus/app/users/yuhw/wire-cell-toolkit/tools/in-sl7.sh <cmd> [args...]`
- In-container setup: `/exp/icarus/app/users/yuhw/wcdev-icarus/setup.sh`
  - Sources `setup_icarus.sh` from cvmfs and `setup icaruscode v10_20_03 -q e26:prof`.
  - Prepends `/exp/icarus/app/users/yuhw/opt/{lib,bin}` to `LD_LIBRARY_PATH` / `PATH`.
  - Activates the `wire-cell-python` venv at
    `/exp/sbnd/app/users/yuhw/wire-cell-python/venv`.

To run any command in the right environment:

```bash
/exp/icarus/app/users/yuhw/wire-cell-toolkit/tools/in-sl7.sh <command>
```

If you need a different working directory than `wire-cell-toolkit`, pass an
explicit `cd` as part of the command, e.g.

```bash
/exp/icarus/app/users/yuhw/wire-cell-toolkit/tools/in-sl7.sh \
  bash -c 'cd /exp/icarus/app/users/yuhw/wcdev-icarus && lar -n 1 -c detsim-yz-v10_20_03.fcl ...'
```

## Layout

- `setup.sh` — in-container environment setup (see above).
- `clean.sh` — removes the per-run output ROOT files
  (`-_detsim_hist.root`, `RootOutput-*.root`, `TFileService-*.root`,
  `Supplemental-*.root`).
- `wcls-multitpc-sim-drift-simchannel-yzsim-refactored.jsonnet` — Wire-Cell
  config under active development.
- `detsim-yz-v10_20_03.fcl` — fully-expanded fhicl (from
  `fhicl-dump detsim_2d_icarus_refactored_yzsim.fcl`); use it as the source
  of jsonnet `--ext-*` parameter values.
- `js.sh` — drives `jsonnet` (`json` / `pdf` / `all`) using `$WIRECELL_PATH`.
  Currently hard-coded for DUNE-VD; needs to be retargeted to
  `wcls-multitpc-sim-drift-simchannel-yzsim-refactored.jsonnet` with
  parameters taken from `detsim-yz-v10_20_03.fcl`.
- `massif.out.929` — output from the valgrind massif run documented in
  `README.md`.
- `run-20260507-01/` — prior run artifacts.

## Common tasks

Run a detsim job:

```bash
/exp/icarus/app/users/yuhw/wire-cell-toolkit/tools/in-sl7.sh \
  bash -c 'cd /exp/icarus/app/users/yuhw/wcdev-icarus && \
    lar --trace -n 1 -c detsim-yz-v10_20_03.fcl \
      -s xroot://fndca1.fnal.gov:1095/pnfs/fnal.gov/usr/icarus/persistent/stash/ContinuousIntegration/reference/standard/g4/intimecosmic_g4_test_icaruscode_Reference.root \
      -o detsim.root'
```

Generate / visualize the jsonnet graph (after retargeting `js.sh`):

```bash
/exp/icarus/app/users/yuhw/wire-cell-toolkit/tools/in-sl7.sh \
  bash -c 'cd /exp/icarus/app/users/yuhw/wcdev-icarus && ./js.sh all'
```

Memory profile with massif: see the recipe in `README.md`.

Clean per-run outputs: `./clean.sh` (safe to run on the host; only `rm`s).
