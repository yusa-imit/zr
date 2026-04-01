#!/usr/bin/env bash
# Test coverage analyzer for zr
# Usage: scripts/test-coverage.sh [--verbose]

VERBOSE=0
[[ "${1:-}" == "--verbose" ]] && VERBOSE=1

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; NC='\033[0m'

echo -e "${BLUE}=== zr Test Coverage Report ===${NC}\n"

# Count source files and tests
total=0; tested=0; unit_tests=0
untested=()

for file in src/**/*.zig; do
    [[ ! -f "$file" ]] && continue
    ((total++))
    count=$(grep "^test " "$file" 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$count" -gt 0 ]]; then
        ((tested++)); ((unit_tests += count))
        [[ $VERBOSE -eq 1 ]] && echo -e "${GREEN}✓${NC} $file ($count tests)"
    else
        untested+=("$file")
        [[ $VERBOSE -eq 1 ]] && echo -e "${RED}✗${NC} $file"
    fi
done

# Count integration tests
int_files=0; int_tests=0
for file in tests/*_test.zig; do
    [[ ! -f "$file" ]] && continue
    ((int_files++))
    count=$(grep "^test " "$file" 2>/dev/null | wc -l | tr -d ' ')
    ((int_tests += count))
done

# Count fuzz/perf tests
fuzz=$(ls tests/fuzz_*.zig 2>/dev/null | wc -l | tr -d ' ')
perf=$(ls tests/perf_*.zig 2>/dev/null | wc -l | tr -d ' ')

# Calculate coverage
pct=$(awk "BEGIN {printf \"%.1f\", ($tested / $total) * 100}")

echo -e "\n${BLUE}--- Summary ---${NC}"
echo -e "Total source files:        $total"
echo -e "${GREEN}Files with unit tests:     $tested (${pct}%)${NC}"
echo -e "${RED}Files without tests:       $((total - tested))${NC}"
echo -e "Total unit tests:          $unit_tests"
echo ""
echo -e "Integration test files:    $int_files"
echo -e "Integration tests:         $int_tests"
echo -e "Fuzz test files:           $fuzz"
echo -e "Performance test files:    $perf"

# Show untested files
if [[ $VERBOSE -eq 0 && ${#untested[@]} -gt 0 ]]; then
    echo -e "\n${YELLOW}--- Files Without Tests ---${NC}"
    for file in "${untested[@]}"; do echo -e "${RED}✗${NC} $file"; done
fi

# Threshold check
if (( $(echo "$pct >= 80.0" | bc -l) )); then
    echo -e "\n${GREEN}✓ Test coverage (${pct}%) meets 80% threshold${NC}"
else
    echo -e "\n${YELLOW}⚠ Warning: Test coverage (${pct}%) is below 80% threshold${NC}"
    exit 1
fi
