#!/usr/bin/env bash
# Regenerates every texture, model, level and sound from source, then imports them.
set -euo pipefail
cd "$(dirname "$0")/.."
for script in gen_textures gen_space gen_audio gen_music ship_player ship_mounts robots props arsenal enemies wall_parts harbor_ring; do
  echo "== $script"
  blender -b --factory-startup --python "tools/blender/$script.py" | grep -E '^\[|Error|Traceback' || true
done
for level in first_shift the_vein black_shaft smelter_row hollow_reach deep_cut overseer_pit glass_seam last_light core_zero; do
  echo "== level $level"
  blender -b --factory-startup --python tools/blender/level.py -- "$level" | grep -E '^\[|Error|Traceback' || true
done
godot --headless --import --path .
