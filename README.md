# wcdev-icarus
```bash
lar -n 1 -c eventdump.fcl -s xroot://fndca1.fnal.gov:1095/pnfs/fnal.gov/usr/icarus/persistent/stash/ContinuousIntegration/reference/standard/g4/intimecosmic_g4_test_icaruscode_Reference.root
lar -n 1 -c standard_mc_all_detsim_icarus.fcl -s xroot://fndca1.fnal.gov:1095/pnfs/fnal.gov/usr/icarus/persistent/stash/ContinuousIntegration/reference/standard/g4/intimecosmic_g4_test_icaruscode_Reference.root -o detsim.root
```


## v10_20_03
```bash
fhicl-dump detsim_2d_icarus_refactored_yzsim.fcl >& detsim-yz-v10_20_03.fcl
lar --trace -n 1 -c detsim-yz-v10_20_03.fcl -s xroot://fndca1.fnal.gov:1095/pnfs/fnal.gov/usr/icarus/persistent/stash/ContinuousIntegration/reference/standard/g4/intimecosmic_g4_test_icaruscode_Reference.root -o detsim.root
```