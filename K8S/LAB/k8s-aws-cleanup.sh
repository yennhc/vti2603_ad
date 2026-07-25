#!/bin/bash

################################################################################
# Script dọn dẹp (cleanup) AWS resources
# Sử dụng: bash k8s-aws-cleanup.sh
################################################################################

set -e

# Configuration
AWS_REGION="us-east-1"
KEY_NAME="k8s-key-pair"
KEY_PATH="$HOME/.ssh/$KEY_NAME.pem"
SG_NAME="k8s-cluster-sg"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "\n${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC} $1"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Xóa EC2 Instances
terminate_instances() {
    print_header "Xóa EC2 Instances"
    
    INSTANCE_IDS=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=k8s-node" "Name=instance-state-name,Values=running,stopped" \
        --region "$AWS_REGION" \
        --query 'Reservations[*].Instances[*].InstanceId' \
        --output text)
    
    if [ -z "$INSTANCE_IDS" ]; then
        print_warning "Không tìm thấy instances"
        return
    fi
    
    print_info "Xóa instances: $INSTANCE_IDS"
    aws ec2 terminate-instances \
        --instance-ids $INSTANCE_IDS \
        --region "$AWS_REGION" > /dev/null
    
    print_info "Chờ instances bị xóa (~1-2 phút)..."
    aws ec2 wait instance-terminated \
        --instance-ids $INSTANCE_IDS \
        --region "$AWS_REGION"
    
    print_success "EC2 Instances đã bị xóa"
}

# Xóa Elastic IPs
release_elastic_ips() {
    print_header "Xóa Elastic IPs"
    
    ALLOC_IDS=$(aws ec2 describe-addresses \
        --region "$AWS_REGION" \
        --filters "Name=instance-id,Values=" \
        --query 'Addresses[*].AllocationId' \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$ALLOC_IDS" ]; then
        print_warning "Không tìm thấy Elastic IPs"
        return
    fi
    
    for alloc_id in $ALLOC_IDS; do
        print_info "Xóa Elastic IP: $alloc_id"
        aws ec2 release-address \
            --allocation-id "$alloc_id" \
            --region "$AWS_REGION" > /dev/null 2>&1 || true
    done
    
    print_success "Elastic IPs đã bị xóa"
}

# Xóa Security Group
delete_security_group() {
    print_header "Xóa Security Group"
    
    # Chờ instances hoàn toàn bị xóa
    print_info "Chờ 15 giây để instances hoàn toàn bị xóa..."
    sleep 15
    
    SG_ID=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=$SG_NAME" \
        --region "$AWS_REGION" \
        --query 'SecurityGroups[0].GroupId' \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$SG_ID" ] || [ "$SG_ID" = "None" ]; then
        print_warning "Security group không tồn tại"
        return
    fi
    
    print_info "Xóa Security Group: $SG_ID"
    aws ec2 delete-security-group \
        --group-id "$SG_ID" \
        --region "$AWS_REGION" > /dev/null
    
    print_success "Security Group đã bị xóa"
}

# Xóa SSH Key Pair
delete_key_pair() {
    print_header "Xóa SSH Key Pair"
    
    print_info "Xóa key pair từ AWS: $KEY_NAME"
    aws ec2 delete-key-pair \
        --key-name "$KEY_NAME" \
        --region "$AWS_REGION" > /dev/null
    
    if [ -f "$KEY_PATH" ]; then
        print_info "Xóa local key file: $KEY_PATH"
        rm -f "$KEY_PATH"
    fi
    
    print_success "SSH Key Pair đã bị xóa"
}

# Xóa local Kubespray files (tùy chọn)
cleanup_local_files() {
    print_header "Dọn dẹp Local Files"
    
    read -p "Xóa Kubespray folder? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if [ -d "kubespray" ]; then
            print_info "Xóa kubespray folder..."
            rm -rf kubespray
            print_success "Kubespray folder đã bị xóa"
        fi
    fi
    
    if [ -f "/tmp/instance_info.txt" ]; then
        rm -f "/tmp/instance_info.txt"
    fi
}

# Main function
main() {
    print_header "AWS Kubernetes Cleanup"
    
    read -p "Xác nhận xóa tất cả AWS resources? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Cleanup bị hủy"
        exit 0
    fi
    
    terminate_instances
    release_elastic_ips
    delete_security_group
    delete_key_pair
    cleanup_local_files
    
    print_header "Cleanup Hoàn Thành"
    print_success "Tất cả AWS resources đã bị xóa"
}

main "$@"
