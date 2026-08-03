#!/bin/bash
# Re-run the 2D repro but with the patched libWireCellSigProc.so shadowing the
# cvmfs v0.36.1 one. Everything else stays stock v0.36.1 (same version -> ABI safe).
set -uo pipefail
cd /exp/icarus/app/users/yuhw/wcdev-icarus/issue-491
FIXLIB=/exp/icarus/app/users/yuhw/wcdev-icarus/issue-491/wct-src/build/sigproc/libWireCellSigProc.so
if [ ! -e "$FIXLIB" ]; then echo "MISSING $FIXLIB"; exit 2; fi
export LD_PRELOAD="$FIXLIB${LD_PRELOAD:+:$LD_PRELOAD}"
echo "LD_PRELOAD=$LD_PRELOAD"
INPUT=/exp/icarus/data/users/vito/ci_tests/ci_14907/ICARUS/single_detsim_seq_test_icaruscode/single_detsim_test_icaruscode_Current.root
lar --rethrow-all -n 2 -c repro2d.fcl -s "$INPUT"
echo "LAR_EXIT=$?"
