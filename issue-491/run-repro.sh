#!/bin/bash
set -uo pipefail
cd /exp/icarus/app/users/yuhw/wcdev-icarus/issue-491
INPUT=/exp/icarus/data/users/vito/ci_tests/ci_14907/ICARUS/single_detsim_seq_test_icaruscode/single_detsim_test_icaruscode_Current.root
# Process 2 events (crash reported on 2nd event). rethrow-all like CI.
lar --rethrow-all -n 2 \
    --TFileName hist-repro.root \
    -o repro_out.root \
    --config icarus_ci_single_reco0_seq_test_icaruscode.fcl \
    "$INPUT"
echo "LAR_EXIT=$?"
