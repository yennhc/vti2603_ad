#!/bin/bash

#############################################################################
# EKS Lab - Phase 3: Add Node Groups & Fargate
# 
# Công việc:
# - Tạo Managed Node Group
# - Tạo Fargate Profile
# - Verify nodes ready
#
# Thời gian: ~15 minutes (actual creation: 5-10 min)
#############################################################################

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
REGION="ap-southeast-1"
PROFILE="${AWS_PROFILE:-default}"
LAB_NAME="eks-lab"
CLUSTER_NAME="${LAB_NAME}-cluster"

# Node Group Configuration
NODE_GROUP_NAME="primary-nodes"
INSTANCE_TYPES="t3.medium"
DESIRED_SIZE=3
MIN_SIZE=2
MAX_SIZE=5
DISK_SIZE=20

# Load resources from Phase 1 & 2
if [ ! -f "./eks-lab-resources.txt" ]; then
    echo -e "${RED}Error: eks-lab-resources.txt not found!${NC}"
    exit 1
fi

source ./eks-lab-resources.txt

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}EKS Lab - Phase 3: Add Node Groups${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Function: Print step
print_step() {
    echo -e "${YELLOW}→ $1${NC}"
}

# Function: Print success
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# Function: Print error
print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# ============================================================================
# STEP 1: Verify cluster exists
# ============================================================================
print_step "Verifying cluster exists..."

CLUSTER_STATUS=$(aws eks describe-cluster \
    --name $CLUSTER_NAME \
    --region $REGION \
    --profile $PROFILE \
    --query 'cluster.status' \
    --output text 2>/dev/null || echo "FAILED")

if [ "$CLUSTER_STATUS" != "ACTIVE" ]; then
    print_error "Cluster not ACTIVE. Status: $CLUSTER_STATUS"
    exit 1
fi

print_success "Cluster is ACTIVE"

# ============================================================================
# STEP 2: Create Managed Node Group
# ============================================================================
print_step "Creating Managed Node Group: $NODE_GROUP_NAME..."
print_step "Instance Type: $INSTANCE_TYPES (Count: $MIN_SIZE-$DESIRED_SIZE-$MAX_SIZE)"

aws eks create-nodegroup \
    --cluster-name $CLUSTER_NAME \
    --nodegroup-name $NODE_GROUP_NAME \
    --scaling-config \
        minSize=$MIN_SIZE,\
        maxSize=$MAX_SIZE,\
        desiredSize=$DESIRED_SIZE \
    --instance-types $INSTANCE_TYPES \
    --disk-size $DISK_SIZE \
    --node-role $NODE_INSTANCE_ROLE \
    --subnets $PRIVATE_SUBNET_1 $PRIVATE_SUBNET_2 \
    --security-groups $NODE_SG \
    --ami-type AL2_x86_64 \
    --capacity-type ON_DEMAND \
    --region $REGION \
    --profile $PROFILE \
    --tags \
        "Environment=lab,Name=$NODE_GROUP_NAME"

print_success "Node Group creation initiated"

# ============================================================================
# STEP 3: Wait for Node Group to be Active
# ============================================================================
print_step "Waiting for node group to be ACTIVE..."

WAIT_TIME=0
MAX_WAIT=600  # 10 minutes
INTERVAL=15   # Check every 15 seconds

while [ $WAIT_TIME -lt $MAX_WAIT ]; do
    STATUS=$(aws eks describe-nodegroup \
        --cluster-name $CLUSTER_NAME \
        --nodegroup-name $NODE_GROUP_NAME \
        --region $REGION \
        --profile $PROFILE \
        --query 'nodegroup.status' \
        --output text 2>/dev/null || echo "UNKNOWN")
    
    NODE_COUNT=$(aws eks describe-nodegroup \
        --cluster-name $CLUSTER_NAME \
        --nodegroup-name $NODE_GROUP_NAME \
        --region $REGION \
        --profile $PROFILE \
        --query 'nodegroup.resources.autoScalingGroups[0].desiredCapacity' \
        --output text 2>/dev/null || echo "0")
    
    echo -ne "\r[$(($WAIT_TIME / 60))m] Status: $STATUS (Nodes: $NODE_COUNT)"
    
    if [ "$STATUS" = "ACTIVE" ]; then
        echo ""
        break
    fi
    
    sleep $INTERVAL
    WAIT_TIME=$((WAIT_TIME + INTERVAL))
done

if [ "$STATUS" != "ACTIVE" ]; then
    print_error "Node Group creation timeout. Status: $STATUS"
    exit 1
fi

echo ""
print_success "Node Group is now ACTIVE!"

# ============================================================================
# STEP 4: Wait for nodes to be ready in Kubernetes
# ============================================================================
print_step "Waiting for nodes to be ready in Kubernetes..."

WAIT_TIME=0
MAX_WAIT=300  # 5 minutes
INTERVAL=10

while [ $WAIT_TIME -lt $MAX_WAIT ]; do
    READY_NODES=$(kubectl get nodes --no-headers 2>/dev/null | grep -c "Ready" || echo "0")
    TOTAL_NODES=$(kubectl get nodes --no-headers 2>/dev/null | wc -l || echo "0")
    
    echo -ne "\r[$(($WAIT_TIME / 60))m] Ready nodes: $READY_NODES/$TOTAL_NODES"
    
    if [ "$READY_NODES" -eq "$DESIRED_SIZE" ]; then
        echo ""
        break
    fi
    
    sleep $INTERVAL
    WAIT_TIME=$((WAIT_TIME + INTERVAL))
done

print_success "All nodes are ready!"

# ============================================================================
# STEP 5: Display node information
# ============================================================================
print_step "Node Information:"
echo ""
kubectl get nodes -o wide
echo ""

# Show node details
echo "Node Resources:"
kubectl top nodes 2>/dev/null || echo "Metrics not available yet (wait 1-2 minutes)"
echo ""

# ============================================================================
# STEP 6: Create Fargate Profile
# ============================================================================
print_step "Creating Fargate Profile..."

# First, create the Fargate namespace
kubectl create namespace fargate --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace fargate workload=fargate

FARGATE_PROFILE_NAME="${LAB_NAME}-fargate-profile"

aws eks create-fargate-profile \
    --cluster-name $CLUSTER_NAME \
    --fargate-profile-name $FARGATE_PROFILE_NAME \
    --pod-execution-role-arn $FARGATE_ROLE \
    --subnets $PRIVATE_SUBNET_1 $PRIVATE_SUBNET_2 \
    --selectors namespace=fargate \
    --region $REGION \
    --profile $PROFILE \
    --tags \
        "Environment=lab,Name=$FARGATE_PROFILE_NAME"

print_success "Fargate Profile creation initiated"

# ============================================================================
# STEP 7: Wait for Fargate Profile to be Active
# ============================================================================
print_step "Waiting for Fargate Profile to be ACTIVE..."

WAIT_TIME=0
MAX_WAIT=300  # 5 minutes
INTERVAL=15

while [ $WAIT_TIME -lt $MAX_WAIT ]; do
    STATUS=$(aws eks describe-fargate-profile \
        --cluster-name $CLUSTER_NAME \
        --fargate-profile-name $FARGATE_PROFILE_NAME \
        --region $REGION \
        --profile $PROFILE \
        --query 'fargateProfile.status' \
        --output text 2>/dev/null || echo "UNKNOWN")
    
    echo -ne "\r[$(($WAIT_TIME / 60))m] Status: $STATUS"
    
    if [ "$STATUS" = "ACTIVE" ]; then
        echo ""
        break
    fi
    
    sleep $INTERVAL
    WAIT_TIME=$((WAIT_TIME + INTERVAL))
done

if [ "$STATUS" != "ACTIVE" ]; then
    print_error "Fargate Profile creation timeout. Status: $STATUS"
    exit 1
fi

echo ""
print_success "Fargate Profile is now ACTIVE!"

# ============================================================================
# STEP 8: Test pod scheduling on Fargate
# ============================================================================
print_step "Testing Fargate pod scheduling..."

# Create a test deployment in Fargate namespace
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fargate-test
  namespace: fargate
spec:
  replicas: 1
  selector:
    matchLabels:
      app: fargate-test
  template:
    metadata:
      labels:
        app: fargate-test
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        ports:
        - containerPort: 80
        resources:
          requests:
            memory: "64Mi"
            cpu: "100m"
          limits:
            memory: "128Mi"
            cpu: "200m"
EOF

print_success "Fargate test deployment created"

# Wait for pod to be running
WAIT_TIME=0
MAX_WAIT=120  # 2 minutes
INTERVAL=10

while [ $WAIT_TIME -lt $MAX_WAIT ]; do
    POD_STATUS=$(kubectl get pods -n fargate -l app=fargate-test \
        --no-headers 2>/dev/null | awk '{print $3}' | head -1 || echo "UNKNOWN")
    
    echo -ne "\r[$(($WAIT_TIME / 60))m] Pod Status: $POD_STATUS"
    
    if [ "$POD_STATUS" = "Running" ]; then
        echo ""
        break
    fi
    
    sleep $INTERVAL
    WAIT_TIME=$((WAIT_TIME + INTERVAL))
done

if [ "$POD_STATUS" != "Running" ]; then
    print_error "Fargate pod failed to run. Status: $POD_STATUS"
else
    print_success "Fargate pod is running!"
fi

# Delete test pod
kubectl delete deployment fargate-test -n fargate

# ============================================================================
# STEP 9: Tag subnets for ELB/ALB discovery
# ============================================================================
print_step "Tagging subnets for ELB/ALB discovery..."

# Public subnets for ELB
for subnet in $PUBLIC_SUBNET_1 $PUBLIC_SUBNET_2; do
    aws ec2 create-tags \
        --resources $subnet \
        --tags Key=kubernetes.io/role/elb,Value=1 \
        --region $REGION \
        --profile $PROFILE
done

# Private subnets for internal ALB
for subnet in $PRIVATE_SUBNET_1 $PRIVATE_SUBNET_2; do
    aws ec2 create-tags \
        --resources $subnet \
        --tags Key=kubernetes.io/role/internal-elb,Value=1 \
        --region $REGION \
        --profile $PROFILE
done

print_success "Subnets tagged for load balancer discovery"

# ============================================================================
# STEP 10: Save node group information
# ============================================================================
echo "" >> ./eks-lab-resources.txt
echo "# Phase 3 - Node Groups" >> ./eks-lab-resources.txt
echo "NODE_GROUP_NAME=$NODE_GROUP_NAME" >> ./eks-lab-resources.txt
echo "FARGATE_PROFILE_NAME=$FARGATE_PROFILE_NAME" >> ./eks-lab-resources.txt

# ============================================================================
# STEP 11: Summary
# ============================================================================
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}✓ Phase 3 Completed Successfully!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Node Groups:"
echo "─────────────────────────────────────────"
aws eks list-nodegroups \
    --cluster-name $CLUSTER_NAME \
    --region $REGION \
    --profile $PROFILE \
    --output table
echo ""
echo "Fargate Profiles:"
echo "─────────────────────────────────────────"
aws eks list-fargate-profiles \
    --cluster-name $CLUSTER_NAME \
    --region $REGION \
    --profile $PROFILE \
    --output table
echo ""
echo "Current Nodes:"
echo "─────────────────────────────────────────"
kubectl get nodes -o wide
echo ""
echo "All System Pods:"
echo "─────────────────────────────────────────"
kubectl get pods -A
echo ""
echo -e "${YELLOW}Next step: Run Phase 4 to configure cluster${NC}"
echo "bash phase-4-configure-cluster.sh"
echo ""
