#!/usr/bin/env bash
# Benchmark: Hot Run Performance
# Measures time for repeated task execution with warm cache
# Scenario: Execute same task 10x in a row (process reuse benefit)

set -euo pipefail

BENCHMARK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="${BENCHMARK_DIR}/../results"
mkdir -p "${RESULTS_DIR}"

ITERATIONS="${BENCH_ITERATIONS:-20}"
WARMUP="${BENCH_WARMUP:-5}"
TASK_REPETITIONS=10 # Run same task N times per iteration

echo "=== Hot Run Benchmark ==="
echo "Iterations: ${ITERATIONS}"
echo "Warmup: ${WARMUP}"
echo "Task repetitions per iteration: ${TASK_REPETITIONS}"
echo ""

# Create test project
TEST_DIR=$(mktemp -d)
trap "rm -rf ${TEST_DIR}" EXIT
cd "${TEST_DIR}"

# zr.toml
cat > zr.toml <<'EOF'
[tasks.compute]
cmd = "expr 12345 + 67890 > /dev/null"
EOF

# Makefile
cat > Makefile <<'EOF'
.PHONY: compute
compute:
	@expr 12345 + 67890 > /dev/null
EOF

# Justfile
cat > Justfile <<'EOF'
compute:
	expr 12345 + 67890 > /dev/null
EOF

# Taskfile.yml
cat > Taskfile.yml <<'EOF'
version: '3'
tasks:
  compute:
    cmds:
      - expr 12345 + 67890 > /dev/null
EOF

# package.json
cat > package.json <<'EOF'
{
  "scripts": {
    "compute": "expr 12345 + 67890 > /dev/null"
  }
}
EOF

# Measure zr (run task 10x, measure total time)
echo "Benchmarking zr..."
ZR_TIMES=()
for ((i=1; i<=${WARMUP}+${ITERATIONS}; i++)); do
  START=$(date +%s%N)
  for ((j=1; j<=${TASK_REPETITIONS}; j++)); do
    zr run compute >/dev/null 2>&1
  done
  END=$(date +%s%N)
  ELAPSED=$(( (END - START) / 1000000 )) # Convert to milliseconds
  if [ $i -gt ${WARMUP} ]; then
    ZR_TIMES+=($ELAPSED)
  fi
done

# Measure make
echo "Benchmarking make..."
MAKE_TIMES=()
for ((i=1; i<=${WARMUP}+${ITERATIONS}; i++)); do
  START=$(date +%s%N)
  for ((j=1; j<=${TASK_REPETITIONS}; j++)); do
    make compute >/dev/null 2>&1
  done
  END=$(date +%s%N)
  ELAPSED=$(( (END - START) / 1000000 ))
  if [ $i -gt ${WARMUP} ]; then
    MAKE_TIMES+=($ELAPSED)
  fi
done

# Measure just (if available)
JUST_TIMES=()
if command -v just &> /dev/null; then
  echo "Benchmarking just..."
  for ((i=1; i<=${WARMUP}+${ITERATIONS}; i++)); do
    START=$(date +%s%N)
    for ((j=1; j<=${TASK_REPETITIONS}; j++)); do
      just compute >/dev/null 2>&1
    done
    END=$(date +%s%N)
    ELAPSED=$(( (END - START) / 1000000 ))
    if [ $i -gt ${WARMUP} ]; then
      JUST_TIMES+=($ELAPSED)
    fi
  done
fi

# Measure task (if available)
TASK_TIMES=()
if command -v task &> /dev/null; then
  echo "Benchmarking task..."
  for ((i=1; i<=${WARMUP}+${ITERATIONS}; i++)); do
    START=$(date +%s%N)
    for ((j=1; j<=${TASK_REPETITIONS}; j++)); do
      task compute >/dev/null 2>&1
    done
    END=$(date +%s%N)
    ELAPSED=$(( (END - START) / 1000000 ))
    if [ $i -gt ${WARMUP} ]; then
      TASK_TIMES+=($ELAPSED)
    fi
  done
fi

# Measure npm (if available)
NPM_TIMES=()
if command -v npm &> /dev/null; then
  echo "Benchmarking npm..."
  for ((i=1; i<=${WARMUP}+${ITERATIONS}; i++)); do
    START=$(date +%s%N)
    for ((j=1; j<=${TASK_REPETITIONS}; j++)); do
      npm run compute >/dev/null 2>&1
    done
    END=$(date +%s%N)
    ELAPSED=$(( (END - START) / 1000000 ))
    if [ $i -gt ${WARMUP} ]; then
      NPM_TIMES+=($ELAPSED)
    fi
  done
fi

# Calculate statistics
calc_stats() {
  local arr=("$@")
  local sum=0
  local min=${arr[0]}
  local max=${arr[0]}

  for val in "${arr[@]}"; do
    sum=$((sum + val))
    [ $val -lt $min ] && min=$val
    [ $val -gt $max ] && max=$val
  done

  local mean=$((sum / ${#arr[@]}))

  # Calculate median
  IFS=$'\n' sorted=($(sort -n <<<"${arr[*]}"))
  unset IFS
  local mid=$((${#sorted[@]} / 2))
  local median=${sorted[$mid]}

  echo "$mean,$median,$min,$max"
}

# Output results
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_FILE="${RESULTS_DIR}/03-hot-run_${TIMESTAMP}.csv"

echo "tool,mean_ms,median_ms,min_ms,max_ms" > "$RESULTS_FILE"

ZR_STATS=$(calc_stats "${ZR_TIMES[@]}")
echo "zr,$ZR_STATS" >> "$RESULTS_FILE"

MAKE_STATS=$(calc_stats "${MAKE_TIMES[@]}")
echo "make,$MAKE_STATS" >> "$RESULTS_FILE"

if [ ${#JUST_TIMES[@]} -gt 0 ]; then
  JUST_STATS=$(calc_stats "${JUST_TIMES[@]}")
  echo "just,$JUST_STATS" >> "$RESULTS_FILE"
fi

if [ ${#TASK_TIMES[@]} -gt 0 ]; then
  TASK_STATS=$(calc_stats "${TASK_TIMES[@]}")
  echo "task,$TASK_STATS" >> "$RESULTS_FILE"
fi

if [ ${#NPM_TIMES[@]} -gt 0 ]; then
  NPM_STATS=$(calc_stats "${NPM_TIMES[@]}")
  echo "npm,$NPM_STATS" >> "$RESULTS_FILE"
fi

echo ""
echo "=== Results ==="
cat "$RESULTS_FILE"
echo ""
echo "Results saved to: $RESULTS_FILE"
