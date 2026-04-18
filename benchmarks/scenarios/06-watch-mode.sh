#!/usr/bin/env bash
# Benchmark: Watch Mode Responsiveness
# Measures time from file change detection to task execution start
# Scenario: Watch src/*.txt files, measure trigger latency

set -euo pipefail

BENCHMARK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="${BENCHMARK_DIR}/../results"
mkdir -p "${RESULTS_DIR}"

ITERATIONS="${BENCH_ITERATIONS:-20}"
WARMUP="${BENCH_WARMUP:-3}"
WATCH_TIMEOUT=10 # Max seconds to wait for watch trigger

echo "=== Watch Mode Benchmark ==="
echo "Iterations: ${ITERATIONS}"
echo "Warmup: ${WARMUP}"
echo ""

# Create test project
TEST_DIR=$(mktemp -d)
trap "rm -rf ${TEST_DIR}" EXIT
cd "${TEST_DIR}"

mkdir -p src

# zr.toml
cat > zr.toml <<'EOF'
[tasks.build]
cmd = "date +%s%N > build.log"
watch = ["src/*.txt"]
EOF

# Makefile (no native watch, would need entr/watchexec wrapper)
cat > Makefile <<'EOF'
.PHONY: build
build:
	@date +%s%N > build.log
EOF

# Justfile (no native watch in most versions)
cat > Justfile <<'EOF'
build:
	date +%s%N > build.log
EOF

# Taskfile.yml (has watch via --watch flag)
cat > Taskfile.yml <<'EOF'
version: '3'
tasks:
  build:
    cmds:
      - date +%s%N > build.log
    sources:
      - src/*.txt
EOF

echo "Initial content" > src/input.txt

# Measure zr watch mode
echo "Benchmarking zr watch mode..."
ZR_TIMES=()

for ((i=1; i<=${WARMUP}+${ITERATIONS}; i++)); do
  # Start zr watch in background
  rm -f build.log
  zr watch build >/dev/null 2>&1 &
  WATCH_PID=$!
  sleep 0.5 # Let watcher initialize

  # Trigger file change and measure latency
  CHANGE_TIME=$(date +%s%N)
  echo "Change $i" > src/input.txt

  # Wait for build.log to appear (watcher triggered)
  for ((j=0; j<${WATCH_TIMEOUT}*10; j++)); do
    if [ -f build.log ]; then
      TRIGGER_TIME=$(cat build.log)
      break
    fi
    sleep 0.1
  done

  kill $WATCH_PID 2>/dev/null || true
  wait $WATCH_PID 2>/dev/null || true

  if [ -f build.log ]; then
    LATENCY=$(( (TRIGGER_TIME - CHANGE_TIME) / 1000000 )) # Convert to ms
    if [ $i -gt ${WARMUP} ]; then
      ZR_TIMES+=($LATENCY)
    fi
  else
    echo "Warning: Watch timeout on iteration $i" >&2
  fi

  sleep 0.2 # Cooldown between iterations
done

# Measure watchexec + make (common pattern for watch)
MAKE_TIMES=()
if command -v watchexec &> /dev/null; then
  echo "Benchmarking watchexec + make..."

  for ((i=1; i<=${WARMUP}+${ITERATIONS}; i++)); do
    rm -f build.log
    watchexec -w src --no-vcs-ignore -r -- make build >/dev/null 2>&1 &
    WATCH_PID=$!
    sleep 0.5

    CHANGE_TIME=$(date +%s%N)
    echo "Change $i" > src/input.txt

    for ((j=0; j<${WATCH_TIMEOUT}*10; j++)); do
      if [ -f build.log ]; then
        TRIGGER_TIME=$(cat build.log)
        break
      fi
      sleep 0.1
    done

    kill $WATCH_PID 2>/dev/null || true
    wait $WATCH_PID 2>/dev/null || true

    if [ -f build.log ]; then
      LATENCY=$(( (TRIGGER_TIME - CHANGE_TIME) / 1000000 ))
      if [ $i -gt ${WARMUP} ]; then
        MAKE_TIMES+=($LATENCY)
      fi
    fi

    sleep 0.2
  done
else
  echo "watchexec not found, skipping make comparison"
fi

# Measure task watch mode (if available)
TASK_TIMES=()
if command -v task &> /dev/null; then
  echo "Benchmarking task watch mode..."

  for ((i=1; i<=${WARMUP}+${ITERATIONS}; i++)); do
    rm -f build.log
    task --watch build >/dev/null 2>&1 &
    WATCH_PID=$!
    sleep 0.5

    CHANGE_TIME=$(date +%s%N)
    echo "Change $i" > src/input.txt

    for ((j=0; j<${WATCH_TIMEOUT}*10; j++)); do
      if [ -f build.log ]; then
        TRIGGER_TIME=$(cat build.log)
        break
      fi
      sleep 0.1
    done

    kill $WATCH_PID 2>/dev/null || true
    wait $WATCH_PID 2>/dev/null || true

    if [ -f build.log ]; then
      LATENCY=$(( (TRIGGER_TIME - CHANGE_TIME) / 1000000 ))
      if [ $i -gt ${WARMUP} ]; then
        TASK_TIMES+=($LATENCY)
      fi
    fi

    sleep 0.2
  done
fi

# Calculate statistics
calc_stats() {
  local arr=("$@")
  if [ ${#arr[@]} -eq 0 ]; then
    echo "N/A,N/A,N/A,N/A"
    return
  fi

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
RESULTS_FILE="${RESULTS_DIR}/06-watch-mode_${TIMESTAMP}.csv"

echo "tool,mean_ms,median_ms,min_ms,max_ms,watch_impl" > "$RESULTS_FILE"

ZR_STATS=$(calc_stats "${ZR_TIMES[@]}")
echo "zr,$ZR_STATS,native-inotify/kqueue" >> "$RESULTS_FILE"

if [ ${#MAKE_TIMES[@]} -gt 0 ]; then
  MAKE_STATS=$(calc_stats "${MAKE_TIMES[@]}")
  echo "make,$MAKE_STATS,watchexec-wrapper" >> "$RESULTS_FILE"
fi

if [ ${#TASK_TIMES[@]} -gt 0 ]; then
  TASK_STATS=$(calc_stats "${TASK_TIMES[@]}")
  echo "task,$TASK_STATS,native-watch" >> "$RESULTS_FILE"
fi

echo ""
echo "=== Results ==="
cat "$RESULTS_FILE"
echo ""
echo "Results saved to: $RESULTS_FILE"
echo ""
echo "Note: zr uses native file watching (inotify on Linux, kqueue on macOS)."
echo "Lower latency = faster response to file changes."
