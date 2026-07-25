#!/bin/bash

# =====================================================
# Script để tìm các AWS Resource IDs cần thiết
# =====================================================

REGION="ap-southeast-1"

echo "=========================================="
echo "Tìm AWS Resource IDs"
echo "Region: $REGION"
echo "=========================================="
echo ""

# ============================================
# 1. Tìm VPC ID
# ============================================
echo "1. Tìm VPC ID (CIDR: 172.19.0.0/16)"
echo "---"

VPC_INFO=$(aws ec2 describe-vpcs \
    --region $REGION \
    --filters "Name=cidr,Values=172.19.0.0/16" \
    --query 'Vpcs[0].[VpcId,CidrBlock,IsDefault]' \
    --output text)

if [ -z "$VPC_INFO" ]; then
    echo "❌ Không tìm thấy VPC với CIDR 172.19.0.0/16"
    echo "   Danh sách tất cả VPCs:"
    aws ec2 describe-vpcs \
        --region $REGION \
        --query 'Vpcs[*].[VpcId,CidrBlock]' \
        --output table
else
    VPC_ID=$(echo $VPC_INFO | awk '{print $1}')
    echo "✓ VPC ID: $VPC_ID"
    echo "  Info: $VPC_INFO"
fi

echo ""

# ============================================
# 2. Tìm Public Subnet ID
# ============================================
echo "2. Tìm Public Subnet ID (CIDR: 172.19.1.0/24)"
echo "---"

SUBNET_INFO=$(aws ec2 describe-subnets \
    --region $REGION \
    --filters "Name=cidr-block,Values=172.19.1.0/24" \
    --query 'Subnets[0].[SubnetId,CidrBlock,AvailabilityZone,VpcId]' \
    --output text)

if [ -z "$SUBNET_INFO" ]; then
    echo "❌ Không tìm thấy Subnet với CIDR 172.19.1.0/24"
    if [ ! -z "$VPC_ID" ]; then
        echo "   Danh sách Subnets trong VPC $VPC_ID:"
        aws ec2 describe-subnets \
            --region $REGION \
            --filters "Name=vpc-id,Values=$VPC_ID" \
            --query 'Subnets[*].[SubnetId,CidrBlock,AvailabilityZone]' \
            --output table
    else
        echo "   Danh sách tất cả Subnets:"
        aws ec2 describe-subnets \
            --region $REGION \
            --query 'Subnets[*].[SubnetId,CidrBlock,VpcId,AvailabilityZone]' \
            --output table
    fi
else
    SUBNET_ID=$(echo $SUBNET_INFO | awk '{print $1}')
    echo "✓ Public Subnet ID: $SUBNET_ID"
    echo "  Info: $SUBNET_INFO"
fi

echo ""

# ============================================
# 3. Kiểm tra Security Group
# ============================================
echo "3. Kiểm tra Security Group (sg-0c97b840933fac952)"
echo "---"

SG_INFO=$(aws ec2 describe-security-groups \
    --region $REGION \
    --group-ids sg-0c97b840933fac952 \
    --query 'SecurityGroups[0].[GroupId,GroupName,VpcId]' \
    --output text 2>/dev/null)

if [ -z "$SG_INFO" ]; then
    echo "❌ Không tìm thấy Security Group sg-0c97b840933fac952"
    echo "   Danh sách Security Groups:"
    aws ec2 describe-security-groups \
        --region $REGION \
        --query 'SecurityGroups[*].[GroupId,GroupName,VpcId]' \
        --output table
else
    echo "✓ Security Group: sg-0c97b840933fac952"
    echo "  Info: $SG_INFO"
    
    echo ""
    echo "  Inbound Rules:"
    aws ec2 describe-security-groups \
        --region $REGION \
        --group-ids sg-0c97b840933fac952 \
        --query 'SecurityGroups[0].IpPermissions[*].[IpProtocol,FromPort,ToPort,IpRanges[0].CidrIp]' \
        --output table
fi

echo ""

# ============================================
# 4. Tìm Key Pairs
# ============================================
echo "4. Key Pairs sẵn có"
echo "---"

KEY_PAIRS=$(aws ec2 describe-key-pairs \
    --region $REGION \
    --query 'KeyPairs[*].KeyName' \
    --output text)

if [ -z "$KEY_PAIRS" ]; then
    echo "❌ Không tìm thấy key pairs nào"
    echo "   Vui lòng tạo key pair trước"
else
    echo "✓ Danh sách Key Pairs:"
    aws ec2 describe-key-pairs \
        --region $REGION \
        --query 'KeyPairs[*].[KeyName,KeyType,CreateTime]' \
        --output table
fi

echo ""

# ============================================
# 5. Tìm Ubuntu 24.04 AMI
# ============================================
echo "5. Ubuntu 24.04 LTS AMI"
echo "---"

AMI_INFO=$(aws ec2 describe-images \
    --region $REGION \
    --owners 099720109477 \
    --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-noble-24.04-amd64-server-*" \
    --query 'Images | sort_by(@, &CreationDate) | [-1].[ImageId,Name,CreationDate]' \
    --output text)

if [ -z "$AMI_INFO" ]; then
    echo "❌ Không tìm thấy Ubuntu 24.04 AMI"
    echo "   Tìm các Ubuntu AMI khác:"
    aws ec2 describe-images \
        --region $REGION \
        --owners 099720109477 \
        --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-*-amd64-server-*" \
        --query 'Images | sort_by(@, &CreationDate) | [-5:].[ImageId,Name]' \
        --output table
else
    AMI_ID=$(echo $AMI_INFO | awk '{print $1}')
    echo "✓ Ubuntu 24.04 AMI: $AMI_ID"
    echo "  Info: $AMI_INFO"
fi

echo ""

# ============================================
# 6. Tóm tắt thông tin
# ============================================
echo "=========================================="
echo "TÓM TẮT THÔNG TIN CẦN THIẾT"
echo "=========================================="
echo ""
echo "Cập nhật các biến sau trong script của bạn:"
echo ""
echo "export REGION=\"$REGION\""
echo "export VPC_ID=\"${VPC_ID:-vpc-xxxxxxxxx}\""
echo "export SUBNET_ID=\"${SUBNET_ID:-subnet-xxxxxxxxx}\""
echo "export SECURITY_GROUP=\"sg-0c97b840933fac952\""
echo "export AMI_ID=\"${AMI_ID:-ami-0c6c6be3c4e42b7b0}\""
echo "export KEY_NAME=\"<YOUR_KEY_PAIR_NAME>\""
echo "export INSTANCE_TYPE=\"t3.medium\""
echo ""
echo "=========================================="
echo ""

# ============================================
# 7. Kiểm tra Instance Types có sẵn
# ============================================
echo "7. Kiểm tra Instance Types có sẵn (sample)"
echo "---"
echo "Các instance type thích hợp cho Kubernetes:"
echo "  - t3.medium    (2 vCPU, 4GB RAM) - Dev/Test"
echo "  - t3.large     (2 vCPU, 8GB RAM) - Small Production"
echo "  - m5.large     (2 vCPU, 8GB RAM) - Production"
echo "  - m5.xlarge    (4 vCPU, 16GB RAM) - Heavy Workload"
echo ""

echo "=========================================="
echo "Hoàn thành! Vui lòng cập nhật các biến cần thiết"
echo "=========================================="
