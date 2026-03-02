#!/usr/bin/env bash

# Performance Benchmark Suite for zr
# Compares zr against Make, Just, and Task (if available)

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== zr Performance Benchmark Suite ===${NC}\n"

# Check if hyperfine is installed
if ! command -v hyperfine &> /dev/null; then
    echo -e "${RED}Error: hyperfine is required but not installed.${NC}"
    echo "Install with: brew install hyperfine (macOS) or cargo install hyperfine"
    exit 1
fi

# Check if zr is built
if [ ! -f "../zig-out/bin/zr" ]; then
    echo -e "${YELLOW}Building zr first...${NC}"
    (cd .. && zig build -Doptimize=ReleaseFast)
fi

ZR="../zig-out/bin/zr"

# Create benchmark workspace
BENCH_DIR=$(mktemp -d)
trap "rm -rf $BENCH_DIR" EXIT

cd "$BENCH_DIR"

echo -e "${GREEN}Benchmark workspace: $BENCH_DIR${NC}\n"

# ============================================
# Benchmark 1: Cold Start (minimal config)
# ============================================
echo -e "${BLUE}[1/4] Cold Start Performance${NC}"

cat > zr.toml << 'TOML'
[tasks.noop]
cmd = "true"
TOML

# Create Makefile for comparison
cat > Makefile << 'MAKE'
noop:
	@true
MAKE

# Create Justfile for comparison (if just is available)
if command -v just &> /dev/null; then
    cat > justfile << 'JUST'
noop:
    @true
JUST
    HAS_JUST=1
else
    HAS_JUST=0
fi

# Create Taskfile.yml for comparison (if task is available)
if command -v task &> /dev/null; then
    cat > Taskfile.yml << 'TASK'
version: '3'
tasks:
  noop:
    cmds:
      - 'true'
TASK
    HAS_TASK=1
else
    HAS_TASK=0
fi

# Build comparison command list
CMDS=("$ZR run noop" "make noop")
if [ $HAS_JUST -eq 1 ]; then
    CMDS+=("just noop")
fi
if [ $HAS_TASK -eq 1 ]; then
    CMDS+=("task noop")
fi

# Run hyperfine benchmark
hyperfine --warmup 5 --min-runs 20 "${CMDS[@]}"

# ============================================
# Benchmark 2: Config Parsing (large config)
# ============================================
echo -e "\n${BLUE}[2/4] Config Parsing (100 tasks)${NC}"

# Generate large zr.toml
{
    echo "[workspace]"
    echo "members = []"
    echo ""
    for i in $(seq 1 100); do
        echo "[tasks.task_$i]"
        echo "cmd = \"echo task $i\""
        echo "deps = []"
        echo ""
    done
} > zr.toml

# Generate equivalent Makefile
{
    for i in $(seq 1 100); do
        echo "task_$i:"
        echo "	@echo task $i"
        echo ""
    done
} > Makefile

# Benchmark config validation (parsing only, no execution)
PARSE_CMDS=("$ZR validate" "make --print-data-base > /dev/null")
hyperfine --warmup 3 --min-runs 10 "${PARSE_CMDS[@]}"

# ============================================
# Benchmark 3: Parallel Execution
# ============================================
echo -e "\n${BLUE}[3/4] Parallel Execution (4 sleep tasks)${NC}"

cat > zr.toml << 'TOML'
[tasks.sleep1]
cmd = "sleep 0.1"

[tasks.sleep2]
cmd = "sleep 0.1"

[tasks.sleep3]
cmd = "sleep 0.1"

[tasks.sleep4]
cmd = "sleep 0.1"

[tasks.all]
deps = ["sleep1", "sleep2", "sleep3", "sleep4"]
cmd = "true"
TOML

cat > Makefile << 'MAKE'
all: sleep1 sleep2 sleep3 sleep4
	@true

sleep1:
	@sleep 0.1

sleep2:
	@sleep 0.1

sleep3:
	@sleep 0.1

sleep4:
	@sleep 0.1
MAKE

# zr runs deps in parallel by default
# Make runs serially by default
PARALLEL_CMDS=("$ZR run all" "make all" "make -j4 all")
hyperfine --warmup 2 --min-runs 5 "${PARALLEL_CMDS[@]}"

# ============================================
# Benchmark 4: Memory Usage
# ============================================
echo -e "\n${BLUE}[4/4] Memory Usage (RSS)${NC}"

# Simple task for memory measurement
cat > zr.toml << 'TOML'
[tasks.noop]
cmd = "true"
TOML

cat > Makefile << 'MAKE'
noop:
	@true
MAKE

if command -v /usr/bin/time &> /dev/null; then
    echo "Measuring peak RSS (resident set size)..."
    echo ""

    echo -e "${YELLOW}zr:${NC}"
    /usr/bin/time -l "$ZR" run noop 2>&1 | grep "maximum resident set size" || echo "N/A"

    echo -e "${YELLOW}make:${NC}"
    /usr/bin/time -l make noop 2>&1 | grep "maximum resident set size" || echo "N/A"

    if [ $HAS_JUST -eq 1 ]; then
        echo -e "${YELLOW}just:${NC}"
        /usr/bin/time -l just noop 2>&1 | grep "maximum resident set size" || echo "N/A"
    fi

    if [ $HAS_TASK -eq 1 ]; then
        echo -e "${YELLOW}task:${NC}"
        /usr/bin/time -l task noop 2>&1 | grep "maximum resident set size" || echo "N/A"
    fi
else
    echo -e "${YELLOW}Note: /usr/bin/time not available (macOS/BSD specific)${NC}"
    echo "Install GNU time for memory measurements on Linux"
fi

# ============================================
# Summary
# ============================================
echo -e "\n${BLUE}=== Benchmark Complete ===${NC}"
echo -e "${GREEN}Results saved to terminal output${NC}"
echo -e "${YELLOW}Tip: Run with \`script output.txt\` to save results to file${NC}\n"
