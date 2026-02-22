#!/bin/bash
set -e

# ==========================================
# ProtoMQ Main Integration Test Runner
# ==========================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}==========================================${NC}"
echo -e "${YELLOW}       ProtoMQ Test Suite Runner          ${NC}"
echo -e "${YELLOW}==========================================${NC}"

# Ensure we are in the project root
if [ ! -d "tests/cases" ]; then
    echo -e "${RED}Error: Must be run from the project root.${NC}"
    exit 1
fi

echo -e "\n${YELLOW}[1/2] Building Project...${NC}"
if zig build; then
    echo -e "${GREEN}✓ Build Successful${NC}"
else
    echo -e "${RED}✗ Build Failed${NC}"
    exit 1
fi

echo -e "\n${YELLOW}[2/2] Running Test Cases...${NC}"

# Array of test scripts to run in order
declare -a TESTS=(
    "tests/cases/cli_test.sh"
    "tests/cases/integration_test.sh"
    "tests/cases/run_pubsub_test.sh"
    "tests/cases/discovery_test.sh"
)

PASSED=0
FAILED=0

for test_script in "${TESTS[@]}"; do
    echo -e "\n--------------------------------------------"
    echo -e "▶ Running: ${test_script}"
    echo -e "--------------------------------------------\n"
    
    # Run the test
    if chmod +x "$test_script" && "$test_script"; then
        echo -e "\n${GREEN}✓ Passed: ${test_script}${NC}"
        PASSED=$((PASSED+1))
    else
        echo -e "\n${RED}✗ Failed: ${test_script}${NC}"
        FAILED=$((FAILED+1))
    fi
done

echo -e "\n${YELLOW}==========================================${NC}"
echo -e "${YELLOW}              TEST SUMMARY                ${NC}"
echo -e "${YELLOW}==========================================${NC}"

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}🎉 ALL $PASSED TESTS PASSED SUCCESSFULLY!${NC}"
    exit 0
else
    echo -e "${RED}💥 $FAILED TEST(S) FAILED (Out of $((PASSED+FAILED)) total)${NC}"
    exit 1
fi
