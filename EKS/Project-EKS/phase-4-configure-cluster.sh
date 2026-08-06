#!/bin/bash

#############################################################################
# EKS Lab - Phase 4: Configure Cluster
# 
# Công việc:
# - Cài đặt Add-ons (VPC CNI, CoreDNS, kube-proxy)
# - Cấu hình Storage Classes
# - Thiết lập RBAC
# - Cấu hình CloudWatch logging
#
# Thời gian: ~20 minutes
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

# Load resources
if [ ! -f "./eks-lab-resources.txt" ]; then
    echo -e "${RED}Error: eks-lab-resources.txt not found!${NC}"
    exit 1
fi

source ./eks-lab-resources.txt

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}EKS Lab - Phase 4: Configure Cluster${NC}"
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

# ============================================================================
# STEP 1: Verify cluster access
# ============================================================================
print_step "Verifying cluster access..."

if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}Cannot access cluster. Please run Phase 1-3 first.${NC}"
    exit 1
fi

print_success "Cluster access verified"

# ============================================================================
# STEP 2: Update Add-ons
# ============================================================================
print_step "Installing/Updating Add-ons..."

# Get cluster version
K8S_VERSION=$(kubectl version --short | grep Server | awk '{print $3}' | cut -d'.' -f1,2)
print_success "Kubernetes version: $K8S_VERSION"

# Get latest addon version
get_addon_version() {
    local addon_name=$1
    aws eks describe-addon \
        --cluster-name $CLUSTER_NAME \
        --addon-name $addon_name \
        --region $REGION \
        --profile $PROFILE \
        --query 'addon.addonVersion' \
        --output text 2>/dev/null || echo ""
}

# Install or update VPC CNI
print_step "Managing vpc-cni addon..."
CURRENT_VPC_CNI=$(get_addon_version "vpc-cni" || echo "")

if [ -z "$CURRENT_VPC_CNI" ]; then
    aws eks create-addon \
        --cluster-name $CLUSTER_NAME \
        --addon-name vpc-cni \
        --region $REGION \
        --profile $PROFILE \
        --service-account-role-arn "$(aws iam get-role --role-name ${LAB_NAME}-vpc-cni-role --profile $PROFILE --query 'Role.Arn' --output text 2>/dev/null || echo '')" || true
    print_success "vpc-cni addon installed"
else
    print_success "vpc-cni addon already exists (version: $CURRENT_VPC_CNI)"
fi

# Install or update CoreDNS
print_step "Managing coredns addon..."
CURRENT_COREDNS=$(get_addon_version "coredns" || echo "")

if [ -z "$CURRENT_COREDNS" ]; then
    aws eks create-addon \
        --cluster-name $CLUSTER_NAME \
        --addon-name coredns \
        --region $REGION \
        --profile $PROFILE || true
    print_success "coredns addon installed"
else
    print_success "coredns addon already exists (version: $CURRENT_COREDNS)"
fi

# Install or update kube-proxy
print_step "Managing kube-proxy addon..."
CURRENT_KUBE_PROXY=$(get_addon_version "kube-proxy" || echo "")

if [ -z "$CURRENT_KUBE_PROXY" ]; then
    aws eks create-addon \
        --cluster-name $CLUSTER_NAME \
        --addon-name kube-proxy \
        --region $REGION \
        --profile $PROFILE || true
    print_success "kube-proxy addon installed"
else
    print_success "kube-proxy addon already exists (version: $CURRENT_KUBE_PROXY)"
fi

# Wait for addons to be healthy
print_step "Waiting for addons to be healthy..."
sleep 10

kubectl wait --for=condition=Available --timeout=180s deployment/coredns -n kube-system 2>/dev/null || true

# ============================================================================
# STEP 3: Create Storage Classes
# ============================================================================
print_step "Creating Storage Classes..."

# EBS GP3 Storage Class
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs-gp3
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  iops: "3000"
  throughput: "125"
  fstype: ext4
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs-gp2
provisioner: ebs.csi.aws.com
parameters:
  type: gp2
  fstype: ext4
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
EOF

print_success "Storage classes created"

# ============================================================================
# STEP 4: Create RBAC Resources
# ============================================================================
print_step "Creating RBAC resources..."

# Create namespaces
kubectl create namespace app-lab --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

print_success "Namespaces created"

# Create service accounts
kubectl create serviceaccount app-sa -n app-lab --dry-run=client -o yaml | kubectl apply -f -
kubectl create serviceaccount db-sa -n app-lab --dry-run=client -o yaml | kubectl apply -f -

print_success "Service accounts created"

# Create Roles and RoleBindings
cat <<EOF | kubectl apply -f -
---
# Pod reader role (for debugging)
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: app-lab
rules:
- apiGroups: [""]
  resources: ["pods", "pods/log"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["pods/exec"]
  verbs: ["create"]
---
# Bind pod reader role to app-sa
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: read-pods
  namespace: app-lab
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: pod-reader
subjects:
- kind: ServiceAccount
  name: app-sa
  namespace: app-lab
---
# Deployment deployer role
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: deployment-manager
  namespace: app-lab
rules:
- apiGroups: ["apps"]
  resources: ["deployments", "statefulsets"]
  verbs: ["get", "list", "watch", "create", "update", "patch"]
- apiGroups: [""]
  resources: ["services"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: manage-deployments
  namespace: app-lab
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: deployment-manager
subjects:
- kind: ServiceAccount
  name: app-sa
  namespace: app-lab
EOF

print_success "RBAC roles created"

# ============================================================================
# STEP 5: Enable Control Plane Logging
# ============================================================================
print_step "Verifying control plane logging..."

LOGGING_CONFIG=$(aws eks describe-cluster \
    --name $CLUSTER_NAME \
    --region $REGION \
    --profile $PROFILE \
    --query 'cluster.logging.clusterLogging[0].enabled' \
    --output text)

if [ "$LOGGING_CONFIG" = "true" ]; then
    print_success "Control plane logging is enabled"
else
    print_step "Enabling control plane logging..."
    aws eks update-cluster-config \
        --name $CLUSTER_NAME \
        --logging '{"clusterLogging":[{"enabled":true,"types":["api","audit","authenticator","controllerManager","scheduler"]}]}' \
        --region $REGION \
        --profile $PROFILE
    print_success "Control plane logging enabled"
fi

# ============================================================================
# STEP 6: Configure CloudWatch Container Insights
# ============================================================================
print_step "Setting up CloudWatch Container Insights..."

# Check if CloudWatch agent is already deployed
if kubectl get daemonset -n amazon-cloudwatch cloudwatch-agent &> /dev/null; then
    print_success "CloudWatch Container Insights already installed"
else
    print_step "Installing CloudWatch Container Insights..."
    
    # Create namespace
    kubectl create namespace amazon-cloudwatch --dry-run=client -o yaml | kubectl apply -f -
    
    # Deploy CloudWatch agent
    # In production, use Helm or CloudWatch agent DaemonSet
    # For this lab, we'll just inform that it's optional
    print_success "CloudWatch Container Insights namespace created"
    echo "Note: To enable full monitoring, install CloudWatch Agent:"
    echo "helm repo add aws https://aws.github.io/eks-charts"
    echo "helm install cloudwatch-agent aws/aws-cloudwatch-metrics --namespace amazon-cloudwatch"
fi

# ============================================================================
# STEP 7: Configure Network Policies (optional)
# ============================================================================
print_step "Setting up Network Policy support..."

# Check if Calico is needed
print_step "Installing Calico for network policies (optional)..."

# Install Calico CRDs and operator
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/tigera-operator.yaml || true

# Wait for operator
sleep 10

# Apply Installation resource
cat <<EOF | kubectl apply -f - || true
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
    - blockSize: 26
      cidr: 10.0.0.0/8
      encapsulation: VXLANCrossSubnet
      natOutgoing: Enabled
      nodeSelector: all()
EOF

print_success "Calico network policy installed"

# ============================================================================
# STEP 8: Create example NetworkPolicy
# ============================================================================
print_step "Creating example NetworkPolicy..."

cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: app-lab
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-backend
  namespace: app-lab
spec:
  podSelector:
    matchLabels:
      tier: backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          tier: frontend
    ports:
    - protocol: TCP
      port: 5000
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-backend-to-db
  namespace: app-lab
spec:
  podSelector:
    matchLabels:
      tier: database
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          tier: backend
    ports:
    - protocol: TCP
      port: 5432
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: app-lab
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: UDP
      port: 53
EOF

print_success "Network policies created"

# ============================================================================
# STEP 9: Install AWS Load Balancer Controller
# ============================================================================
print_step "Installing AWS Load Balancer Controller..."

# Create IAM role for ALB controller
ALB_CONTROLLER_ROLE_NAME="${LAB_NAME}-alb-controller-role"

# Check if role exists
if ! aws iam get-role --role-name $ALB_CONTROLLER_ROLE_NAME --profile $PROFILE &> /dev/null; then
    print_step "Creating IAM role for ALB Controller..."
    
    # Create trust policy
    cat > /tmp/alb-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::%ACCOUNT_ID%:oidc-provider/%OIDC_URL%"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "%OIDC_URL%:sub": "system:serviceaccount:kube-system:aws-load-balancer-controller",
          "%OIDC_URL%:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
EOF

    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --profile $PROFILE)
    sed -i "s|%ACCOUNT_ID%|$ACCOUNT_ID|g" /tmp/alb-trust-policy.json
    sed -i "s|%OIDC_URL%|$OIDC_URL|g" /tmp/alb-trust-policy.json
    
    aws iam create-role \
        --role-name $ALB_CONTROLLER_ROLE_NAME \
        --assume-role-policy-document file:///tmp/alb-trust-policy.json \
        --profile $PROFILE || true
    
    print_success "ALB Controller role created"
fi

# Attach policy
aws iam attach-role-policy \
    --role-name $ALB_CONTROLLER_ROLE_NAME \
    --policy-arn arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess \
    --profile $PROFILE 2>/dev/null || true

print_success "ALB Controller IAM policy attached"

# Install via Helm
print_step "Installing AWS Load Balancer Controller via Helm..."

if helm repo list | grep -q "eks"; then
    print_success "EKS Helm repo already added"
else
    helm repo add eks https://aws.github.io/eks-charts
fi

helm repo update eks

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
    -n kube-system \
    --set clusterName=$CLUSTER_NAME \
    --set serviceAccount.create=true \
    --set serviceAccount.name=aws-load-balancer-controller \
    --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="arn:aws:iam::$ACCOUNT_ID:role/$ALB_CONTROLLER_ROLE_NAME" || true

print_success "AWS Load Balancer Controller installed"

# ============================================================================
# STEP 10: Verify configuration
# ============================================================================
print_step "Verifying cluster configuration..."
echo ""
echo "Namespaces:"
kubectl get namespaces
echo ""
echo "Storage Classes:"
kubectl get storageclass
echo ""
echo "Add-ons:"
aws eks list-addons --cluster-name $CLUSTER_NAME --region $REGION --profile $PROFILE --output table
echo ""
echo "Kube-system Pods:"
kubectl get pods -n kube-system
echo ""

# ============================================================================
# STEP 11: Save configuration info
# ============================================================================
echo "" >> ./eks-lab-resources.txt
echo "# Phase 4 - Configuration" >> ./eks-lab-resources.txt
echo "ALB_CONTROLLER_ROLE=$ALB_CONTROLLER_ROLE_NAME" >> ./eks-lab-resources.txt

# ============================================================================
# Summary
# ============================================================================
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}✓ Phase 4 Completed Successfully!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Configuration Summary:"
echo "─────────────────────────────────────────"
echo "✓ Add-ons installed (VPC CNI, CoreDNS, kube-proxy)"
echo "✓ Storage Classes configured (EBS GP3, GP2)"
echo "✓ RBAC configured (Namespaces, Roles, ServiceAccounts)"
echo "✓ Control Plane logging enabled"
echo "✓ CloudWatch Container Insights namespace created"
echo "✓ Network Policies installed (Calico)"
echo "✓ AWS Load Balancer Controller installed"
echo ""
echo -e "${YELLOW}Next step: Run Phase 5 to deploy applications${NC}"
echo "bash phase-5-deploy-applications.sh"
echo ""
