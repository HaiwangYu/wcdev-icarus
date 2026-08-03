# Clean setup that reproduces the CI environment for issue 491.
# Sets up stock icaruscode v10_20_09p01 (-> wirecell v0_36_1), NO local overrides.
source /cvmfs/icarus.opensciencegrid.org/products/icarus/setup_icarus.sh
setup icaruscode v10_20_09p01 -q e26:prof
