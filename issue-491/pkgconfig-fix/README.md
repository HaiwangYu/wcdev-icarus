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

See `WireCell_Build_Cheat_Sheet.pdf` for the full corrected build recipe.
