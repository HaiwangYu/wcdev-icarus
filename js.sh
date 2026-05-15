#!/bin/bash

# Render the ICARUS Wire-Cell jsonnet to JSON / PDF / SVG / HTML.
#
# Usage: js.sh {json|pdf|svg|html|all} [jsonnet-name]
#   json: jsonnet -> .json
#   pdf:  .json   -> .pdf  (single huge page; only useful for small graphs)
#   svg:  .json   -> .svg  (vector, zoom/Ctrl-F in any browser; recommended)
#   html: .svg    -> .html (svg-pan-zoom wrapper; needs CDN for js library)
#   all:  json + svg + html
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

if [[ $1 == "pdf" ]]; then
    wirecell-pgraph dotify --jpath -1 --no-params "${output_name}.json" "${output_name}.pdf"
fi

if [[ $1 == "svg" || $1 == "all" ]]; then
    wirecell-pgraph dotify --jpath -1 --no-params "${output_name}.json" "${output_name}.svg"
fi

if [[ $1 == "html" || $1 == "all" ]]; then
    cat > "${output_name}.html" <<HTML
<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>${output_name}</title>
<style>
  html,body { margin:0; height:100%; background:#222; color:#eee; font-family:sans-serif; }
  #controls { position:fixed; top:8px; left:8px; z-index:10;
              background:#333; padding:6px 8px; border-radius:4px; font-size:12px; }
  #controls button { margin-right:4px; }
  #frame { width:100vw; height:100vh; border:0; display:block; background:#fff; }
</style></head>
<body>
<div id="controls">
  <button onclick="zoom.zoomIn()">+</button>
  <button onclick="zoom.zoomOut()">-</button>
  <button onclick="zoom.resetZoom();zoom.resetPan()">reset</button>
  <button onclick="zoom.fit();zoom.center()">fit</button>
  <span>drag = pan, scroll = zoom, Ctrl+F in the SVG = search labels</span>
</div>
<object id="frame" type="image/svg+xml" data="${output_name}.svg"></object>
<script src="https://cdn.jsdelivr.net/npm/svg-pan-zoom@3.6.1/dist/svg-pan-zoom.min.js"></script>
<script>
  let zoom;
  document.getElementById('frame').addEventListener('load', function() {
    zoom = svgPanZoom(this.contentDocument.documentElement, {
      zoomScaleSensitivity: 0.4, minZoom: 0.05, maxZoom: 50,
      controlIconsEnabled: false, fit: true, center: true,
    });
  });
</script>
</body></html>
HTML
fi
