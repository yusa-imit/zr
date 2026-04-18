#!/usr/bin/env bash
# Benchmark: Cold Start Performance
# Measures time from invocation to task execution start
# Scenario: Single no-op task (echo "hello")

set -euo pipefail

BENCHMARK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="${BENCHMARK_DIR}/../results"
mkdir -p "${RESULTS_DIR}"

ITERATIONS="${BENCH_ITERATIONS:-100}"
WARMUP="${BENCH_WARMUP:-10}"

echo "=== Cold Start Benchmark ==="
echo "Iterations: ${ITERATIONS}"
echo "Warmup: ${WARMUP}"
echo ""

# Create test project
TEST_DIR=$(mktemp -d)
trap "rm -rf ${TEST_DIR}" EXIT
cd "${TEST_DIR}"

# zr.toml
cat > zr.toml <<'EOF'
[tasks.hello]
cmd = "echo hello"
EOF

# Makefile
cat > Makefile <<'EOF'
.PHONY: hello
hello:
	@echo hello
EOF

# Justfile
cat > Justfile <<'EOF'
hello:
	echo hello
EOF

# Taskfile.yml
cat > Taskfile.yml <<'EOF'
version: '3'
tasks:
  hello:
    cmds:
      - echo hello
EOF

# package.json
cat > package.json <<'EOF'
{
  "scripts": {
    "hello": "echo hello"
  }
}
EOF

# Measure zr
echo "Benchmarking zr..."
ZR_TIMES=()
for ((i=1; i<=${WARMUP}+${ITERATIONS}; i++)); do
  START=$(date +%s%N)
  zr run hello >/dev/null 2>&1
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
  make hello >/dev/null 2>&1
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
    just hello >/dev/null 2>&1
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
    task hello >/dev/null 2>&1
    END=$(date +%s%N)
    ELAPSED=$(( (END - START) / 1000000 ))
    if [ $i -gt ${WARMUP} ]; then
      TASK_TIMES+=($ELAPSED)
    fi
  done
fi

# Measure npm (if package.json script runner available)
NPM_TIMES=()
if command -v npm &> /dev/null; then
  echo "Benchmarking npm..."
  for ((i=1; i<=${WARMUP}+${ITERATIONS}; i++)); do
    START=$(date +%s%N)
    npm run hello >/dev/null 2>&1
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
RESULTS_FILE="${RESULTS_DIR}/01-cold-start_${TIMESTAMP}.csv"

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
