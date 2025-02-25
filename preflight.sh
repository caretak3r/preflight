#!/bin/bash

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
NC='\033[0m' # No Color

# Test registry array
declare -a TESTS

# Output formatting
print_result() {
    local status="$1"
    local message="$2"
    local test_name="$3"
    
    case $status in
        PASS)
            printf "%-40s [${GREEN}%s${NC}] %s\n" "$test_name" "$status" "$message"
            ;;
        FAIL)
            printf "%-40s [${RED}%s${NC}] %s\n" "$test_name" "$status" "$message"
            ;;
        WARN)
            printf "%-40s [${ORANGE}%s${NC}] %s\n" "$test_name" "$status" "$message"
            ;;
        *)
            printf "%-40s [%s] %s\n" "$test_name" "$status" "$message"
            ;;
    esac
}

# Test runner function
run_tests() {
    echo "Running preflight checks..."
    echo "========================================"
    
    for test in "${TESTS[@]}"; do
        # Run test and capture output
        local output
        output=$(eval "$test")
        local exit_code=$?
        
        # Parse output
        local status=$(echo "$output" | cut -d'|' -f1)
        local message=$(echo "$output" | cut -d'|' -f2-)
        
        print_result "$status" "$message" "$test"
    done
    
    echo "========================================"
}

# --------------------------------------------------
# Built-in Test Functions
# --------------------------------------------------

check_cpu_cores() {
    local required=2
    local cores=$(nproc)
    
    if [ "$cores" -ge "$required" ]; then
        echo "PASS|CPU cores ($cores) meet requirement ($required)"
    else
        echo "FAIL|Insufficient CPU cores ($cores < $required)"
    fi
}

check_disk_space() {
    local required=20 # GB
    local space=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')
    
    if [ "$space" -ge "$required" ]; then
        echo "PASS|Disk space (${space}GB) meets minimum (${required}GB)"
    elif [ "$space" -ge $((required/2)) ]; then
        echo "WARN|Low disk space (${space}GB) - minimum ${required}GB required"
    else
        echo "FAIL|Insufficient disk space (${space}GB < ${required}GB)"
    fi
}

check_kernel_version() {
    local required="5.4"
    local version=$(uname -r | cut -d'.' -f1-2)
    
    if awk 'BEGIN {exit !(ARGV[1] >= ARGV[2])}' "$version" "$required"; then
        echo "PASS|Kernel version ($version) meets minimum ($required)"
    else
        echo "WARN|Kernel version ($version) is below recommended ($required)"
    fi
}

check_memory() {
    local required=4000 # MB
    local memory=$(free -m | awk '/Mem:/ {print $2}')
    
    if [ "$memory" -ge "$required" ]; then
        echo "PASS|System memory (${memory}MB) meets minimum (${required}MB)"
    elif [ "$memory" -ge $((required/2)) ]; then
        echo "WARN|Low memory (${memory}MB) - minimum ${required}MB recommended"
    else
        echo "FAIL|Insufficient memory (${memory}MB < ${required}MB)"
    fi
}

check_swap() {
    local swap=$(free -m | awk '/Swap:/ {print $2}')
    if [ "$swap" -ge 1 ]; then
        echo "PASS|Swap configured (${swap}MB)"
    else
        echo "WARN|No swap space configured"
    fi
}

check_docker_runtime() {
    if command -v docker &> /dev/null; then
        echo "PASS|Docker is installed"
    else
        echo "FAIL|Docker not found"
    fi
}

# --------------------------------------------------
# Register Tests
# --------------------------------------------------
TESTS+=("check_cpu_cores")
TESTS+=("check_disk_space")
TESTS+=("check_kernel_version")
TESTS+=("check_memory")
TESTS+=("check_swap")
TESTS+=("check_docker_runtime")

# Run all tests
run_tests
