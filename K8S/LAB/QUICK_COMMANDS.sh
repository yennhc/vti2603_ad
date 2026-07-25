#!/bin/bash

# =====================================================
# AWS CLI Quick Commands - Tạo 3 EC2 Instances
# Region: ap-southeast-1
# OS: Ubuntu 24.04 LTS
# =====================================================

# ============ CẬP NHẬT CÁC GIỚI HẠN ============
# Thay thế các giá trị sau:
# - SUBNET_ID: subnet-xxxxx
# - KEY_NAME: your-key-pair-name
# - VPC_ID: vpc-xxxxx (nếu cần)
# =====================================================

# Đặt các biến
REGION="ap-southeast-1"
SECURITY_GROUP="sg-0c97b840933fac952"
SUBNET_ID="subnet-xxxxx"                    # ⚠️ THAY ĐỔI
KEY_NAME="your-key-pair-name"               # ⚠️ THAY ĐỔI
AMI_ID="ami-03acbba64aef9bf5c"             # Ubuntu 24.04 LTS
INSTANCE_TYPE="t3.medium"

# ============================================
# LỆNH 1: Tạo k8s-master
# ============================================
echo "Creating k8s-master..."

aws ec2 run-instances \
    --region $REGION \
    --image-id $AMI_ID \
    --instance-type $INSTANCE_TYPE \
    --key-name $KEY_NAME \
    --security-group-ids $SECURITY_GROUP \
    --subnet-id $SUBNET_ID \
    --private-ip-address 172.19.1.10 \
    --associate-public-ip-address \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=k8s-master},{Key=Role,Value=master}]' \
    --query 'Instances[0].[InstanceId,PrivateIpAddress]' \
    --output text

sleep 2

# ============================================
# LỆNH 2: Tạo node1
# ============================================
echo "Creating node1..."

aws ec2 run-instances \
    --region $REGION \
    --image-id $AMI_ID \
    --instance-type $INSTANCE_TYPE \
    --key-name $KEY_NAME \
    --security-group-ids $SECURITY_GROUP \
    --subnet-id $SUBNET_ID \
    --private-ip-address 172.19.1.11 \
    --associate-public-ip-address \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=node1},{Key=Role,Value=worker}]' \
    --query 'Instances[0].[InstanceId,PrivateIpAddress]' \
    --output text

sleep 2

# ============================================
# LỆNH 3: Tạo node2
# ============================================
echo "Creating node2..."

aws ec2 run-instances \
    --region $REGION \
    --image-id $AMI_ID \
    --instance-type $INSTANCE_TYPE \
    --key-name $KEY_NAME \
    --security-group-ids $SECURITY_GROUP \
    --subnet-id $SUBNET_ID \
    --private-ip-address 172.19.1.12 \
    --associate-public-ip-address \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=node2},{Key=Role,Value=worker}]' \
    --query 'Instances[0].[InstanceId,PrivateIpAddress]' \
    --output text

sleep 2

# ============================================
# LỆNH 4: Kiểm tra trạng thái instances
# ============================================
echo ""
echo "Checking instance status..."
echo ""

aws ec2 describe-instances \
    --region $REGION \
    --filters "Name=tag:Name,Values=k8s-master,node1,node2" \
    --query 'Reservations[*].Instances[*].[Tags[?Key==`Name`].Value|[0],InstanceId,State.Name,PrivateIpAddress,PublicIpAddress]' \
    --output table

# ============================================
# LỆNH 5: Chờ instances khởi động
# ============================================
echo ""
echo "Waiting for instances to be running..."

aws ec2 wait instance-running \
    --region $REGION \
    --filters "Name=tag:Name,Values=k8s-master,node1,node2"

echo "✓ All instances are running!"

# ============================================
# LỆNH 6: Chờ status checks
# ============================================
echo ""
echo "Waiting for status checks to pass..."

aws ec2 wait instance-status-ok \
    --region $REGION \
    --filters "Name=tag:Name,Values=k8s-master,node1,node2"

echo "✓ All instances passed status checks!"

# ============================================
# LỆNH 7: Lấy thông tin kết nối SSH
# ============================================
echo ""
echo "SSH Connection Information:"
echo "============================="
echo ""

aws ec2 describe-instances \
    --region $REGION \
    --filters "Name=tag:Name,Values=k8s-master,node1,node2" \
    --query 'Reservations[*].Instances[*].[Tags[?Key==`Name`].Value|[0],PublicIpAddress,PrivateIpAddress]' \
    --output table

echo ""
echo "Connect with:"
echo "ssh -i /path/to/your/key.pem ubuntu@<PUBLIC_IP>"
echo ""

# ============================================
# OPTIONAL: Xóa instances (nếu cần)
# ============================================
# Uncomment để xóa tất cả instances
# echo "Terminating instances..."
# 
# INSTANCE_IDS=$(aws ec2 describe-instances \
#     --region $REGION \
#     --filters "Name=tag:Name,Values=k8s-master,node1,node2" \
#     --query 'Reservations[*].Instances[*].InstanceId' \
#     --output text)
# 
# aws ec2 terminate-instances \
#     --region $REGION \
#     --instance-ids $INSTANCE_IDS
# 
# echo "✓ Instances terminated!"
