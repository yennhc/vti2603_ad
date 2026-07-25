#!/bin/bash

################################################################################
# Script cấu hình AWS CLI
# Sử dụng: bash k8s-aws-configure.sh
################################################################################

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
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

# Kiểm tra Python
check_python() {
    if ! command -v python3 &> /dev/null; then
        print_error "Python 3 chưa được cài đặt"
        exit 1
    fi
    print_success "Python 3 được cài đặt"
}

# Cài đặt AWS CLI
install_aws_cli() {
    print_header "Cài đặt AWS CLI"
    
    if command -v aws &> /dev/null; then
        print_warning "AWS CLI đã được cài đặt"
        aws --version
        return
    fi
    
    print_info "Cài đặt AWS CLI..."
    pip3 install --upgrade awscli
    
    print_success "AWS CLI đã được cài đặt"
    aws --version
}

# Cấu hình AWS credentials
configure_aws_credentials() {
    print_header "Cấu hình AWS Credentials"
    
    print_info "Nhập AWS credentials của bạn"
    echo ""
    echo "Để lấy AWS credentials:"
    echo "1. Truy cập: https://console.aws.amazon.com/iam/home"
    echo "2. Chọn 'Users' -> tên user của bạn"
    echo "3. Chọn 'Security credentials' tab"
    echo "4. Tạo hoặc copy 'Access key' và 'Secret access key'"
    echo ""
    
    aws configure
    
    print_success "AWS credentials đã được cấu hình"
}

# Kiểm tra AWS connection
test_aws_connection() {
    print_header "Kiểm tra AWS Connection"
    
    if aws sts get-caller-identity &> /dev/null; then
        print_success "AWS connection hoạt động"
        echo ""
        aws sts get-caller-identity
    else
        print_error "AWS connection thất bại"
        print_warning "Vui lòng kiểm tra lại credentials"
        exit 1
    fi
}

# Cài đặt Ansible
install_ansible() {
    print_header "Cài đặt Ansible"
    
    if command -v ansible &> /dev/null; then
        print_warning "Ansible đã được cài đặt"
        ansible --version
        return
    fi
    
    print_info "Cài đặt Ansible và dependencies..."
    
    # Ubuntu/Debian
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [ "$ID" = "ubuntu" ] || [ "$ID" = "debian" ]; then
            sudo apt update
            sudo apt install -y ansible git python3-pip
        fi
    fi
    
    print_success "Ansible đã được cài đặt"
    ansible --version
}

# Cài đặt git
install_git() {
    print_header "Kiểm tra Git"
    
    if command -v git &> /dev/null; then
        print_warning "Git đã được cài đặt"
        return
    fi
    
    print_info "Cài đặt Git..."
    sudo apt update
    sudo apt install -y git
    
    print_success "Git đã được cài đặt"
}

# Tóm tắt
print_summary() {
    print_header "Cấu Hình Hoàn Thành"
    
    echo "Các tools đã được cài đặt:"
    echo "============================="
    
    if command -v aws &> /dev/null; then
        echo "✓ AWS CLI: $(aws --version)"
    fi
    
    if command -v ansible &> /dev/null; then
        echo "✓ Ansible: $(ansible --version | head -1)"
    fi
    
    if command -v git &> /dev/null; then
        echo "✓ Git: $(git --version)"
    fi
    
    if command -v python3 &> /dev/null; then
        echo "✓ Python 3: $(python3 --version)"
    fi
    
    echo ""
    echo "Bước tiếp theo:"
    echo "==============="
    echo "1. Đảm bảo script k8s-aws-setup.sh có quyền thực thi:"
    echo "   chmod +x k8s-aws-setup.sh"
    echo ""
    echo "2. Chạy script setup:"
    echo "   bash k8s-aws-setup.sh"
    echo ""
}

# Main
main() {
    print_header "AWS Kubernetes Setup - Prerequisites Configuration"
    
    check_python
    install_aws_cli
    install_ansible
    install_git
    configure_aws_credentials
    test_aws_connection
    print_summary
}

main "$@"
