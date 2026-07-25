# Hướng Dẫn Tạo 3 EC2 Instances bằng AWS CLI

## 📋 Thông Tin Cấu Hình
- **Region**: ap-southeast-1
- **OS**: Ubuntu 24.04 LTS
- **VPC**: 172.19.0.0/16
- **Public Subnet**: 172.19.1.0/24
- **Security Group**: sg-0c97b840933fac952
- **Public IP**: Có
- **Hostnames**: k8s-master, node1, node2
- **Private IPs**: 172.19.1.10, 172.19.1.11, 172.19.1.12

---

## 🔧 Bước 1: Chuẩn Bị Thông Tin Cần Thiết

### 1.1 Tìm VPC ID
```bash
aws ec2 describe-vpcs \
    --region ap-southeast-1 \
    --filters "Name=cidr,Values=172.19.0.0/16" \
    --query 'Vpcs[0].VpcId' \
    --output text
```
**Kết quả ghi nhớ**: `vpc-xxxxxxxxx`

### 1.2 Tìm Subnet ID
```bash
aws ec2 describe-subnets \
    --region ap-southeast-1 \
    --filters "Name=cidr-block,Values=172.19.1.0/24" \
    --query 'Subnets[0].SubnetId' \
    --output text
```
**Kết quả ghi nhớ**: `subnet-xxxxxxxxx`

### 1.3 Kiểm tra Security Group
```bash
aws ec2 describe-security-groups \
    --region ap-southeast-1 \
    --group-ids sg-0c97b840933fac952 \
    --query 'SecurityGroups[0]' \
    --output table
```

### 1.4 Tìm Ubuntu 24.04 AMI ID
```bash
aws ec2 describe-images \
    --region ap-southeast-1 \
    --owners 099720109477 \
    --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-noble-24.04-amd64-server-*" \
    --query 'Images | sort_by(@, &CreationDate) | [-1].[ImageId,Name]' \
    --output table
```

### 1.5 Kiểm tra Key Pair
```bash
aws ec2 describe-key-pairs \
    --region ap-southeast-1 \
    --query 'KeyPairs[*].KeyName' \
    --output table
```

---

## 📝 Bước 2: Đặt Biến Môi Trường

```bash
# Thay thế các giá trị xxxx bằng kết quả thực tế
export AWS_REGION="ap-southeast-1"
export VPC_ID="vpc-xxxxx"
export SUBNET_ID="subnet-xxxxx"
export SECURITY_GROUP="sg-0c97b840933fac952"
export AMI_ID="ami-0c6c6be3c4e42b7b0"  # Ubuntu 24.04 LTS
export KEY_NAME="your-key-pair-name"
export INSTANCE_TYPE="t3.medium"
```

---

## 🚀 Bước 3: Tạo 3 EC2 Instances

### 3.1 Tạo Instance 1: k8s-master
```bash
aws ec2 run-instances \
    --region $AWS_REGION \
    --image-id $AMI_ID \
    --instance-type $INSTANCE_TYPE \
    --key-name $KEY_NAME \
    --security-group-ids $SECURITY_GROUP \
    --subnet-id $SUBNET_ID \
    --private-ip-address 172.19.1.10 \
    --associate-public-ip-address \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=k8s-master}]' \
    --user-data file:///tmp/k8s-master-userdata.sh \
    --query 'Instances[0].[InstanceId,PrivateIpAddress,PublicIpAddress]' \
    --output table
```

### 3.2 Tạo Instance 2: node1
```bash
aws ec2 run-instances \
    --region $AWS_REGION \
    --image-id $AMI_ID \
    --instance-type $INSTANCE_TYPE \
    --key-name $KEY_NAME \
    --security-group-ids $SECURITY_GROUP \
    --subnet-id $SUBNET_ID \
    --private-ip-address 172.19.1.11 \
    --associate-public-ip-address \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=node1}]' \
    --user-data file:///tmp/node-userdata.sh \
    --query 'Instances[0].[InstanceId,PrivateIpAddress,PublicIpAddress]' \
    --output table
```

### 3.3 Tạo Instance 3: node2
```bash
aws ec2 run-instances \
    --region $AWS_REGION \
    --image-id $AMI_ID \
    --instance-type $INSTANCE_TYPE \
    --key-name $KEY_NAME \
    --security-group-ids $SECURITY_GROUP \
    --subnet-id $SUBNET_ID \
    --private-ip-address 172.19.1.12 \
    --associate-public-ip-address \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=node2}]' \
    --user-data file:///tmp/node-userdata.sh \
    --query 'Instances[0].[InstanceId,PrivateIpAddress,PublicIpAddress]' \
    --output table
```

---

## 📊 Bước 4: Kiểm Tra Trạng Thái Instances

### 4.1 Xem tất cả instances vừa tạo
```bash
aws ec2 describe-instances \
    --region $AWS_REGION \
    --filters "Name=tag:Name,Values=k8s-master,node1,node2" \
    --query 'Reservations[*].Instances[*].[Tags[?Key==`Name`].Value|[0],InstanceId,InstanceType,State.Name,PrivateIpAddress,PublicIpAddress]' \
    --output table
```

### 4.2 Chờ instances khởi động hoàn toàn
```bash
aws ec2 wait instance-running \
    --region $AWS_REGION \
    --filters "Name=tag:Name,Values=k8s-master,node1,node2"

echo "✓ Tất cả instances đã khởi động!"
```

### 4.3 Chờ status checks hoàn thành
```bash
aws ec2 wait instance-status-ok \
    --region $AWS_REGION \
    --filters "Name=tag:Name,Values=k8s-master,node1,node2"

echo "✓ Tất cả instances sẵn sàng!"
```

---

## 🔌 Bước 5: Kết Nối SSH đến Instances

```bash
# Lấy Public IP của k8s-master
MASTER_IP=$(aws ec2 describe-instances \
    --region $AWS_REGION \
    --filters "Name=tag:Name,Values=k8s-master" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)

# Kết nối SSH
ssh -i /path/to/your/key.pem ubuntu@$MASTER_IP

# Hoặc lấy tất cả IPs
aws ec2 describe-instances \
    --region $AWS_REGION \
    --filters "Name=tag:Name,Values=k8s-master,node1,node2" \
    --query 'Reservations[*].Instances[*].[Tags[?Key==`Name`].Value|[0],PublicIpAddress]' \
    --output table
```

---

## 🛠️ User Data Scripts

### k8s-master-userdata.sh
```bash
#!/bin/bash
hostnamectl set-hostname k8s-master
echo "127.0.0.1 k8s-master" >> /etc/hosts

# Cập nhật hệ thống
apt-get update
apt-get upgrade -y

# Cài đặt Docker
apt-get install -y curl
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh

# Thêm user ubuntu vào docker group
usermod -aG docker ubuntu
```

### node-userdata.sh (cho node1 và node2)
```bash
#!/bin/bash
# Thay thế NODE_NAME bằng node1 hoặc node2 tương ứng
hostnamectl set-hostname NODE_NAME
echo "127.0.0.1 NODE_NAME" >> /etc/hosts

# Cập nhật hệ thống
apt-get update
apt-get upgrade -y

# Cài đặt Docker
apt-get install -y curl
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh

# Thêm user ubuntu vào docker group
usermod -aG docker ubuntu
```

---

## 🗑️ Xóa Instances (Nếu cần)

```bash
# Lấy Instance IDs
INSTANCE_IDS=$(aws ec2 describe-instances \
    --region $AWS_REGION \
    --filters "Name=tag:Name,Values=k8s-master,node1,node2" \
    --query 'Reservations[*].Instances[*].InstanceId' \
    --output text)

# Terminate instances
aws ec2 terminate-instances \
    --region $AWS_REGION \
    --instance-ids $INSTANCE_IDS

echo "✓ Instances đã được xóa"
```

---

## 💡 Lưu Ý Quan Trọng

1. **Key Pair**: Đảm bảo bạn đã có key pair AWS
2. **IAM Permissions**: Tài khoản AWS cần quyền EC2
3. **AMI ID**: Thay đổi AMI ID theo region của bạn
4. **Instance Type**: t3.medium thích hợp cho Kubernetes, có thể nâng cấp tùy nhu cầu
5. **Network**: Kiểm tra VPC và Subnet đã tồn tại
6. **Security Group**: Đảm bảo security group cho phép incoming traffic cần thiết

---

## 📞 Troubleshooting

```bash
# Kiểm tra lỗi khi tạo instances
aws ec2 describe-instances --region ap-southeast-1 --query 'Reservations[*].Instances[*].StateTransitionReason'

# Xem chi tiết instance
aws ec2 describe-instances --region ap-southeast-1 --instance-ids i-xxxxxxxxx

# Xem console output
aws ec2 get-console-output --region ap-southeast-1 --instance-id i-xxxxxxxxx
```
