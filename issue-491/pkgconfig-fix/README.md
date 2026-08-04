# WCT master build fix — external-fmtlib SPDLOG

Fixes the build error seen with `wire-cell-toolkit/master`:

```
../util/inc/WireCellUtil/Spdlog.h:55:2: error:
    #error WCT requires SPDLOG to be compiled against external fmtlib
```

## Cause

WCT `master` (commit `1387e712`) requires SPDLOG built against **external**
fmtlib. `wcb` discovers SPDLOG via `pkg-config`, and `spdlog v1_9_2` bundles fmt
— its `spdlog.pc` has no `-DSPDLOG_FMT_EXTERNAL` — so the `#error` fires.

## Fix

1. Set up the external-fmtlib SPDLOG plus a standalone fmt (replaces
   `setup spdlog v1_9_2 -q e26:prof`):

   ```
   setup spdlog v1_14_1 -q e26:prof
   setup fmt    v11_0_2 -q e26:prof
   ```

2. The cvmfs `.pc` files carry a stale `prefix=/scratch/workspace/...`, so drop
   the corrected `spdlog.pc` and `fmt.pc` here into your local
   `PKG_CONFIG_PATH` override dir (keep it first on the path):

   ```
   cp spdlog.pc fmt.pc /home/usher/test/wirecell/pkgconfig/
   export PKG_CONFIG_PATH=/home/usher/test/wirecell/pkgconfig:$PKG_CONFIG_PATH
   pkg-config --cflags spdlog   # MUST show -DSPDLOG_FMT_EXTERNAL and an -I.../fmt/.../include
   ```

3. Clean-reconfigure and rebuild (`./wcb configure ...` then `./wcb`).

`spdlog.pc` here points at `spdlog v1_14_1` (external fmt) and carries
`-DSPDLOG_FMT_EXTERNAL` + `Requires: fmt`; `fmt.pc` points at `fmt v11_0_2`.
Adjust the `prefix=` lines if you use a different qualifier (e.g. `e28`).

## Second gotcha: missing `WireCellPytorch` plugin

After the spdlog fix, a job may still die at construction with:

```
failed to load plugin: WireCellPytorch
../util/src/PluginManager.cxx(67): Throw ... IOError
[WireCell::tag_errmsg*] = failed to load plugin: WireCellPytorch
Art has completed and will exit with status 9.
```

The reco configs (`decon2droi*`) list the `WireCellPytorch` plugin, but if
`libtorch` is not set up when you run `./wcb configure`, wcb drops the pytorch
package (`Removing package pytorch ... LIB_LIBTORCH`) and never builds
`libWireCellPytorch.so`.

Fix: set up libtorch and enable it at configure time:

```
setup libtorch v2_1_1b -q e26            # add to the Dependencies block
./wcb configure ... --with-libtorch=$LIBTORCH_FQ_DIR
```

Configure output must list `pytorch` under "Configured for submodules:" (and
must NOT say "Removing package pytorch"). After `./wcb install`, verify:

```
ls $PREFIX/lib/libWireCellPytorch.so
```

Verified locally against WCT `master` + `libtorch v2_1_1b`: the package builds
and `libWireCellPytorch.so` links `libtorch.so` / `libtorch_cpu.so` / `libc10.so`.

See `WireCell_Build_Cheat_Sheet.pdf` for the full corrected build recipe.
