#!/usr/bin/env bash
# ============================================================================
#  run_sim.sh — launch Gazebo + ArduPilot SITL TOGETHER with the flying-wing quadplane.
#  One command. Works on macOS (Jetty) and Linux (Harmonic/Jetty).
#    macOS  -> Gazebo server (-s) and GUI (-g) are launched as separate processes.
#    Linux  -> a single `gz sim -r` runs both.
#  Ctrl-C in this terminal stops Gazebo too (cleanup trap).
# ============================================================================
set -uo pipefail

# SIM_DIR="${SIM_DIR:-$HOME/flying_wing_quadplane_sim}"
WORLD="./worlds/quadplane_runway.sdf"
PARM="./config/flying_wing_quadplane.parm"
GZ_ARGS="${GZ_ARGS:--v4}"          # extra args for gz sim (override with env if you like)

# Make Gazebo resolve  model://flying_wing_quadplane  no matter where this project
# lives. This is the fix for "error code 14" = a URI in the world could not be resolved.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
export GZ_SIM_RESOURCE_PATH="$HERE/models:$HERE/worlds:${GZ_SIM_RESOURCE_PATH:-}"
echo "GZ_SIM_RESOURCE_PATH includes: $HERE/models"

[ -f "$WORLD" ] || { echo "World not found: $WORLD"; exit 1; }
[ -f "$PARM" ]  || { echo "Param file not found: $PARM"; exit 1; }
command -v gz >/dev/null 2>&1 || { echo "'gz' not found — is Gazebo installed / sourced?"; exit 1; }
command -v sim_vehicle.py >/dev/null 2>&1 || { echo "sim_vehicle.py not found — run: . ~/.profile"; exit 1; }

# open-file limit (macOS default 256 / Linux 1024 are both too low for Gazebo+SITL)
ulimit -n 65535 2>/dev/null || ulimit -n 10240 2>/dev/null || true
echo "open-file limit: $(ulimit -n)"

pids=()
cleanup(){ echo; echo "stopping Gazebo…"; for p in "${pids[@]:-}"; do kill "$p" 2>/dev/null || true; done; }
trap cleanup EXIT INT TERM

echo "starting Gazebo ($(uname))…"
if [ "$(uname)" = "Darwin" ]; then
  gz sim $GZ_ARGS -s -r "$WORLD" &  pids+=("$!")   # physics server
  gz sim $GZ_ARGS -g             &  pids+=("$!")   # GUI (separate process on macOS)
else
  gz sim $GZ_ARGS -r "$WORLD"    &  pids+=("$!")   # server + GUI in one
fi

echo "waiting for Gazebo to come up…"
sleep 4

echo "starting ArduPilot SITL (ArduPlane quadplane)…"
sim_vehicle.py -v ArduPlane -f gazebo-zephyr --model JSON \
    --add-param-file="$PARM" --map --console

# when SITL exits, the trap stops Gazebo.
