#!/bin/bash

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
NC='\033[0m' # No Color

# Test registry array
declare -a TESTS

# Configuration - Add any missing tools here
REQUIRED_TOOLS=("kubectl" "jq" "helm")

# Configuration
MIN_K8S_VERSION="1.24"
SUPPORTED_DISTROS=("aks" "eks")
REQUIRED_ENDPOINTS=(
  "https://kubernetes.default.svc"
  "https://registry-1.docker.io"
  "https://quay.io"
)

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
check_dependencies() {
    local missing=()
    for tool in "${REQUIRED_TOOLS[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing+=("$tool")
        fi
    done

    if [ ${#missing[@]} -eq 0 ]; then
        echo "PASS|All required tools are installed"
    else
        echo "FAIL|Missing required tools: ${missing[*]}"
    fi
}

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

check_k8s_version() {
    if ! command -v kubectl &> /dev/null; then
        echo "FAIL|kubectl not found"
        return
    fi

    local server_version=$(kubectl version --short 2>/dev/null | grep "Server Version" | awk '{print $3}')
    if [ -z "$server_version" ]; then
        echo "FAIL|Could not connect to cluster"
        return
    fi

    local major_minor=$(echo $server_version | grep -Po 'v?\K\d+\.\d+')
    if [ "$(printf '%s\n' "$MIN_K8S_VERSION" "$major_minor" | sort -V | head -n1)" = "$MIN_K8S_VERSION" ]; then
        echo "PASS|Kubernetes version ($server_version) meets minimum (v$MIN_K8S_VERSION)"
    else
        echo "FAIL|Unsupported Kubernetes version ($server_version < v$MIN_K8S_VERSION)"
    fi
}

check_managed_provider() {
    local provider=""
    
    # Check node labels for cloud provider identifiers
    if kubectl get nodes -o yaml | grep -q 'eks.amazonaws.com/nodegroup'; then
        provider="eks"
    elif kubectl get nodes -o yaml | grep -q 'kubernetes.azure.com/role'; then
        provider="aks"
    fi

    if [ -n "$provider" ]; then
        echo "PASS|Cluster is running on managed provider: ${provider^^}"
    else
        echo "WARN|Cluster is not running on a managed provider"
    fi
}

check_supported_distribution() {
    local distro_found=""
    
    # Check cluster information
    local cluster_info=$(kubectl cluster-info dump)
    for distro in "${SUPPORTED_DISTROS[@]}"; do
        if [[ "$cluster_info" =~ $distro ]]; then
            distro_found="$distro"
            break
        fi
    done

    if [ -n "$distro_found" ]; then
        echo "PASS|Cluster is running supported distribution: ${distro_found^^}"
    else
        echo "WARN|Cluster is not running a supported distribution"
    fi
}

check_node_count() {
    local node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
    
    if [ "$node_count" -ge 3 ]; then
        echo "PASS|Cluster has $node_count nodes"
    else
        echo "FAIL|Insufficient nodes ($node_count < 3)"
    fi
}

check_node_resources() {
    local qualified_nodes=0
    local nodes=$(kubectl get nodes -o json)
    
    while read -r node; do
        local cpus=$(jq -r '.status.allocatable.cpu' <<< "$node" | awk '{print int($1)}')
        local memory=$(jq -r '.status.allocatable.memory' <<< "$node" | sed 's/[^0-9]*//g')
        memory=$((memory/1024/1024)) # Convert to GB
        
        if [ "$cpus" -ge 8 ] && [ "$memory" -ge 16 ]; then
            ((qualified_nodes++))
        fi
    done <<< "$(jq -c '.items[]' <<< "$nodes")"

    if [ "$qualified_nodes" -ge 1 ]; then
        echo "PASS|Found $qualified_nodes node(s) with ≥8 CPUs and ≥16GB RAM"
    else
        echo "FAIL|No nodes meet resource requirements (8 CPU, 16GB RAM)"
    fi
}

check_endpoint_reachability() {
    local failed=()
    
    for endpoint in "${REQUIRED_ENDPOINTS[@]}"; do
        if ! curl --max-time 5 -ksSf "$endpoint" >/dev/null 2>&1; then
            failed+=("$endpoint")
        fi
    done

    if [ ${#failed[@]} -eq 0 ]; then
        echo "PASS|All required endpoints reachable"
    else
        echo "FAIL|Unreachable endpoints: ${failed[*]}"
    fi
}

check_helm_releases() {
    if ! command -v helm &> /dev/null; then
        echo "WARN|helm not installed"
        return
    fi

    local releases=$(helm list -A --output json 2>/dev/null)
    if [ -z "$releases" ]; then
        echo "INFO|No helm releases found"
        return
    fi

    local count=$(jq length <<< "$releases")
    echo "PASS|Found $count helm releases:"
    
    # Formatting output
    printf "\n%-40s %-25s %-15s %-20s\n" "NAME" "NAMESPACE" "CHART" "VERSION"
    jq -r '.[] | "\(.name)|\(.namespace)|\(.chart)|\(.app_version)"' <<< "$releases" | 
    while IFS='|' read -r name namespace chart version; do
        printf "%-40s %-25s %-15s %-20s\n" "$name" "$namespace" "$chart" "$version"
    done
    
    # Return pass status with count
    echo "PASS|Displayed $count helm releases"
}

# --------------------------------------------------
# Register Tests
# --------------------------------------------------
TESTS=("check_dependencies")
TESTS+=("check_cpu_cores")
TESTS+=("check_disk_space")
TESTS+=("check_kernel_version")
TESTS+=("check_memory")
TESTS+=("check_swap")
TESTS+=("check_docker_runtime")
TESTS+=("check_k8s_version")
TESTS+=("check_managed_provider")
TESTS+=("check_supported_distribution")
TESTS+=("check_node_count")
TESTS+=("check_node_resources")
TESTS+=("check_endpoint_reachability")
TESTS+=("check_helm_releases")

# Run all tests
run_tests
