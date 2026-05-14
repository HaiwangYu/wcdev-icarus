#!/bin/bash

# Render the ICARUS Wire-Cell jsonnet to a JSON graph (and optional PDF).
#
# Values for the --ext-{str,code} flags are taken from the WCLS tool block
# in detsim-yz-v10_20_03.fcl (params + structs at L452-486).  Update this
# script and that fcl together.

J_ARGS=""
IFS=':' read -ra cfg_dirs <<< "$WIRECELL_PATH"
for (( idx=${#cfg_dirs[@]}-1; idx>=0; idx-- )); do
    J_ARGS="$J_ARGS -J ${cfg_dirs[$idx]}"
done

name=${2:-wcls-multitpc-sim-drift-simchannel-yzsim-refactored.jsonnet}
name=${name%.jsonnet}
input_jsonnet="${name}.jsonnet"
output_name=$(basename "$name")

if [[ ! -f "$input_jsonnet" ]]; then
    if [[ -n "$WIRECELL_PATH" ]]; then
        IFS=':' read -ra cfg_dirs <<< "$WIRECELL_PATH"
        for cfg_dir in "${cfg_dirs[@]}"; do
            if [[ -f "$cfg_dir/$input_jsonnet" ]]; then
                input_jsonnet="$cfg_dir/$input_jsonnet"
                break
            fi
        done
    fi
fi

if [[ $1 == "json" || $1 == "all" ]]; then
jsonnet \
--max-stack 5000 \
--ext-str SimEnergyDepositLabel="filtersed" \
--ext-str cathode_input_format="array" \
--ext-str file_rcresp="icarus_fnal_rc_tail.json" \
--ext-code DL=4e-9 \
--ext-code DT=8.8e-9 \
--ext-code lifetime=3000 \
--ext-code gain0=1.705212e1 \
--ext-code gain1=1.26181926e1 \
--ext-code gain2=1.30261362e1 \
--ext-code shaping0=1.3 \
--ext-code shaping1=1.45 \
--ext-code shaping2=1.3 \
--ext-code time_offset_u=0 \
--ext-code time_offset_v=0 \
--ext-code time_offset_y=0 \
--ext-code int_noise_scale=1 \
--ext-code coh_noise_scale=1 \
--ext-code overlay_drifter=false \
$J_ARGS \
"$input_jsonnet" \
-o "${output_name}.json"
fi

if [[ $1 == "pdf" || $1 == "all" ]]; then
    wirecell-pgraph dotify --jpath -1 --no-params "${output_name}.json" "${output_name}.pdf"
fi
