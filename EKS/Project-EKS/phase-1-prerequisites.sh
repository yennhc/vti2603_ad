#!/bin/bash

#############################################################################
# EKS Lab - Phase 1: Prerequisites & Planning
# 
# Công việc:
# - Tạo VPC
# - Tạo Public & Private Subnets
# - Tạo Internet Gateway & NAT Gateway
# - Tạo Security Groups
# - Tạo IAM Roles
#
# Thời gian: ~30 minutes
#############################################################################

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
REGION="ap-southeast-1"
PROFILE="${AWS_PROFILE:-default}"
LAB_NAME="eks-lab"
ENVIRONMENT="lab"

# Network Configuration
VPC_CIDR="10.0.0.0/16"
PUBLIC_SUBNET_1_CIDR="10.0.1.0/24"
PUBLIC_SUBNET_2_CIDR="10.0.2.0/24"
PRIVATE_SUBNET_1_CIDR="10.0.10.0/24"
PRIVATE_SUBNET_2_CIDR="10.0.11.0/24"

# Availability zones
AZ1="${REGION}a"
AZ2="${REGION}b"

# Output file for tracking resource IDs
OUTPUT_FILE="./eks-lab-resources.txt"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}EKS Lab - Phase 1: Prerequisites${NC}"
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

# Function: Save resource ID
save_resource() {
    echo "$1" >> "$OUTPUT_FILE"
}

# ============================================================================
# STEP 1: Verify AWS Credentials
# ============================================================================
print_step "Verifying AWS credentials..."

if ! aws sts get-caller-identity --region $REGION --profile $PROFILE > /dev/null 2>&1; then
    print_error "AWS credentials not configured. Run: aws configure --profile $PROFILE"
    exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --profile $PROFILE)
print_success "AWS Account: $ACCOUNT_ID"

# Initialize output file
> "$OUTPUT_FILE"
echo "# EKS Lab Resources - Phase 1" > "$OUTPUT_FILE"
echo "# Created: $(date)" >> "$OUTPUT_FILE"
echo "# Region: $REGION" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# ============================================================================
# STEP 2: Create VPC
# ============================================================================
print_step "Creating VPC ($VPC_CIDR)..."

VPC_ID=$(aws ec2 create-vpc \
    --cidr-block $VPC_CIDR \
    --region $REGION \
    --profile $PROFILE \
    --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${LAB_NAME}-vpc},{Key=Environment,Value=${ENVIRONMENT}}]" \
    --query 'Vpc.VpcId' \
    --output text)

print_success "VPC created: $VPC_ID"
save_resource "VPC_ID=$VPC_ID"

# Enable DNS hostnames
aws ec2 modify-vpc-attribute \
    --vpc-id $VPC_ID \
    --enable-dns-hostnames \
    --region $REGION \
    --profile $PROFILE

print_success "DNS hostnames enabled"

# ============================================================================
# STEP 3: Create Internet Gateway
# ============================================================================
print_step "Creating Internet Gateway..."

IGW_ID=$(aws ec2 create-internet-gateway \
    --region $REGION \
    --profile $PROFILE \
    --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${LAB_NAME}-igw}]" \
    --query 'InternetGateway.InternetGatewayId' \
    --output text)

print_success "Internet Gateway created: $IGW_ID"
save_resource "IGW_ID=$IGW_ID"

# Attach IGW to VPC
aws ec2 attach-internet-gateway \
    --internet-gateway-id $IGW_ID \
    --vpc-id $VPC_ID \
    --region $REGION \
    --profile $PROFILE

print_success "Internet Gateway attached to VPC"

# ============================================================================
# STEP 4: Create Public Subnets
# ============================================================================
print_step "Creating Public Subnet 1 ($PUBLIC_SUBNET_1_CIDR in $AZ1)..."

PUBLIC_SUBNET_1=$(aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block $PUBLIC_SUBNET_1_CIDR \
    --availability-zone $AZ1 \
    --region $REGION \
    --profile $PROFILE \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${LAB_NAME}-public-subnet-1},{Key=Type,Value=Public}]" \
    --query 'Subnet.SubnetId' \
    --output text)

print_success "Public Subnet 1 created: $PUBLIC_SUBNET_1"
save_resource "PUBLIC_SUBNET_1=$PUBLIC_SUBNET_1"

# Enable public IP auto-assignment
aws ec2 modify-subnet-attribute \
    --subnet-id $PUBLIC_SUBNET_1 \
    --map-public-ip-on-launch \
    --region $REGION \
    --profile $PROFILE

print_step "Creating Public Subnet 2 ($PUBLIC_SUBNET_2_CIDR in $AZ2)..."

PUBLIC_SUBNET_2=$(aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block $PUBLIC_SUBNET_2_CIDR \
    --availability-zone $AZ2 \
    --region $REGION \
    --profile $PROFILE \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${LAB_NAME}-public-subnet-2},{Key=Type,Value=Public}]" \
    --query 'Subnet.SubnetId' \
    --output text)

print_success "Public Subnet 2 created: $PUBLIC_SUBNET_2"
save_resource "PUBLIC_SUBNET_2=$PUBLIC_SUBNET_2"

aws ec2 modify-subnet-attribute \
    --subnet-id $PUBLIC_SUBNET_2 \
    --map-public-ip-on-launch \
    --region $REGION \
    --profile $PROFILE

# ============================================================================
# STEP 5: Create Private Subnets
# ============================================================================
print_step "Creating Private Subnet 1 ($PRIVATE_SUBNET_1_CIDR in $AZ1)..."

PRIVATE_SUBNET_1=$(aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block $PRIVATE_SUBNET_1_CIDR \
    --availability-zone $AZ1 \
    --region $REGION \
    --profile $PROFILE \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${LAB_NAME}-private-subnet-1},{Key=Type,Value=Private}]" \
    --query 'Subnet.SubnetId' \
    --output text)

print_success "Private Subnet 1 created: $PRIVATE_SUBNET_1"
save_resource "PRIVATE_SUBNET_1=$PRIVATE_SUBNET_1"

print_step "Creating Private Subnet 2 ($PRIVATE_SUBNET_2_CIDR in $AZ2)..."

PRIVATE_SUBNET_2=$(aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block $PRIVATE_SUBNET_2_CIDR \
    --availability-zone $AZ2 \
    --region $REGION \
    --profile $PROFILE \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${LAB_NAME}-private-subnet-2},{Key=Type,Value=Private}]" \
    --query 'Subnet.SubnetId' \
    --output text)

print_success "Private Subnet 2 created: $PRIVATE_SUBNET_2"
save_resource "PRIVATE_SUBNET_2=$PRIVATE_SUBNET_2"

# ============================================================================
# STEP 6: Create NAT Gateway (in Public Subnet 1)
# ============================================================================
print_step "Allocating Elastic IP for NAT Gateway..."

EIP=$(aws ec2 allocate-address \
    --domain vpc \
    --region $REGION \
    --profile $PROFILE \
    --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=${LAB_NAME}-nat-eip}]" \
    --query 'AllocationId' \
    --output text)

print_success "Elastic IP allocated: $EIP"
save_resource "ELASTIC_IP=$EIP"

print_step "Creating NAT Gateway in Public Subnet 1..."

NAT_GW=$(aws ec2 create-nat-gateway \
    --subnet-id $PUBLIC_SUBNET_1 \
    --allocation-id $EIP \
    --region $REGION \
    --profile $PROFILE \
    --tag-specifications "ResourceType=natgateway,Tags=[{Key=Name,Value=${LAB_NAME}-nat-gw}]" \
    --query 'NatGateway.NatGatewayId' \
    --output text)

print_success "NAT Gateway created: $NAT_GW"
save_resource "NAT_GW=$NAT_GW"

# Wait for NAT Gateway to be available
print_step "Waiting for NAT Gateway to be available (this may take 1-2 minutes)..."
aws ec2 wait nat-gateway-available \
    --nat-gateway-ids $NAT_GW \
    --region $REGION \
    --profile $PROFILE

print_success "NAT Gateway is available"

# ============================================================================
# STEP 7: Create Route Tables
# ============================================================================
print_step "Creating Public Route Table..."

PUBLIC_RT=$(aws ec2 create-route-table \
    --vpc-id $VPC_ID \
    --region $REGION \
    --profile $PROFILE \
    --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${LAB_NAME}-public-rt}]" \
    --query 'RouteTable.RouteTableId' \
    --output text)

print_success "Public Route Table created: $PUBLIC_RT"
save_resource "PUBLIC_RT=$PUBLIC_RT"

# Add route to IGW
aws ec2 create-route \
    --route-table-id $PUBLIC_RT \
    --destination-cidr-block 0.0.0.0/0 \
    --gateway-id $IGW_ID \
    --region $REGION \
    --profile $PROFILE

print_success "Route to IGW added"

# Associate public subnets with public RT
aws ec2 associate-route-table \
    --subnet-id $PUBLIC_SUBNET_1 \
    --route-table-id $PUBLIC_RT \
    --region $REGION \
    --profile $PROFILE

aws ec2 associate-route-table \
    --subnet-id $PUBLIC_SUBNET_2 \
    --route-table-id $PUBLIC_RT \
    --region $REGION \
    --profile $PROFILE

print_success "Public subnets associated with public RT"

# Create Private Route Tables (one for each AZ)
print_step "Creating Private Route Table 1 (for AZ1)..."

PRIVATE_RT_1=$(aws ec2 create-route-table \
    --vpc-id $VPC_ID \
    --region $REGION \
    --profile $PROFILE \
    --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${LAB_NAME}-private-rt-1}]" \
    --query 'RouteTable.RouteTableId' \
    --output text)

print_success "Private Route Table 1 created: $PRIVATE_RT_1"
save_resource "PRIVATE_RT_1=$PRIVATE_RT_1"

# Add route to NAT Gateway
aws ec2 create-route \
    --route-table-id $PRIVATE_RT_1 \
    --destination-cidr-block 0.0.0.0/0 \
    --nat-gateway-id $NAT_GW \
    --region $REGION \
    --profile $PROFILE

# Associate private subnet 1
aws ec2 associate-route-table \
    --subnet-id $PRIVATE_SUBNET_1 \
    --route-table-id $PRIVATE_RT_1 \
    --region $REGION \
    --profile $PROFILE

print_success "Private Subnet 1 associated with Private RT 1"

# Create another NAT GW for high availability (optional for this lab, but good practice)
print_step "Creating NAT Gateway 2 in Public Subnet 2 (for HA)..."

EIP_2=$(aws ec2 allocate-address \
    --domain vpc \
    --region $REGION \
    --profile $PROFILE \
    --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=${LAB_NAME}-nat-eip-2}]" \
    --query 'AllocationId' \
    --output text)

NAT_GW_2=$(aws ec2 create-nat-gateway \
    --subnet-id $PUBLIC_SUBNET_2 \
    --allocation-id $EIP_2 \
    --region $REGION \
    --profile $PROFILE \
    --tag-specifications "ResourceType=natgateway,Tags=[{Key=Name,Value=${LAB_NAME}-nat-gw-2}]" \
    --query 'NatGateway.NatGatewayId' \
    --output text)

print_success "NAT Gateway 2 created: $NAT_GW_2"
save_resource "NAT_GW_2=$NAT_GW_2"

aws ec2 wait nat-gateway-available \
    --nat-gateway-ids $NAT_GW_2 \
    --region $REGION \
    --profile $PROFILE

print_step "Creating Private Route Table 2 (for AZ2)..."

PRIVATE_RT_2=$(aws ec2 create-route-table \
    --vpc-id $VPC_ID \
    --region $REGION \
    --profile $PROFILE \
    --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${LAB_NAME}-private-rt-2}]" \
    --query 'RouteTable.RouteTableId' \
    --output text)

aws ec2 create-route \
    --route-table-id $PRIVATE_RT_2 \
    --destination-cidr-block 0.0.0.0/0 \
    --nat-gateway-id $NAT_GW_2 \
    --region $REGION \
    --profile $PROFILE

aws ec2 associate-route-table \
    --subnet-id $PRIVATE_SUBNET_2 \
    --route-table-id $PRIVATE_RT_2 \
    --region $REGION \
    --profile $PROFILE

print_success "Private Subnet 2 associated with Private RT 2"
save_resource "PRIVATE_RT_2=$PRIVATE_RT_2"

# ============================================================================
# STEP 8: Create Security Groups
# ============================================================================
print_step "Creating Control Plane Security Group..."

CONTROL_PLANE_SG=$(aws ec2 create-security-group \
    --group-name ${LAB_NAME}-control-plane-sg \
    --description "Security group for EKS Control Plane" \
    --vpc-id $VPC_ID \
    --region $REGION \
    --profile $PROFILE \
    --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${LAB_NAME}-control-plane-sg}]" \
    --query 'GroupId' \
    --output text)

print_success "Control Plane SG created: $CONTROL_PLANE_SG"
save_resource "CONTROL_PLANE_SG=$CONTROL_PLANE_SG"

print_step "Creating Node Security Group..."

NODE_SG=$(aws ec2 create-security-group \
    --group-name ${LAB_NAME}-node-sg \
    --description "Security group for EKS Nodes" \
    --vpc-id $VPC_ID \
    --region $REGION \
    --profile $PROFILE \
    --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${LAB_NAME}-node-sg}]" \
    --query 'GroupId' \
    --output text)

print_success "Node SG created: $NODE_SG"
save_resource "NODE_SG=$NODE_SG"

# Add ingress rules for Node SG
print_step "Adding ingress rules to Node SG..."

# Allow nodes to communicate with each other
aws ec2 authorize-security-group-ingress \
    --group-id $NODE_SG \
    --source-group $NODE_SG \
    --protocol -1 \
    --region $REGION \
    --profile $PROFILE 2>/dev/null || true

# Allow nodes to communicate with control plane
aws ec2 authorize-security-group-ingress \
    --group-id $NODE_SG \
    --source-group $CONTROL_PLANE_SG \
    --protocol -1 \
    --region $REGION \
    --profile $PROFILE 2>/dev/null || true

# Allow control plane to communicate with nodes (443)
aws ec2 authorize-security-group-ingress \
    --group-id $CONTROL_PLANE_SG \
    --source-group $NODE_SG \
    --protocol tcp \
    --port 443 \
    --region $REGION \
    --profile $PROFILE 2>/dev/null || true

print_success "Ingress rules added"

# ============================================================================
# STEP 9: Create IAM Roles for EKS
# ============================================================================
print_step "Creating EKS Service Role..."

# Create trust policy document
cat > /tmp/eks-service-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

EKS_SERVICE_ROLE=$(aws iam create-role \
    --role-name ${LAB_NAME}-eks-service-role \
    --assume-role-policy-document file:///tmp/eks-service-trust-policy.json \
    --profile $PROFILE \
    --query 'Role.Arn' \
    --output text 2>/dev/null || echo "arn:aws:iam::$ACCOUNT_ID:role/${LAB_NAME}-eks-service-role")

print_success "EKS Service Role created: $EKS_SERVICE_ROLE"
save_resource "EKS_SERVICE_ROLE=$EKS_SERVICE_ROLE"

# Attach policies
aws iam attach-role-policy \
    --role-name ${LAB_NAME}-eks-service-role \
    --policy-arn arn:aws:iam::aws:policy/AmazonEKSServiceRolePolicy \
    --profile $PROFILE 2>/dev/null || true

print_success "AmazonEKSServiceRolePolicy attached"

# ============================================================================
# STEP 10: Create IAM Role for EC2 Nodes
# ============================================================================
print_step "Creating Node Instance Role..."

# Create trust policy for EC2
cat > /tmp/ec2-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

NODE_INSTANCE_ROLE=$(aws iam create-role \
    --role-name ${LAB_NAME}-node-instance-role \
    --assume-role-policy-document file:///tmp/ec2-trust-policy.json \
    --profile $PROFILE \
    --query 'Role.Arn' \
    --output text 2>/dev/null || echo "arn:aws:iam::$ACCOUNT_ID:role/${LAB_NAME}-node-instance-role")

print_success "Node Instance Role created: $NODE_INSTANCE_ROLE"
save_resource "NODE_INSTANCE_ROLE=$NODE_INSTANCE_ROLE"

# Attach policies
aws iam attach-role-policy \
    --role-name ${LAB_NAME}-node-instance-role \
    --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy \
    --profile $PROFILE 2>/dev/null || true

aws iam attach-role-policy \
    --role-name ${LAB_NAME}-node-instance-role \
    --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy \
    --profile $PROFILE 2>/dev/null || true

aws iam attach-role-policy \
    --role-name ${LAB_NAME}-node-instance-role \
    --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly \
    --profile $PROFILE 2>/dev/null || true

print_success "Required policies attached to Node Role"

# Create instance profile
aws iam create-instance-profile \
    --instance-profile-name ${LAB_NAME}-node-instance-profile \
    --profile $PROFILE 2>/dev/null || true

aws iam add-role-to-instance-profile \
    --instance-profile-name ${LAB_NAME}-node-instance-profile \
    --role-name ${LAB_NAME}-node-instance-role \
    --profile $PROFILE 2>/dev/null || true

print_success "Instance profile created"
save_resource "NODE_INSTANCE_PROFILE=${LAB_NAME}-node-instance-profile"

# ============================================================================
# STEP 11: Create IAM Role for Fargate
# ============================================================================
print_step "Creating Fargate Pod Execution Role..."

# Create trust policy for Fargate
cat > /tmp/fargate-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks-fargate-pods.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

FARGATE_ROLE=$(aws iam create-role \
    --role-name ${LAB_NAME}-fargate-pod-execution-role \
    --assume-role-policy-document file:///tmp/fargate-trust-policy.json \
    --profile $PROFILE \
    --query 'Role.Arn' \
    --output text 2>/dev/null || echo "arn:aws:iam::$ACCOUNT_ID:role/${LAB_NAME}-fargate-pod-execution-role")

print_success "Fargate Pod Execution Role created: $FARGATE_ROLE"
save_resource "FARGATE_ROLE=$FARGATE_ROLE"

# Attach policy
aws iam attach-role-policy \
    --role-name ${LAB_NAME}-fargate-pod-execution-role \
    --policy-arn arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy \
    --profile $PROFILE 2>/dev/null || true

print_success "Fargate policies attached"

# ============================================================================
# STEP 12: Summary
# ============================================================================
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}✓ Phase 1 Completed Successfully!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Resources created:"
echo "─────────────────────────────────────────"
echo "VPC ID:                    $VPC_ID"
echo "Public Subnet 1:           $PUBLIC_SUBNET_1"
echo "Public Subnet 2:           $PUBLIC_SUBNET_2"
echo "Private Subnet 1:          $PRIVATE_SUBNET_1"
echo "Private Subnet 2:          $PRIVATE_SUBNET_2"
echo "Internet Gateway:          $IGW_ID"
echo "NAT Gateway 1:             $NAT_GW"
echo "NAT Gateway 2:             $NAT_GW_2"
echo "Control Plane SG:          $CONTROL_PLANE_SG"
echo "Node SG:                   $NODE_SG"
echo "EKS Service Role:          $EKS_SERVICE_ROLE"
echo "Node Instance Role:        $NODE_INSTANCE_ROLE"
echo "Fargate Execution Role:    $FARGATE_ROLE"
echo ""
echo "Resource file saved to: $OUTPUT_FILE"
echo ""
echo -e "${YELLOW}Next step: Run Phase 2 to create EKS cluster${NC}"
echo "bash phase-2-create-cluster.sh"
echo ""
