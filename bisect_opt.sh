#!/usr/bin/env bash
# bisect_opt.sh – Identify the optimization pass causing the problem

# Usage:
#   ./bisect_opt.sh '<compiler command>' <source.c> '<expected-output-pattern>'
#
# Example usage from ISVC 06622551: ./bisect_opt.sh ifx test.f90 '240.0000      0.0000000E+00'
# CMPLRLLVM-69793: ./bisect_opt.sh icx test_mf_conversion_strict.c 'FAIL: Mismatch detected between original and volatile loop!'
set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "Usage: $0 '<compiler command>' <source-file> \"<expected-output-pattern>\""
  exit 1
fi

COMPILER_CMD="$1"
SOURCE="$2"
PATTERN="$3"

# Compile with optimizations to ensure the bug is still there
echo "🔧 Testing with -O2..."
eval "$COMPILER_CMD -O2 \"$SOURCE\" -o a.out_opt"

if ! ./a.out_opt | grep "$PATTERN"; then
  echo "✅ Passes with -O2; this compiler version has this problem fixed."
  exit 1
else
  echo "❌ Fails at -O2; may be an optimization issue."
fi

# Compile without optimizations to ensure the bug disappears at -O0
echo "🔧 Testing with -O0 to ensure failure disappears..."
eval "$COMPILER_CMD -O0 \"$SOURCE\" -o a.out_noopt"

if ! ./a.out_noopt | grep "$PATTERN"; then
  echo "✅ Passes with -O0; optimization is the likely culprit."
else
  echo "❌ Still fails at -O0; may not be an optimization issue."
  exit 1
fi

# Discover the maximum pass index
echo "📋 Enumerating passes..."
eval "$COMPILER_CMD -O2 -mllvm -opt-bisect-limit=-1 \"$SOURCE\" -o /dev/null" 2>passes.log || true

INDEXES=($(grep -oP '^\s*BISECT: running pass \(\K[0-9]+' passes.log))
if [ ${#INDEXES[@]} -eq 0 ]; then
  echo "❌ Could not find any optimization passes."
  exit 1
fi

LOW=0
HIGH=${INDEXES[-1]}
echo "🔍 Starting binary search between pass index $LOW and $HIGH"

# Binary search to find the minimal failing pass
while (( LOW < HIGH )); do
  MID=$(((LOW + HIGH) / 2))
  echo "⚙️  Testing with -opt-bisect-limit=$MID..."

  if eval "$COMPILER_CMD -O2 -mllvm -opt-bisect-limit=$MID \"$SOURCE\" -o a.out"; then
    if ./a.out | grep "$PATTERN"; then
      echo "❌ Issue reproduced at limit=$MID"
      HIGH=$MID
    else
      echo "✅ Output OK at limit=$MID"
      LOW=$((MID + 1))
    fi
  else
    echo "❌ Compilation failed at limit=$MID"
    LOW=$((MID + 1))
  fi
done

echo "🎯 Problematic pass index: $LOW"

# Show pass name at failing index
echo "🔎 Looking up pass name for index $LOW..."
eval "$COMPILER_CMD -O2 -mllvm -opt-bisect-limit=-1 \"$SOURCE\" -o /dev/null" 2>all_passes.log || true
grep -E "running pass.*\($LOW\)" all_passes.log || echo "⚠️ Pass name not found for index $LOW"



# IR GENERATION
PREV=$((LOW > 0 ? LOW - 1 : 0))
echo "🧬 Generating IR for comparison..."

echo "🔹 IR before failing pass (limit=$PREV): before.ll"
eval "$COMPILER_CMD -O2 -S -emit-llvm -mllvm -opt-bisect-limit=$PREV \"$SOURCE\" -o before.ll"

echo "🔸 IR at failing pass (limit=$LOW): after.ll"
eval "$COMPILER_CMD -O2 -S -emit-llvm -mllvm -opt-bisect-limit=$LOW \"$SOURCE\" -o after.ll"

echo "📄 Use: diff -u before.ll after.ll | less"