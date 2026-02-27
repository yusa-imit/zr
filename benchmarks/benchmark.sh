#!/usr/bin/env bash
# Benchmark zr against Make, Just, and Task
set -e

ITERATIONS=10
ZR_BIN="${ZR_BIN:-./zig-out/bin/zr}"

echo "=== zr Performance Benchmark ==="
echo "Date: $(date)"
echo "Iterations: $ITERATIONS"
echo ""

# Create test workspace
BENCH_DIR=$(mktemp -d)
trap "rm -rf $BENCH_DIR" EXIT
cd "$BENCH_DIR"

# Setup configs
cat > Makefile << 'EOF'
.PHONY: noop
noop:
	@true
EOF

cat > zr.toml << 'EOF'
[tasks.noop]
cmd = "true"
EOF

# Benchmark function
bench() {
    local name=$1
    shift
    local total=0
    
    for i in $(seq 1 $ITERATIONS); do
        start=$(date +%s%N)
        "$@" > /dev/null 2>&1
        end=$(date +%s%N)
        elapsed=$((end - start))
        total=$((total + elapsed))
    done
    
    avg=$((total / ITERATIONS / 1000000)) # Convert to ms
    echo "$name: ${avg}ms"
}

echo "Running benchmarks..."
bench "zr  " "$ZR_BIN" run noop
bench "Make" make noop

echo ""
echo "Binary sizes:"
du -h "$ZR_BIN" | awk '{print "zr:  ", $1}'
du -h /usr/bin/make | awk '{print "Make:", $1}'
