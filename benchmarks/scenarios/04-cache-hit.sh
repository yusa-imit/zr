#!/usr/bin/env bash
# Benchmark: Cache Hit Performance
# Measures time for task execution with cache enabled
# Scenario: Generate file, re-run task (should be cached and skip execution)

set -euo pipefail

BENCHMARK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="${BENCHMARK_DIR}/../results"
mkdir -p "${RESULTS_DIR}"

ITERATIONS="${BENCH_ITERATIONS:-50}"
WARMUP="${BENCH_WARMUP:-10}"

echo "=== Cache Hit Benchmark ==="
echo "Iterations: ${ITERATIONS}"
echo "Warmup: ${WARMUP}"
echo ""

# Create test project
TEST_DIR=$(mktemp -d)
trap "rm -rf ${TEST_DIR}" EXIT
cd "${TEST_DIR}"

# zr.toml with cache enabled
cat > zr.toml <<'EOF'
[tasks.generate]
cmd = "echo 'cached content' > output.txt"
cache_inputs = ["src/input.txt"]
cache_outputs = ["output.txt"]
EOF

# Create input file
mkdir -p src
echo "input data" > src/input.txt

# Makefile (no native caching)
cat > Makefile <<'EOF'
.PHONY: generate
generate:
	@echo 'cached content' > output.txt
EOF

# Justfile (no native caching)
cat > Justfile <<'EOF'
generate:
	echo 'cached content' > output.txt
EOF

# Taskfile.yml (has status/sources for caching)
cat > Taskfile.yml <<'EOF'
version: '3'
tasks:
  generate:
    cmds:
      - echo 'cached content' > output.txt
    sources:
      - src/input.txt
    generates:
      - output.txt
EOF

# package.json (no native caching)
cat > package.json <<'EOF'
{
  "scripts": {
    "generate": "echo 'cached content' > output.txt"
  }
}
EOF

# Measure zr (first run to populate cache, then measure cache hits)
echo "Benchmarking zr (with cache)..."
rm -f .zr/cache/* output.txt 2>/dev/null || true
zr run generate >/dev/null 2>&1 # Populate cache

ZR_TIMES=()
for ((i=1; i<=${WARMUP}+${ITERATIONS}; i++)); do
  START=$(date +%s%N)
  zr run generate >/dev/null 2>&1 # Should be cache hit
  END=$(date +%s%N)
  ELAPSED=$(( (END - START) / 1000000 )) # Convert to milliseconds
  if [ $i -gt ${WARMUP} ]; then
    ZR_TIMES+=($ELAPSED)
  fi
done

# Measure make (no caching, always re-runs)
echo "Benchmarking make (no cache)..."
MAKE_TIMES=()
for ((i=1; i<=${WARMUP}+${ITERATIONS}; i++)); do
  rm -f output.txt 2>/dev/null || true
  START=$(date +%s%N)
  make generate >/dev/null 2>&1
  END=$(date +%s%N)
  ELAPSED=$(( (END - START) / 1000000 ))
  if [ $i -gt ${WARMUP} ]; then
    MAKE_TIMES+=($ELAPSED)
  fi
done

# Measure just (no native caching)
JUST_TIMES=()
if command -v just &> /dev/null; then
  echo "Benchmarking just (no cache)..."
  for ((i=1; i<=${WARMUP}+${ITERATIONS}; i++)); do
    rm -f output.txt 2>/dev/null || true
    START=$(date +%s%N)
    just generate >/dev/null 2>&1
    END=$(date +%s%N)
    ELAPSED=$(( (END - START) / 1000000 ))
    if [ $i -gt ${WARMUP} ]; then
      JUST_TIMES+=($ELAPSED)
    fi
  done
fi

# Measure task (has status checking for caching)
TASK_TIMES=()
if command -v task &> /dev/null; then
  echo "Benchmarking task (with status check)..."
  rm -f output.txt 2>/dev/null || true
  task generate >/dev/null 2>&1 # First run

  for ((i=1; i<=${WARMUP}+${ITERATIONS}; i++)); do
    START=$(date +%s%N)
    task generate >/dev/null 2>&1 # Should detect up-to-date
    END=$(date +%s%N)
    ELAPSED=$(( (END - START) / 1000000 ))
    if [ $i -gt ${WARMUP} ]; then
      TASK_TIMES+=($ELAPSED)
    fi
  done
fi

# Measure npm (no caching)
NPM_TIMES=()
if command -v npm &> /dev/null; then
  echo "Benchmarking npm (no cache)..."
  for ((i=1; i<=${WARMUP}+${ITERATIONS}; i++)); do
    rm -f output.txt 2>/dev/null || true
    START=$(date +%s%N)
    npm run generate >/dev/null 2>&1
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
RESULTS_FILE="${RESULTS_DIR}/04-cache-hit_${TIMESTAMP}.csv"

echo "tool,mean_ms,median_ms,min_ms,max_ms,caching" > "$RESULTS_FILE"

ZR_STATS=$(calc_stats "${ZR_TIMES[@]}")
echo "zr,$ZR_STATS,content-based" >> "$RESULTS_FILE"

MAKE_STATS=$(calc_stats "${MAKE_TIMES[@]}")
echo "make,$MAKE_STATS,none" >> "$RESULTS_FILE"

if [ ${#JUST_TIMES[@]} -gt 0 ]; then
  JUST_STATS=$(calc_stats "${JUST_TIMES[@]}")
  echo "just,$JUST_STATS,none" >> "$RESULTS_FILE"
fi

if [ ${#TASK_TIMES[@]} -gt 0 ]; then
  TASK_STATS=$(calc_stats "${TASK_TIMES[@]}")
  echo "task,$TASK_STATS,timestamp-based" >> "$RESULTS_FILE"
fi

if [ ${#NPM_TIMES[@]} -gt 0 ]; then
  NPM_STATS=$(calc_stats "${NPM_TIMES[@]}")
  echo "npm,$NPM_STATS,none" >> "$RESULTS_FILE"
fi

echo ""
echo "=== Results ==="
cat "$RESULTS_FILE"
echo ""
echo "Results saved to: $RESULTS_FILE"
echo ""
echo "Note: zr uses content-based caching (hash of inputs), task uses timestamp comparison."
echo "Tools without caching (make/just/npm) always re-execute tasks."
