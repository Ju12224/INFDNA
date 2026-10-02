#!/bin/bash
# usage: run_seeds.sh <projdir> <outfile> <mins> <seeds...>   (extra env passes through: STEP, QUEEN, BOT)
proj=$1; out=$2; mins=$3; shift 3
GD=/home/claude/godot/Godot_v3.5.3-stable_linux_headless.64
: > "$out"
for s in "$@"; do
  ( cd "$proj" && SEED=$s MINS=$mins $GD --no-window --path . -s bal.gd 2>&1 | grep "^TL\|^ROW\|^LEDGER\|^PERF" >> "$out" )
done
echo DONE >> "$out"
