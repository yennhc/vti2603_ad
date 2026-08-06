#!/bin/bash

#############################################################################
# EKS Lab - Phase 2: Create EKS Cluster
# 
# Công việc:
# - Tạo EKS Cluster control plane
# - Cấu hình logging
# - Kích hoạt OIDC provider
# 
# Thời gian: ~15 minutes (actual creation: 10-15 min)
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
K8S_VERSION="1.30"

# Load resources from Phase 1
if [ ! -f "./eks-lab-resources.txt" ]; then
    echo -e "${RED}Error: eks-lab-resources.txt not found!${NC}"
    echo "Please run phase-1-prerequisites.sh first"
    exit 1
fi

source ./eks-lab-resources.txt

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}EKS Lab - Phase 2: Create Cluster${NC}"
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
# STEP 1: Verify prerequisites
# ============================================================================
print_step "Verifying Phase 1 resources..."

required_vars=("VPC_ID" "PRIVATE_SUBNET_1" "PRIVATE_SUBNET_2" "CONTROL_PLANE_SG" "EKS_SERVICE_ROLE")

for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        print_error "Missing variable: $var"
        exit 1
    fi
done

print_success "All required resources found"

# ============================================================================
# STEP 2: Create EKS Cluster
# ============================================================================
print_step "Creating EKS Cluster: $CLUSTER_NAME..."
print_step "This may take 10-15 minutes. Please wait..."
echo ""

aws eks create-cluster \
    --name $CLUSTER_NAME \
    --version $K8S_VERSION \
    --region $REGION \
    --profile $PROFILE \
    --role-arn $EKS_SERVICE_ROLE \
    --resources-vpc-config \
        subnetIds=$PRIVATE_SUBNET_1,$PRIVATE_SUBNET_2,\
        securityGroupIds=$CONTROL_PLANE_SG,\
        endpointPublicAccess=true,\
        endpointPrivateAccess=false \
    --logging \
        clusterLogging=[{enabled=true,types=[api,audit,authenticator,controllerManager,scheduler]}] \
    --tags \
        "Environment=lab,Name=$CLUSTER_NAME"

print_success "Cluster creation initiated"

# ============================================================================
# STEP 3: Wait for cluster to be active
# ============================================================================
print_step "Waiting for cluster to be ACTIVE..."
print_step "This may take 10-15 minutes..."

# Show progress
WAIT_TIME=0
MAX_WAIT=1200  # 20 minutes
INTERVAL=30    # Check every 30 seconds

while [ $WAIT_TIME -lt $MAX_WAIT ]; do
    STATUS=$(aws eks describe-cluster \
        --name $CLUSTER_NAME \
        --region $REGION \
        --profile $PROFILE \
        --query 'cluster.status' \
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
    print_error "Cluster creation timeout or failed. Status: $STATUS"
    exit 1
fi

echo ""
print_success "Cluster is now ACTIVE!"

# ============================================================================
# STEP 4: Get cluster information
# ============================================================================
print_step "Retrieving cluster information..."

CLUSTER_INFO=$(aws eks describe-cluster \
    --name $CLUSTER_NAME \
    --region $REGION \
    --profile $PROFILE \
    --query 'cluster')

CLUSTER_ARN=$(echo $CLUSTER_INFO | jq -r '.arn')
CLUSTER_ENDPOINT=$(echo $CLUSTER_INFO | jq -r '.endpoint')
CLUSTER_CA=$(echo $CLUSTER_INFO | jq -r '.certificateAuthority.data')

print_success "Cluster information retrieved"

# ============================================================================
# STEP 5: Update kubeconfig
# ============================================================================
print_step "Updating kubeconfig..."

aws eks update-kubeconfig \
    --name $CLUSTER_NAME \
    --region $REGION \
    --profile $PROFILE

print_success "kubeconfig updated"

# ============================================================================
# STEP 6: Verify cluster connectivity
# ============================================================================
print_step "Verifying cluster connectivity..."

if kubectl cluster-info &> /dev/null; then
    print_success "kubectl can access the cluster"
else
    print_error "Failed to access cluster with kubectl"
    exit 1
fi

# ============================================================================
# STEP 7: Create OIDC Provider (required for IRSA)
# ============================================================================
print_step "Setting up OIDC Provider for IRSA..."

# Extract OIDC URL
OIDC_URL=$(aws eks describe-cluster \
    --name $CLUSTER_NAME \
    --region $REGION \
    --profile $PROFILE \
    --query 'cluster.identity.oidc.issuer' \
    --output text | cut -d '/' -f 5)

# Check if OIDC provider already exists
EXISTING_OIDC=$(aws iam list-open-id-connect-providers \
    --profile $PROFILE \
    --query "OpenIDConnectProviderList[].OpenIDConnectProviderArn" \
    --output text | grep -o "$OIDC_URL" || echo "")

if [ -z "$EXISTING_OIDC" ]; then
    print_step "Creating OIDC provider..."
    
    # Get thumbprint
    THUMBPRINT=$(echo | openssl s_client -servername oidc.eks.$REGION.amazonaws.com \
        -showcerts -connect oidc.eks.$REGION.amazonaws.com:443 2>&- | \
        openssl x509 -fingerprint -noout | sed 's/://g' | awk '{print $NF}')
    
    aws iam create-open-id-connect-provider \
        --url https://oidc.eks.$REGION.amazonaws.com/id/$OIDC_URL \
        --client-id-list sts.amazonaws.com \
        --thumbprint-list $THUMBPRINT \
        --profile $PROFILE > /dev/null 2>&1 || true
    
    print_success "OIDC provider created"
else
    print_success "OIDC provider already exists"
fi

# ============================================================================
# STEP 8: Save cluster information
# ============================================================================
echo "" >> ./eks-lab-resources.txt
echo "# Phase 2 - Cluster Information" >> ./eks-lab-resources.txt
echo "CLUSTER_NAME=$CLUSTER_NAME" >> ./eks-lab-resources.txt
echo "CLUSTER_ARN=$CLUSTER_ARN" >> ./eks-lab-resources.txt
echo "CLUSTER_ENDPOINT=$CLUSTER_ENDPOINT" >> ./eks-lab-resources.txt
echo "CLUSTER_CA=$CLUSTER_CA" >> ./eks-lab-resources.txt
echo "OIDC_URL=$OIDC_URL" >> ./eks-lab-resources.txt

# ============================================================================
# STEP 9: Check control plane components
# ============================================================================
print_step "Checking control plane components..."

echo ""
echo "System Pods:"
kubectl get pods -n kube-system

# ============================================================================
# STEP 10: Summary
# ============================================================================
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}✓ Phase 2 Completed Successfully!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Cluster Information:"
echo "─────────────────────────────────────────"
echo "Cluster Name:              $CLUSTER_NAME"
echo "Cluster ARN:               $CLUSTER_ARN"
echo "Endpoint:                  $CLUSTER_ENDPOINT"
echo "Kubernetes Version:        $K8S_VERSION"
echo "Region:                    $REGION"
echo "OIDC Issuer:               https://oidc.eks.$REGION.amazonaws.com/id/$OIDC_URL"
echo ""
echo "Cluster Status:"
kubectl cluster-info
echo ""
echo -e "${YELLOW}Next step: Run Phase 3 to add node groups${NC}"
echo "bash phase-3-add-nodegroups.sh"
echo ""
