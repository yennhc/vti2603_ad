# Lab Triển khai AWS EKS - Hướng dẫn Chi tiết

## 📋 Mục lục

1. [Giới thiệu](#giới-thiệu)
2. [Yêu cầu tiên quyết](#yêu-cầu-tiên-quyết)
3. [Kiến trúc Lab](#kiến-trúc-lab)
4. [Thời gian thực hiện](#thời-gian-thực-hiện)
5. [Các Phase](#các-phase)
6. [Troubleshooting](#troubleshooting)
7. [Chi phí ước tính](#chi-phí-ước-tính)

---

## Giới thiệu

Lab này hướng dẫn triển khai một cluster **AWS EKS** hoàn chỉnh với:
- ✅ Network infrastructure (VPC, Subnets, IGW, NAT)
- ✅ EKS Cluster control plane
- ✅ Managed Node Groups + Fargate Profiles
- ✅ Storage (EBS, EFS)
- ✅ Load Balancing (ALB/NLB)
- ✅ Monitoring (CloudWatch, Container Insights)
- ✅ Sample Applications (3-tier architecture)
- ✅ Security & RBAC
- ✅ High Availability & Scaling tests

---

## Yêu cầu tiên quyết

### Kiến thức cơ bản
- ✓ Kubernetes cơ bản (Pods, Deployments, Services)
- ✓ AWS cơ bản (EC2, VPC, IAM)
- ✓ Linux command line
- ✓ YAML syntax

### Tools cần cài đặt

```bash
# 1. AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
aws --version

# 2. kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
kubectl version --client

# 3. helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version

# 4. eksctl (optional but recommended)
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin
eksctl version

# 5. jq (JSON parser)
sudo apt-get install -y jq

# 6. Terraform (optional)
wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
unzip terraform_1.6.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/
terraform version
```

### AWS Account Setup

```bash
# 1. Configure AWS credentials
aws configure
# Input:
# AWS Access Key ID: <your-key>
# AWS Secret Access Key: <your-secret>
# Default region: ap-southeast-1
# Default output format: json

# 2. Verify credentials
aws sts get-caller-identity

# 3. Create IAM user for lab (recommended)
aws iam create-user --user-name eks-lab-user
aws iam attach-user-policy --user-name eks-lab-user --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

# 4. Create access keys
aws iam create-access-key --user-name eks-lab-user
# Save the access key and secret key

# 5. Configure new profile
aws configure --profile eks-lab
# Then use: --profile eks-lab in commands
```

---

## Kiến trúc Lab

```
VPC (10.0.0.0/16)
├── Public Subnets
│   ├── Public-SN-1: 10.0.1.0/24 (ap-southeast-1a)
│   └── Public-SN-2: 10.0.2.0/24 (ap-southeast-1b)
│       └── IGW + NAT Gateway
│
├── Private Subnets
│   ├── Private-SN-1: 10.0.10.0/24 (ap-southeast-1a)
│   │   └── Node-1, Node-2
│   └── Private-SN-2: 10.0.11.0/24 (ap-southeast-1b)
│       └── Node-3 + Fargate
│
└── EKS Cluster
    ├── Control Plane (AWS Managed)
    ├── Managed Node Group (3 nodes, auto-scale 2-5)
    └── Fargate Profile (serverless pods)

Applications
├── Frontend (Node.js) - LoadBalancer → ALB
├── Backend (Python Flask) - ClusterIP
└── Database (PostgreSQL) - StatefulSet + EBS PVC
```

---

## Thời gian thực hiện

| Phase | Tên | Thời gian | Ghi chú |
|-------|-----|----------|--------|
| 1 | Prerequisites | 30 min | Setup tools & AWS account |
| 2 | Create EKS Cluster | 15 min | Actual creation takes 10-15 min |
| 3 | Add Node Groups | 10 min | Actual creation takes 5-10 min |
| 4 | Configure Cluster | 20 min | Install add-ons, RBAC, storage |
| 5 | Deploy Applications | 20 min | Deploy 3-tier app |
| 6 | Testing & Validation | 30 min | Run all validation tests |
| **Total** | | **~125 min (2h 5min)** | Excluding wait times |

---

## Các Phase

### Phase 1: Prerequisites & Planning
**File**: `phase-1-prerequisites.sh`

Tạo VPC, subnets, security groups, IAM roles

```bash
bash scripts/phase-1-prerequisites.sh
```

**Output**:
- VPC ID
- Subnet IDs (public & private)
- Security Group IDs
- IAM Role ARNs

---

### Phase 2: Create EKS Cluster
**File**: `phase-2-create-cluster.sh`

Tạo EKS cluster control plane

```bash
bash scripts/phase-2-create-cluster.sh
# Wait 10-15 minutes...
```

**Output**:
- Cluster Name: `eks-lab-cluster`
- Endpoint: `https://xxxxx.eks.amazonaws.com`
- Status: ACTIVE

---

### Phase 3: Add Node Groups
**File**: `phase-3-add-nodegroups.sh`

Tạo managed node group + Fargate profile

```bash
bash scripts/phase-3-add-nodegroups.sh
# Wait 5-10 minutes...
```

**Output**:
- Node Group: `primary-nodes` (3 nodes)
- Fargate Profile: `fargate-profile`
- All nodes READY

---

### Phase 4: Configure Cluster
**File**: `phase-4-configure-cluster.sh`

Cấu hình add-ons, RBAC, storage

```bash
bash scripts/phase-4-configure-cluster.sh
```

**Output**:
- Add-ons installed (VPC CNI, CoreDNS, kube-proxy)
- Storage classes created
- RBAC configured
- CloudWatch logging enabled

---

### Phase 5: Deploy Applications
**File**: `phase-5-deploy-applications.sh`

Deploy sample 3-tier application

```bash
bash scripts/phase-5-deploy-applications.sh
```

**Output**:
- Deployment created
- Services configured
- Load Balancer IP assigned
- Database initialized

---

### Phase 6: Testing & Validation
**File**: `phase-6-validation-tests.sh`

Chạy toàn bộ validation tests

```bash
bash scripts/phase-6-validation-tests.sh
```

**Output**:
- All tests PASSED ✓
- Ready for production use

---

## Troubleshooting

### Lỗi phổ biến

#### 1. "ResourceLimitExceeded"
```bash
# Nguyên nhân: VPC đạt giới hạn
# Giải pháp:
aws ec2 describe-vpcs --filters Name=tag:Name,Values=eks-lab-vpc

# Xóa VPC cũ nếu cần
aws ec2 delete-vpc --vpc-id vpc-xxxxx
```

#### 2. "InsufficientFreeAddressesInSubnet"
```bash
# Nguyên nhân: Subnet không đủ IP cho pods
# Giải pháp: Expand subnet
# Edit phase-1-prerequisites.sh, change:
# PRIVATE_SUBNET_1_CIDR="10.0.10.0/24" → "10.0.0.0/21"
```

#### 3. Nodes không sẵn sàng (NotReady)
```bash
# Kiểm tra node status
kubectl get nodes -o wide

# Kiểm tra logs
kubectl logs -n kube-system -l k8s-app=aws-node

# Restart VPC CNI
kubectl rollout restart daemonset -n kube-system aws-node
```

#### 4. Pod pending (không schedule)
```bash
# Kiểm tra describe pod
kubectl describe pod <pod-name>

# Kiểm tra node capacity
kubectl top nodes

# Kiểm tra resource requests/limits
kubectl get pods -o custom-columns=NAME:.metadata.name,CPU:.spec.containers[].resources.requests.cpu,MEMORY:.spec.containers[].resources.requests.memory
```

#### 5. ALB không gán External IP
```bash
# Kiểm tra AWS Load Balancer Controller
kubectl get svc -n kube-system | grep alb

# Cài đặt nếu chưa có
helm repo add eks https://aws.github.io/eks-charts
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=eks-lab-cluster
```

---

## Chi phí ước tính

### Monthly Cost (ap-southeast-1)

| Thành phần | Chi phí | Ghi chú |
|-----------|--------|--------|
| EKS Cluster Control Plane | $73.00 | $0.10/hour |
| EC2 t3.medium (3 nodes) | $65.00 | 730h × $0.0296 |
| Data transfer | $15.00 | Estimate |
| EBS volumes (20GB × 3) | $3.00 | $0.05/GB |
| Load Balancer (ALB) | $16.00 | $0.005/hour + requests |
| **Total** | **~$172/month** | Production use may vary |

### Savings Tips
- ✓ Sử dụng t3.small thay vì t3.medium (-50%)
- ✓ Sử dụng Spot Instances (-70%)
- ✓ Sử dụng Fargate chỉ cho non-critical pods
- ✓ Delete cluster khi không dùng

---

## Quick Start

```bash
# Clone lab repository
git clone https://github.com/your-repo/eks-lab.git
cd eks-lab

# Phase 1-6 tự động
./run-all-phases.sh

# Hoặc chạy từng phase
cd scripts
bash phase-1-prerequisites.sh      # 30 min
bash phase-2-create-cluster.sh     # 15 min (wait 10-15 min)
bash phase-3-add-nodegroups.sh     # 10 min (wait 5-10 min)
bash phase-4-configure-cluster.sh  # 20 min
bash phase-5-deploy-applications.sh # 20 min
bash phase-6-validation-tests.sh   # 30 min

# Cleanup
bash cleanup.sh
```

---

## Tham khảo thêm

- [AWS EKS Documentation](https://docs.aws.amazon.com/eks/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [AWS CLI Reference](https://docs.aws.amazon.com/cli/latest/userguide/)
- [eksctl Documentation](https://eksctl.io/)

---

**Tác giả**: Your Name  
**Ngày**: 2024  
**Phiên bản**: 1.0

