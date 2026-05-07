# wcdev-icarus
```bash
lar -n 1 -c eventdump.fcl -s xroot://fndca1.fnal.gov:1095/pnfs/fnal.gov/usr/icarus/persistent/stash/ContinuousIntegration/reference/standard/g4/intimecosmic_g4_test_icaruscode_Reference.root
lar -n 1 -c standard_mc_all_detsim_icarus.fcl -s xroot://fndca1.fnal.gov:1095/pnfs/fnal.gov/usr/icarus/persistent/stash/ContinuousIntegration/reference/standard/g4/intimecosmic_g4_test_icaruscode_Reference.root -o detsim.root
lar -n 1 -c detsim.fcl -s xroot://fndca1.fnal.gov:1095/pnfs/fnal.gov/usr/icarus/persistent/stash/ContinuousIntegration/reference/standard/g4/intimecosmic_g4_test_icaruscode_Reference.root -o detsim.root
lar -n 1 -c detsim-v10_06_00_06p04.fcl -s xroot://fndca1.fnal.gov:1095/pnfs/fnal.gov/usr/icarus/persistent/stash/ContinuousIntegration/reference/standard/g4/intimecosmic_g4_test_icaruscode_Reference.root -o detsim.root
```


```bash
lar --trace -n 1 -c detsim-yz-v10_20_03.fcl -s xroot://fndca1.fnal.gov:1095/pnfs/fnal.gov/usr/icarus/persistent/stash/ContinuousIntegration/reference/standard/g4/intimecosmic_g4_test_icaruscode_Reference.root -o detsim.root
```