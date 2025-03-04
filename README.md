# preflight 

A simple shell script to modularly add tests to run against a kubernetes cluster. 

```
chmod +x preflight.sh
./preflight.sh
```

To add a new test, add a new function at the bottom of the "Built-in Test Functions" section:

```
check_your_test() {
    # Test logic here
    echo "STATUS|Your message"
}
```

Register it in the TESTS array:

`TESTS+=("check_your_test")`

---

## Overview
This script performs comprehensive preflight checks for Kubernetes environments. Below is a breakdown of each check and its purpose:

## Preflight Checks Reference

| Check Name                     | Description                                                                 | What It Looks For                                                                 |
|--------------------------------|-----------------------------------------------------------------------------|-----------------------------------------------------------------------------------|
| **check_dependencies**         | Verifies required CLI tools are installed                                   | Checks for presence of `kubectl`, `jq`, `helm`, and `curl` in system PATH         |
| **check_cpu_cores**            | Validates minimum CPU capacity                                              | At least 2 CPU cores available on the host system                                 |
| **check_disk_space**           | Ensures adequate storage space                                              | Minimum 20GB available disk space on root partition (`/`)                         |
| **check_kernel_version**       | Checks Linux kernel meets minimum version                                   | Kernel version ≥5.4 (checks via `uname -r`)                                       |
| **check_memory**               | Verifies system memory meets requirements                                   | Minimum 4GB (4096MB) of physical RAM available                                    |
| **check_swap**                 | Checks for swap space configuration                                        | Any configured swap space (warns if none found)                                   |
| **check_docker_runtime**       | Confirms Docker installation                                               | Presence of `docker` command in PATH                                              |
| **check_k8s_version**          | Validates Kubernetes cluster version                                       | Cluster version ≥1.2 (checks server version via `kubectl version`)                |
| **check_managed_provider**     | Identifies cloud-managed Kubernetes provider                               | Looks for EKS (AWS) or AKS (Azure) specific node labels                           |
| **check_supported_distribution** | Verifies cluster distribution compatibility                            | Checks if cluster is running on AKS or EKS                                        |
| **check_node_count**           | Ensures minimum cluster size                                               | At least 3 worker nodes in the cluster                                            |
| **check_node_resources**       | Validates node resource capacity                                           | At least 1 node with ≥8 CPUs and ≥16GB RAM (checks allocatable resources)         |
| **check_nodes_with_taints**    | Checks for tainted nodes                                                   | Presence of nodes with taints (warns if none found)                               |
| **check_aws_instance_types**   | Validates EC2 instance types (EKS only)                                    | Minimum instance specs (e.g., t3.xlarge, m5.large) when running on AWS EKS        |
| **check_endpoint_reachability** | Tests network connectivity to critical endpoints                      | Accessibility of Kubernetes API, Docker Hub, and Quay.io                          |
| **check_helm_releases**        | Audits installed Helm releases                                             | Lists all Helm releases across namespaces                                         |
| **check_helm_repo_access**     | Validates Helm repository access                                           | Ability to add/update repos and search charts (uses test repo)                    |

## Key Thresholds
- **CPU**: Minimum 2 cores (4 recommended)
- **Memory**: Minimum 4GB (8GB+ recommended)
- **Disk**: Minimum 20GB free space
- **Kubernetes**: Version 1.2 or newer
- **Nodes**: Minimum 3 nodes (1+ with 8CPU/16GB)

## Special Notes
1. **Cloud-Specific Checks**: AWS instance type validation only runs on EKS clusters
2. **Helm Operations**: Repository check uses temporary test repos to avoid side effects
3. **Network Checks**: Validates both internal (k8s API server) and external (container registries) connectivity
4. **Resource Metrics**: Uses _allocatable_ resources rather than total node capacity
5. **Version Checks**: Kernel validation ignores patch versions (e.g., 5.4.0-100 = 5.4)

## Interpretation Guide
| Status    | Meaning                                                                 |
|-----------|-------------------------------------------------------------------------|
| **PASS**  | Requirement fully met                                                   |
| **FAIL**  | Critical requirement not met - blocks deployment                        |
| **WARN**  | Suboptimal configuration - proceed with caution                        |
| **INFO**  | Informational message (no action required)                             |

This document serves as a quick reference for understanding the preflight validation process and its requirements.
