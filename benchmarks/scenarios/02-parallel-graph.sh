#!/usr/bin/env bash
# Benchmark: Parallel Execution Performance
# Measures parallel task scheduling efficiency
# Scenario: 4-task diamond graph (A → [B, C] → D)

set -euo pipefail

BENCHMARK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="${BENCHMARK_DIR}/../results"
mkdir -p "${RESULTS_DIR}"

ITERATIONS="${BENCH_ITERATIONS:-50}"
WARMUP="${BENCH_WARMUP:-5}"
TASK_SLEEP="${TASK_SLEEP_MS:-100}" # Simulate 100ms work per task

echo "=== Parallel Execution Benchmark ==="
echo "Iterations: ${ITERATIONS}"
echo "Warmup: ${WARMUP}"
echo "Task sleep: ${TASK_SLEEP}ms"
echo ""

# Create test project
TEST_DIR=$(mktemp -d)
trap "rm -rf ${TEST_DIR}" EXIT
cd "${TEST_DIR}"

# Helper script for simulated work
cat > work.sh <<EOF
#!/bin/sh
sleep 0.${TASK_SLEEP}
echo "Task \$1 complete"
EOF
chmod +x work.sh

# zr.toml (diamond graph with deps)
cat > zr.toml <<EOF
[tasks.a]
cmd = "./work.sh A"

[tasks.b]
cmd = "./work.sh B"
deps = ["a"]

[tasks.c]
cmd = "./work.sh C"
deps = ["a"]

[tasks.d]
cmd = "./work.sh D"
deps = ["b", "c"]
EOF

# Makefile (using -j for parallel)
cat > Makefile <<EOF
.PHONY: a b c d

a:
	@./work.sh A

b: a
	@./work.sh B

c: a
	@./work.sh C

d: b c
	@./work.sh D
EOF

# Justfile (just doesn't support parallel deps well, so sequential)
cat > Justfile <<EOF
a:
	./work.sh A

b: a
	./work.sh B

c: a
	./work.sh C

d: b c
	./work.sh D
EOF

# Taskfile.yml (parallel execution via task)
cat > Taskfile.yml <<EOF
version: '3'
tasks:
  a:
    cmds:
      - ./work.sh A

  b:
    deps: [a]
    cmds:
      - ./work.sh B

  c:
    deps: [a]
    cmds:
      - ./work.sh C

  d:
    deps: [b, c]
    cmds:
      - ./work.sh D
EOF

# Measure zr
echo "Benchmarking zr..."
ZR_TIMES=()
for ((i=1; i<=${WARMUP}+${ITERATIONS}; i++)); do
  START=$(date +%s%N)
  zr run d >/dev/null 2>&1
  END=$(date +%s%N)
  ELAPSED=$(( (END - START) / 1000000 ))
  if [ $i -gt ${WARMUP} ]; then
    ZR_TIMES+=($ELAPSED)
  fi
done

# Measure make (parallel)
echo "Benchmarking make -j4..."
MAKE_TIMES=()
for ((i=1; i<=${WARMUP}+${ITERATIONS}; i++)); do
  START=$(date +%s%N)
  make -j4 d >/dev/null 2>&1
  END=$(date +%s%N)
  ELAPSED=$(( (END - START) / 1000000 ))
  if [ $i -gt ${WARMUP} ]; then
    MAKE_TIMES+=($ELAPSED)
  fi
done

# Measure just (sequential, no good parallel support)
JUST_TIMES=()
if command -v just &> /dev/null; then
  echo "Benchmarking just (sequential)..."
  for ((i=1; i<=${WARMUP}+${ITERATIONS}; i++)); do
    START=$(date +%s%N)
    just d >/dev/null 2>&1
    END=$(date +%s%N)
    ELAPSED=$(( (END - START) / 1000000 ))
    if [ $i -gt ${WARMUP} ]; then
      JUST_TIMES+=($ELAPSED)
    fi
  done
fi

# Measure task
TASK_TIMES=()
if command -v task &> /dev/null; then
  echo "Benchmarking task..."
  for ((i=1; i<=${WARMUP}+${ITERATIONS}; i++)); do
    START=$(date +%s%N)
    task d >/dev/null 2>&1
    END=$(date +%s%N)
    ELAPSED=$(( (END - START) / 1000000 ))
    if [ $i -gt ${WARMUP} ]; then
      TASK_TIMES+=($ELAPSED)
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
RESULTS_FILE="${RESULTS_DIR}/02-parallel-graph_${TIMESTAMP}.csv"

echo "tool,mean_ms,median_ms,min_ms,max_ms" > "$RESULTS_FILE"

ZR_STATS=$(calc_stats "${ZR_TIMES[@]}")
echo "zr,$ZR_STATS" >> "$RESULTS_FILE"

MAKE_STATS=$(calc_stats "${MAKE_TIMES[@]}")
echo "make -j4,$MAKE_STATS" >> "$RESULTS_FILE"

if [ ${#JUST_TIMES[@]} -gt 0 ]; then
  JUST_STATS=$(calc_stats "${JUST_TIMES[@]}")
  echo "just (sequential),$JUST_STATS" >> "$RESULTS_FILE"
fi

if [ ${#TASK_TIMES[@]} -gt 0 ]; then
  TASK_STATS=$(calc_stats "${TASK_TIMES[@]}")
  echo "task,$TASK_STATS" >> "$RESULTS_FILE"
fi

echo ""
echo "=== Results ==="
cat "$RESULTS_FILE"
echo ""
echo "Ideal parallel time: ~$((TASK_SLEEP * 3))ms (3 serial stages: A, [B||C], D)"
echo "Results saved to: $RESULTS_FILE"
