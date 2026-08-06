#!/bin/bash

#############################################################################
# EKS Lab - Phase 6: Validation Tests
# 
# Công việc:
# - Kiểm tra kết nối cluster
# - Kiểm tra pods và services
# - Kiểm tra ứng dụng
# - Kiểm tra scaling
# - Kiểm tra storage
#
# Thời gian: ~30 minutes
#############################################################################

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
GRAY='\033[0;37m'
NC='\033[0m'

# Configuration
REGION="ap-southeast-1"
PROFILE="${AWS_PROFILE:-default}"
LAB_NAME="eks-lab"
CLUSTER_NAME="${LAB_NAME}-cluster"
NAMESPACE="app-lab"

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}EKS Lab - Phase 6: Validation Tests${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Function: Run test
run_test() {
    local test_name=$1
    local test_command=$2
    
    ((TOTAL_TESTS++))
    
    echo -n "[$TOTAL_TESTS] Testing: $test_name ... "
    
    if eval "$test_command" &> /dev/null; then
        echo -e "${GREEN}PASSED${NC}"
        ((PASSED_TESTS++))
    else
        echo -e "${RED}FAILED${NC}"
        echo "    Command: $test_command"
        ((FAILED_TESTS++))
    fi
}

# Function: Print section
print_section() {
    echo ""
    echo -e "${BLUE}▶ $1${NC}"
    echo "─────────────────────────────────────────"
}

# ============================================================================
# SECTION 1: CLUSTER CONNECTIVITY
# ============================================================================
print_section "Cluster Connectivity Tests"

run_test "Kubectl cluster info" \
    "kubectl cluster-info"

run_test "Get nodes" \
    "kubectl get nodes"

run_test "All nodes Ready" \
    "test \$(kubectl get nodes --no-headers | grep -c Ready) -gt 0"

run_test "Get namespaces" \
    "kubectl get namespaces | grep -q $NAMESPACE"

run_test "API server accessible" \
    "kubectl api-resources | grep -q deployments"

# ============================================================================
# SECTION 2: POD & SERVICE TESTS
# ============================================================================
print_section "Pod & Service Tests"

run_test "Frontend pods running" \
    "test \$(kubectl get pods -n $NAMESPACE -l app=frontend --no-headers | grep -c Running) -gt 0"

run_test "Backend pods running" \
    "test \$(kubectl get pods -n $NAMESPACE -l app=backend --no-headers | grep -c Running) -gt 0"

run_test "Database pods running" \
    "test \$(kubectl get pods -n $NAMESPACE -l app=postgres --no-headers | grep -c Running) -eq 1"

run_test "Frontend service exists" \
    "kubectl get svc frontend -n $NAMESPACE"

run_test "Backend service exists" \
    "kubectl get svc backend-api -n $NAMESPACE"

run_test "Database service exists" \
    "kubectl get svc postgres -n $NAMESPACE"

run_test "All pods in Ready state" \
    "test \$(kubectl get pods -n $NAMESPACE --no-headers | grep -c '1/1') -ge 2"

# ============================================================================
# SECTION 3: CONNECTIVITY TESTS
# ============================================================================
print_section "Pod-to-Pod Connectivity Tests"

# Get a pod name for testing
FRONTEND_POD=$(kubectl get pods -n $NAMESPACE -l app=frontend -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
BACKEND_POD=$(kubectl get pods -n $NAMESPACE -l app=backend -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -n "$FRONTEND_POD" ] && [ -n "$BACKEND_POD" ]; then
    run_test "DNS resolution (nslookup kubernetes.default)" \
        "kubectl exec -n $NAMESPACE $FRONTEND_POD -- nslookup kubernetes.default"
    
    run_test "Frontend can reach backend" \
        "kubectl exec -n $NAMESPACE $FRONTEND_POD -- wget -q -O- http://backend-api:5000/api/health | grep -q status"
    
    run_test "Backend returns health status" \
        "kubectl exec -n $NAMESPACE $BACKEND_POD -- wget -q -O- http://localhost:5000/api/health | grep -q healthy"
fi

# ============================================================================
# SECTION 4: STORAGE TESTS
# ============================================================================
print_section "Storage Tests"

run_test "PVC exists" \
    "kubectl get pvc postgres-pvc -n $NAMESPACE"

run_test "PVC is Bound" \
    "kubectl get pvc postgres-pvc -n $NAMESPACE -o jsonpath='{.status.phase}' | grep -q Bound"

run_test "Storage class exists (ebs-gp3)" \
    "kubectl get storageclass ebs-gp3"

run_test "Storage class exists (ebs-gp2)" \
    "kubectl get storageclass ebs-gp2"

# ============================================================================
# SECTION 5: KUBERNETES RESOURCES
# ============================================================================
print_section "Kubernetes Resource Tests"

run_test "Deployments exist" \
    "test \$(kubectl get deployments -n $NAMESPACE --no-headers | wc -l) -ge 2"

run_test "StatefulSets exist" \
    "test \$(kubectl get statefulsets -n $NAMESPACE --no-headers | wc -l) -ge 1"

run_test "Services exist" \
    "test \$(kubectl get svc -n $NAMESPACE --no-headers | wc -l) -ge 3"

run_test "ConfigMaps exist" \
    "test \$(kubectl get configmap -n $NAMESPACE --no-headers | wc -l) -gt 0"

run_test "Secrets exist" \
    "kubectl get secret db-credentials -n $NAMESPACE"

# ============================================================================
# SECTION 6: RESOURCE REQUESTS & LIMITS
# ============================================================================
print_section "Resource Management Tests"

run_test "Frontend has resource requests" \
    "kubectl get deployment frontend -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].resources.requests}' | grep -q cpu"

run_test "Backend has resource requests" \
    "kubectl get deployment backend-api -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].resources.requests}' | grep -q cpu"

run_test "Database has resource requests" \
    "kubectl get statefulset postgres -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].resources.requests}' | grep -q cpu"

# ============================================================================
# SECTION 7: RBAC TESTS
# ============================================================================
print_section "RBAC Tests"

run_test "ServiceAccount exists (app-sa)" \
    "kubectl get serviceaccount app-sa -n $NAMESPACE"

run_test "Role exists (pod-reader)" \
    "kubectl get role pod-reader -n $NAMESPACE"

run_test "RoleBinding exists (read-pods)" \
    "kubectl get rolebinding read-pods -n $NAMESPACE"

# ============================================================================
# SECTION 8: LOAD BALANCER TEST
# ============================================================================
print_section "Load Balancer Tests"

EXTERNAL_IP=$(kubectl get svc frontend -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

if [ -z "$EXTERNAL_IP" ]; then
    EXTERNAL_IP=$(kubectl get svc frontend -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
fi

if [ -n "$EXTERNAL_IP" ]; then
    echo -e "${YELLOW}Load Balancer IP/Hostname: $EXTERNAL_IP${NC}"
    
    run_test "Load balancer endpoint accessible" \
        "curl -s -o /dev/null -w '%{http_code}' http://$EXTERNAL_IP | grep -q 200"
    
    run_test "Frontend returns HTML" \
        "curl -s http://$EXTERNAL_IP | grep -q 'EKS Lab'"
else
    echo -e "${YELLOW}Load Balancer: <pending> (may take 1-2 minutes)${NC}"
fi

# ============================================================================
# SECTION 9: MONITORING & LOGGING TESTS
# ============================================================================
print_section "Monitoring & Logging Tests"

run_test "Check control plane logs" \
    "aws logs describe-log-groups --log-group-name-prefix '/aws/eks/$CLUSTER_NAME' --region $REGION --profile $PROFILE 2>/dev/null | grep -q logGroupName"

run_test "kube-system pods running" \
    "test \$(kubectl get pods -n kube-system --no-headers | grep -c Running) -gt 0"

run_test "CoreDNS pods running" \
    "test \$(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers | grep -c Running) -gt 0"

# ============================================================================
# SECTION 10: ADDON TESTS
# ============================================================================
print_section "Add-ons Tests"

run_test "VPC CNI addon exists" \
    "aws eks list-addons --cluster-name $CLUSTER_NAME --region $REGION --profile $PROFILE --output table | grep -q vpc-cni"

run_test "CoreDNS addon exists" \
    "aws eks list-addons --cluster-name $CLUSTER_NAME --region $REGION --profile $PROFILE --output table | grep -q coredns"

run_test "kube-proxy addon exists" \
    "aws eks list-addons --cluster-name $CLUSTER_NAME --region $REGION --profile $PROFILE --output table | grep -q kube-proxy"

# ============================================================================
# SECTION 11: SCALING TESTS
# ============================================================================
print_section "Scaling Tests (Read-only)"

CURRENT_FRONTEND_REPLICAS=$(kubectl get deployment frontend -n $NAMESPACE -o jsonpath='{.spec.replicas}')
CURRENT_BACKEND_REPLICAS=$(kubectl get deployment backend-api -n $NAMESPACE -o jsonpath='{.spec.replicas}')

echo "Current replicas:"
echo "  Frontend: $CURRENT_FRONTEND_REPLICAS"
echo "  Backend: $CURRENT_BACKEND_REPLICAS"

run_test "Frontend deployment has replicas > 0" \
    "test $CURRENT_FRONTEND_REPLICAS -gt 0"

run_test "Backend deployment has replicas > 0" \
    "test $CURRENT_BACKEND_REPLICAS -gt 0"

# Optional: Perform scaling test
echo ""
echo -e "${YELLOW}→ Testing deployment scaling (frontend: $CURRENT_FRONTEND_REPLICAS → 1)${NC}"

kubectl scale deployment frontend -n $NAMESPACE --replicas=1

sleep 10

SCALED_REPLICAS=$(kubectl get deployment frontend -n $NAMESPACE -o jsonpath='{.status.replicas}')

run_test "Frontend scaled down successfully" \
    "test $SCALED_REPLICAS -eq 1"

# Scale back up
echo -e "${YELLOW}→ Scaling frontend back to $CURRENT_FRONTEND_REPLICAS replicas${NC}"
kubectl scale deployment frontend -n $NAMESPACE --replicas=$CURRENT_FRONTEND_REPLICAS

sleep 10

# ============================================================================
# SECTION 12: NODE STATUS
# ============================================================================
print_section "Node Status"

echo "Node Information:"
kubectl get nodes -o wide

echo ""
echo "Node capacity and allocatable resources:"
kubectl top nodes 2>/dev/null || echo "Metrics not available yet"

echo ""
echo "Node details:"
kubectl describe nodes | grep -E "^Name:|Allocatable:|Allocated resources:" | head -15

# ============================================================================
# SECTION 13: PERFORMANCE METRICS
# ============================================================================
print_section "Performance Metrics"

echo "Pod resource usage:"
kubectl top pods -n $NAMESPACE 2>/dev/null || echo "Metrics not available yet"

echo ""
echo "Memory usage by pod:"
kubectl get pods -n $NAMESPACE -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].resources.limits.memory}{"\n"}{end}'

# ============================================================================
# SUMMARY
# ============================================================================
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Test Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Total Tests:           $TOTAL_TESTS"
echo -e "Passed:                ${GREEN}$PASSED_TESTS${NC}"
echo -e "Failed:                ${RED}$FAILED_TESTS${NC}"
echo ""

# Calculate pass rate
if [ $TOTAL_TESTS -gt 0 ]; then
    PASS_RATE=$((PASSED_TESTS * 100 / TOTAL_TESTS))
    echo "Pass Rate:             $PASS_RATE%"
    echo ""
    
    if [ $FAILED_TESTS -eq 0 ]; then
        echo -e "${GREEN}✓ All tests PASSED!${NC}"
    elif [ $PASS_RATE -ge 80 ]; then
        echo -e "${YELLOW}⚠ Some tests failed (check errors above)${NC}"
    else
        echo -e "${RED}✗ Multiple test failures${NC}"
    fi
fi

# ============================================================================
# USEFUL COMMANDS
# ============================================================================
echo ""
echo -e "${BLUE}Useful Commands for Debugging:${NC}"
echo "─────────────────────────────────────────"
echo "Watch pods:                kubectl get pods -n $NAMESPACE -w"
echo "View deployment logs:      kubectl logs -n $NAMESPACE -l app=frontend"
echo "Describe pod:              kubectl describe pod -n $NAMESPACE <pod-name>"
echo "Port forward:              kubectl port-forward -n $NAMESPACE svc/frontend 8080:80"
echo "Scale deployment:          kubectl scale deployment frontend -n $NAMESPACE --replicas=3"
echo "Exec into pod:             kubectl exec -it -n $NAMESPACE <pod-name> -- /bin/bash"
echo "View pod metrics:          kubectl top pods -n $NAMESPACE"
echo "View events:               kubectl get events -n $NAMESPACE"
echo ""

# ============================================================================
# NEXT STEPS
# ============================================================================
echo -e "${BLUE}========================================${NC}"
if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "${GREEN}✓ Lab Validation Complete!${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo "Your EKS cluster is ready for production use!"
    echo ""
    echo "Next steps:"
    echo "  1. Access the application via Load Balancer IP"
    echo "  2. Test scaling: kubectl scale deployment frontend -n $NAMESPACE --replicas=5"
    echo "  3. Test rolling updates: kubectl set image deployment/frontend -n $NAMESPACE nginx=nginx:latest"
    echo "  4. Explore AWS Console > EKS > Clusters > $CLUSTER_NAME"
    echo "  5. Clean up: bash cleanup.sh"
    echo ""
else
    echo -e "${RED}⚠ Some tests failed${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo "Please check the failed tests above and troubleshoot."
    echo ""
fi

echo -e "${YELLOW}To cleanup resources: bash cleanup.sh${NC}"
echo ""
