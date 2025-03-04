#!/bin/bash

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
NC='\033[0m' # No Color

# Test registry array
declare -a TESTS

# Configuration - Add any missing tools here
REQUIRED_TOOLS=("kubectl" "jq" "helm" "curl")

# Configuration
MIN_K8S_VERSION="1.2"
SUPPORTED_DISTROS=("aks" "eks")
REQUIRED_ENDPOINTS=(
  "https://kubernetes.default.svc"
  "https://registry-1.docker.io"
  "https://quay.io"
)

# EC2 instance types that meet minimum requirements
# Format: instance_type:min_cpu:min_memory_gb
MINIMUM_EC2_INSTANCES=(
  "t3.xlarge:4:16"
  "m5.large:2:8"
  "c5.large:2:4"
  "r5.large:2:16"
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

check_nodes_with_taints() {
    if ! command -v kubectl &> /dev/null; then
        echo "FAIL|kubectl not found"
        return
    fi
    
    local nodes_with_taints=$(kubectl get nodes -o json | jq '[.items[] | select(.spec.taints != null and .spec.taints | length > 0)] | length')
    
    if [ "$nodes_with_taints" -ge 1 ]; then
        echo "PASS|Found $nodes_with_taints node(s) with taints"
    else
        echo "WARN|No nodes with taints found - tokenization may not work properly"
    fi
}

check_aws_instance_types() {
    if ! command -v kubectl &> /dev/null; then
        echo "FAIL|kubectl not found"
        return
    }
    
    # Check if we're running on EKS
    if ! kubectl get nodes -o yaml | grep -q 'eks.amazonaws.com/nodegroup'; then
        echo "INFO|Not running on EKS, skipping EC2 instance check"
        return
    }
    
    local inadequate_nodes=()
    local node_count=0
    
    while read -r node_name instance_type; do
        ((node_count++))
        local meets_requirements=false
        
        for spec in "${MINIMUM_EC2_INSTANCES[@]}"; do
            IFS=':' read -r acceptable_type min_cpu min_mem <<< "$spec"
            if [[ "$instance_type" == "$acceptable_type" || "$instance_type" > "$acceptable_type" ]]; then
                meets_requirements=true
                break
            fi
        done
        
        if [ "$meets_requirements" = false ]; then
            inadequate_nodes+=("$node_name ($instance_type)")
        fi
    done < <(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.labels.beta\.kubernetes\.io/instance-type}{"\n"}{end}')
    
    if [ ${#inadequate_nodes[@]} -eq 0 ]; then
        echo "PASS|All $node_count EC2 instances meet minimum specifications"
    else
        echo "FAIL|Found ${#inadequate_nodes[@]} nodes with inadequate EC2 instance types: ${inadequate_nodes[*]}"
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

check_helm_repo_access() {
    if ! command -v helm &> /dev/null; then
        echo "FAIL|helm not found"
        return
    }
    
    # Add repo temporarily
    if ! helm repo add test-repo "$TEST_HELM_REPO" >/dev/null 2>&1; then
        echo "FAIL|Unable to add helm repository: $TEST_HELM_REPO"
        return
    fi
    
    # Update repo
    if ! helm repo update >/dev/null 2>&1; then
        helm repo remove test-repo >/dev/null 2>&1
        echo "FAIL|Unable to update helm repository"
        return
    }
    
    # Try to fetch chart info
    if ! helm search repo test-repo/$TEST_HELM_CHART >/dev/null 2>&1; then
        helm repo remove test-repo >/dev/null 2>&1
        echo "FAIL|Unable to find chart '$TEST_HELM_CHART' in repository"
        return
    }
    
    # Clean up
    helm repo remove test-repo >/dev/null 2>&1
    
    echo "PASS|Successfully accessed and searched the helm repository ($TEST_HELM_REPO)"
}

check_memlock_ulimit() {
    local qualified_nodes=0
    local total_nodes=0
    
    # Method 1: Check for pre-configured labels/annotations
    local label_nodes=$(kubectl get nodes -o json | 
        jq -r '.items[] | select(.metadata.labels.memlock_unlimited == "true" or (.metadata.annotations.memlock // "0" | tonumber >= 3000000)) | .metadata.name' | wc -l)
    
    # Method 2: Check kubelet configuration (if accessible)
    local config_nodes=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}' | xargs -n1 -I{} sh -c \
        'kubectl get --raw /api/v1/nodes/{}/proxy/configz 2>/dev/null | grep -q "memlock=unlimited" && echo {}' | wc -l)

    # Combine results
    qualified_nodes=$((label_nodes + config_nodes))
    total_nodes=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)

    if [ "$qualified_nodes" -ge 1 ]; then
        echo "PASS|Found $qualified_nodes node(s) with memlock ≥3GB/unlimited (via labels/config)"
    else
        echo "WARN|Memlock status unknown - requires manual verification (nodes: $total_nodes)"
        echo "      Check either:"
        echo "      a) Node labels/annotations: memlock_unlimited=true or memlock≥3000000"
        echo "      b) Kubelet config: --memory-lock=true or equivalent"
    fi
}

check_chicken_taint() {
    if ! command -v kubectl &>/dev/null; then
        echo "FAIL|kubectl not found"
        return 1
    fi

    local target_taint="chicken.com/tier=chicken:NoExecute"
    local tainted_nodes=$(kubectl get nodes -o json | \
        jq -r --arg taint "$target_taint" '
        .items[] | 
        select(.spec.taints != null) |
        .metadata.name as $name |
        .spec.taints[] | 
        select(.key == "c1s.com/tier" and 
               .value == "chicken" and 
               .effect == "NoExecute") |
        $name' | uniq | wc -l)

    if [ "$tainted_nodes" -ge 1 ]; then
        echo "PASS|Found $tainted_nodes node(s) with required taint: $target_taint"
    else
        echo "FAIL|No nodes found with required taint: $target_taint"
    fi
}

check_replicated_chart_pull() {
    if ! command -v helm &>/dev/null; then
        echo "FAIL|helm not found"
        return 1
    fi

    local chart_url="oci://registry.replicated.com/preflight"
    local version="0.1.5"
    local tmp_dir=$(mktemp -d)
    local output_log="$tmp_dir/pull.log"
    local success=0

    # Check Helm version for OCI support
    local helm_version=$(helm version --short | cut -d. -f1-3 | tr -d 'v')
    if [[ $(printf "%s\n" "3.8.0" "$helm_version" | sort -V | head -n1) != "3.8.0" ]]; then
        echo "FAIL|Helm 3.8.0+ required for OCI support (found $helm_version)"
        rm -rf "$tmp_dir"
        return 1
    fi

    # Attempt chart pull with cleanup
    (
        cd "$tmp_dir"
        helm pull "$chart_url" --version "$version" --untar >"$output_log" 2>&1
    )
    
    # Verify results
    if [ $? -eq 0 ] && [ -d "$tmp_dir/preflight" ] && [ -f "$tmp_dir/preflight/Chart.yaml" ]; then
        echo "PASS|Successfully pulled chart: $chart_url (v$version)"
        success=1
    else
        echo "FAIL|Failed to pull chart. Error: $(grep -i error "$output_log" | head -n1 | cut -c1-80)"
    fi

    # Cleanup
    rm -rf "$tmp_dir"
    return $((1 - success))
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
TESTS+=("check_nodes_with_taints")
TESTS+=("check_aws_instance_types")
TESTS+=("check_endpoint_reachability")
TESTS+=("check_helm_releases")
TESTS+=("check_helm_repo_access")
TESTS+=("check_memlock_ulimit")
TESTS+=("check_chicken_taint")
TESTS+=("check_replicated_chart_pull")

# Run all tests
run_tests
