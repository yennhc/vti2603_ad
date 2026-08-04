# Lab EKS Cơ Bản - Tạo và Deploy Ứng Dụng Đơn Giản

## Mục Tiêu Lab
- Hiểu được EKS là gì và cách thức hoạt động
- Tạo một EKS cluster trên AWS
- Cấu hình kubectl để quản lý cluster
- Deploy một ứng dụng Kubernetes đơn giản
- Truy cập và kiểm tra ứng dụng
- Dọn dẹp tài nguyên sau khi hoàn thành

---

## 1. Kiến Thức Cơ Bản

### EKS là gì?
**EKS (Elastic Kubernetes Service)** là dịch vụ Kubernetes được quản lý bởi AWS. AWS sẽ chịu trách nhiệm quản lý control plane (API server, etcd, scheduler, controller-manager), còn bạn sẽ quản lý worker nodes.

### Thành phần chính:
- **Control Plane**: Được quản lý bởi AWS (không cần tự cấu hình)
- **Worker Nodes**: EC2 instances mà bạn tạo để chạy các pods
- **VPC/Networking**: EKS cluster phải chạy trong một VPC
- **IAM Roles**: Để xác thực giữa các dịch vụ AWS

---

## 2. Chuẩn Bị Trước Lab

### 2.1 Yêu Cầu
- Tài khoản AWS với quyền tạo EKS, EC2, VPC, IAM
- Đã cấu hình AWS CLI trên máy tính (hoặc sử dụng AWS CloudShell)
- Cài đặt kubectl
- Cài đặt eksctl (optional nhưng rất tiện)

### 2.2 Cài đặt công cụ

**Cài đặt AWS CLI** (nếu chưa có):
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

**Cài đặt kubectl**:
```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
kubectl version --client
```

**Cài đặt eksctl** (optional - giúp tạo cluster nhanh hơn):
```bash
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin
eksctl version
```

### 2.3 Cấu hình AWS Credentials
```bash
aws configure
# Nhập: AWS Access Key ID, AWS Secret Access Key, Default region (ví dụ: ap-southeast-1)
```

---

## 3. Tạo VPC và IAM Roles

Mặc dù eksctl có thể tự động tạo, ta sẽ tạo thủ công để hiểu rõ hơn.

### 3.1 Tạo IAM Role cho EKS Cluster

**Tạo trust policy file** (`eks-trust-policy.json`):
```json
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
```

**Tạo IAM Role**:
```bash
aws iam create-role \
  --role-name eks-cluster-role \
  --assume-role-policy-document file://eks-trust-policy.json
```

**Gắn policy vào role**:
```bash
aws iam attach-role-policy \
  --role-name eks-cluster-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
```

### 3.2 Tạo IAM Role cho Worker Nodes

**Tạo trust policy file** (`eks-node-trust-policy.json`):
```json
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
```

**Tạo IAM Role**:
```bash
aws iam create-role \
  --role-name eks-node-role \
  --assume-role-policy-document file://eks-node-trust-policy.json
```

**Gắn policies vào role**:
```bash
aws iam attach-role-policy \
  --role-name eks-node-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy

aws iam attach-role-policy \
  --role-name eks-node-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy

aws iam attach-role-policy \
  --role-name eks-node-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
```

### 3.3 Tạo VPC và Subnets

**Tạo VPC**:
```bash
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block 10.0.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=eks-vpc}]' \
  --query 'Vpc.VpcId' \
  --output text)

echo "VPC ID: $VPC_ID"
```

**Bật DNS hostname**:
```bash
aws ec2 modify-vpc-attribute \
  --vpc-id $VPC_ID \
  --enable-dns-hostnames
```

**Tạo Internet Gateway**:
```bash
IGW_ID=$(aws ec2 create-internet-gateway \
  --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=eks-igw}]' \
  --query 'InternetGateway.InternetGatewayId' \
  --output text)

aws ec2 attach-internet-gateway \
  --internet-gateway-id $IGW_ID \
  --vpc-id $VPC_ID

echo "IGW ID: $IGW_ID"
```

**Tạo Public Subnets** (2 subnets ở 2 AZ khác nhau):
```bash
# Subnet 1
SUBNET1_ID=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.1.0/24 \
  --availability-zone ap-southeast-1a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=eks-subnet-1}]' \
  --query 'Subnet.SubnetId' \
  --output text)

# Subnet 2
SUBNET2_ID=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.2.0/24 \
  --availability-zone ap-southeast-1b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=eks-subnet-2}]' \
  --query 'Subnet.SubnetId' \
  --output text)

echo "Subnet 1 ID: $SUBNET1_ID"
echo "Subnet 2 ID: $SUBNET2_ID"
```

**Tạo Route Table và Routes**:
```bash
RT_ID=$(aws ec2 create-route-table \
  --vpc-id $VPC_ID \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=eks-rt}]' \
  --query 'RouteTable.RouteTableId' \
  --output text)

aws ec2 create-route \
  --route-table-id $RT_ID \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id $IGW_ID

aws ec2 associate-route-table \
  --subnet-id $SUBNET1_ID \
  --route-table-id $RT_ID

aws ec2 associate-route-table \
  --subnet-id $SUBNET2_ID \
  --route-table-id $RT_ID

echo "Route Table ID: $RT_ID"
```

**Tạo Security Group**:
```bash
SG_ID=$(aws ec2 create-security-group \
  --group-name eks-sg \
  --description "Security group for EKS cluster" \
  --vpc-id $VPC_ID \
  --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=eks-sg}]' \
  --query 'GroupId' \
  --output text)

# Allow inbound traffic from within the VPC
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol all \
  --cidr 10.0.0.0/16

echo "Security Group ID: $SG_ID"
```

> **Lưu lại các IDs này**, bạn sẽ cần chúng ở bước tiếp theo.

---

## 4. Tạo EKS Cluster

### Cách 1: Sử dụng AWS CLI

**Tạo file cấu hình cluster** (`eks-cluster.json`):
```json
{
  "name": "my-eks-cluster",
  "version": "1.28",
  "roleArn": "arn:aws:iam::YOUR_ACCOUNT_ID:role/eks-cluster-role",
  "resourcesVpcConfig": {
    "subnetIds": [
      "SUBNET1_ID",
      "SUBNET2_ID"
    ],
    "securityGroupIds": [
      "SG_ID"
    ],
    "endpointPublicAccess": true,
    "endpointPrivateAccess": false
  },
  "logging": {
    "clusterLogging": [
      {
        "types": ["api", "audit", "authenticator", "controllerManager", "scheduler"],
        "enabled": true
      }
    ]
  }
}
```

**Thay thế các giá trị**:
- `YOUR_ACCOUNT_ID`: Account ID của bạn
- `SUBNET1_ID`, `SUBNET2_ID`: Các subnet IDs từ bước trước
- `SG_ID`: Security Group ID từ bước trước

**Tạo cluster**:
```bash
aws eks create-cluster --cli-input-json file://eks-cluster.json
```

**Kiểm tra trạng thái cluster** (quá trình này mất khoảng 10-15 phút):
```bash
aws eks describe-cluster --name my-eks-cluster --query 'cluster.status'
```

### Cách 2: Sử dụng eksctl (nhanh hơn)

```bash
eksctl create cluster \
  --name my-eks-cluster \
  --version 1.28 \
  --region ap-southeast-1 \
  --nodes 2 \
  --node-type t3.medium \
  --enable-ssm
```

> eksctl sẽ tự động tạo VPC, IAM roles, v.v.

---

## 5. Tạo Worker Nodes

Nếu tạo cluster bằng AWS CLI, bạn cần tạo worker nodes thủ công. Nếu dùng eksctl, nodes sẽ được tạo tự động.

### Tạo Launch Template cho Node Group

**Tạo file cấu hình** (`node-group.json`):
```json
{
  "clusterName": "my-eks-cluster",
  "nodegroupName": "my-node-group",
  "scalingConfig": {
    "minSize": 2,
    "maxSize": 4,
    "desiredSize": 2
  },
  "instanceTypes": ["t3.medium"],
  "subnets": [
    "SUBNET1_ID",
    "SUBNET2_ID"
  ],
  "nodeRole": "arn:aws:iam::YOUR_ACCOUNT_ID:role/eks-node-role",
  "tags": {
    "Environment": "lab"
  }
}
```

**Tạo Node Group**:
```bash
aws eks create-nodegroup --cli-input-json file://node-group.json
```

**Kiểm tra trạng thái Node Group**:
```bash
aws eks describe-nodegroup \
  --cluster-name my-eks-cluster \
  --nodegroup-name my-node-group \
  --query 'nodegroup.status'
```

---

## 6. Cấu Hình kubectl

### 6.1 Update kubeconfig

```bash
aws eks update-kubeconfig \
  --region ap-southeast-1 \
  --name my-eks-cluster
```

### 6.2 Kiểm tra kết nối

```bash
kubectl cluster-info
```

**Output mong đợi**:
```
Kubernetes control plane is running at https://XXXXXXXXX.eks.ap-southeast-1.amazonaws.com
CoreDNS is running at https://XXXXXXXXX.eks.ap-southeast-1.amazonaws.com/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
```

### 6.3 Kiểm tra nodes

```bash
kubectl get nodes -o wide
```

**Output mong đợi**:
```
NAME                                           STATUS   ROLES    AGE   VERSION
ip-10-0-1-xxx.ap-southeast-1.compute.internal   Ready    <none>   5m    v1.28.x
ip-10-0-2-xxx.ap-southeast-1.compute.internal   Ready    <none>   5m    v1.28.x
```

---

## 7. Deploy Ứng Dụng Đơn Giản

### 7.1 Tạo Namespace

```bash
kubectl create namespace demo
```

### 7.2 Deploy Nginx

**Tạo file** `nginx-deployment.yaml`:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  namespace: demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
```

**Deploy**:
```bash
kubectl apply -f nginx-deployment.yaml
```

### 7.3 Tạo Service

**Tạo file** `nginx-service.yaml`:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
  namespace: demo
spec:
  type: LoadBalancer
  selector:
    app: nginx
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
```

**Deploy**:
```bash
kubectl apply -f nginx-service.yaml
```

### 7.4 Kiểm tra Deployment

```bash
# Kiểm tra pods
kubectl get pods -n demo

# Kiểm tra service
kubectl get svc -n demo

# Xem chi tiết deployment
kubectl describe deployment nginx-deployment -n demo
```

### 7.5 Truy cập Ứng Dụng

Chờ cho Service có EXTERNAL-IP:
```bash
kubectl get svc -n demo -w
```

Một khi có EXTERNAL-IP, bạn có thể truy cập:
```bash
curl http://EXTERNAL-IP
```

Hoặc mở trong trình duyệt: `http://EXTERNAL-IP`

---

## 8. Kiểm Tra Logs

### Xem logs pod

```bash
# Xem logs của một pod cụ thể
kubectl logs POD_NAME -n demo

# Follow logs (giống tail -f)
kubectl logs -f POD_NAME -n demo
```

### Xem events của cluster

```bash
kubectl get events -n demo
```

---

## 9. Dọn Dẹp Tài Nguyên

### 9.1 Xóa ứng dụng

```bash
kubectl delete namespace demo
```

### 9.2 Xóa Node Group

```bash
aws eks delete-nodegroup \
  --cluster-name my-eks-cluster \
  --nodegroup-name my-node-group
```

Chờ khoảng 5 phút cho nodes bị xóa.

### 9.3 Xóa EKS Cluster

```bash
aws eks delete-cluster --name my-eks-cluster
```

### 9.4 Xóa VPC và các tài nguyên liên quan

```bash
# Xóa Route Table
aws ec2 delete-route-table --route-table-id $RT_ID

# Xóa Subnets
aws ec2 delete-subnet --subnet-id $SUBNET1_ID
aws ec2 delete-subnet --subnet-id $SUBNET2_ID

# Detach Internet Gateway
aws ec2 detach-internet-gateway \
  --internet-gateway-id $IGW_ID \
  --vpc-id $VPC_ID

# Xóa Internet Gateway
aws ec2 delete-internet-gateway --internet-gateway-id $IGW_ID

# Xóa VPC
aws ec2 delete-vpc --vpc-id $VPC_ID

# Xóa Security Group
aws ec2 delete-security-group --group-id $SG_ID
```

### 9.5 Xóa IAM Roles

```bash
# Detach policies từ cluster role
aws iam detach-role-policy \
  --role-name eks-cluster-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy

# Xóa cluster role
aws iam delete-role --role-name eks-cluster-role

# Detach policies từ node role
aws iam detach-role-policy \
  --role-name eks-node-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy

aws iam detach-role-policy \
  --role-name eks-node-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy

aws iam detach-role-policy \
  --role-name eks-node-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly

# Xóa node role
aws iam delete-role --role-name eks-node-role
```

---

## 10. Các Câu Lệnh Hữu Ích

```bash
# Xem tất cả resources trong cluster
kubectl get all -n demo

# Xem deployment chi tiết
kubectl describe deployment nginx-deployment -n demo

# Scale deployment
kubectl scale deployment nginx-deployment --replicas=3 -n demo

# Xóa pod (Kubernetes sẽ tạo pod mới)
kubectl delete pod POD_NAME -n demo

# Xem resource usage
kubectl top nodes
kubectl top pods -n demo

# Port forward (truy cập pod mà không cần LoadBalancer)
kubectl port-forward pod/POD_NAME 8080:80 -n demo
```

---

## 11. Các Lỗi Thường Gặp

| Lỗi | Nguyên Nhân | Giải Pháp |
|-----|-----------|----------|
| `Unable to connect to the server` | Kubeconfig chưa được cấu hình | Chạy `aws eks update-kubeconfig` |
| `Pending` pods | Nodes không đủ tài nguyên | Tăng số nodes hoặc instance type |
| `ImagePullBackOff` | Docker image không tồn tại | Kiểm tra image name và registry |
| `Service có PENDING EXTERNAL-IP` | AWS ELB chưa sẵn sàng | Chờ 2-3 phút |
| `Permission denied` | IAM role không có quyền | Kiểm tra IAM policies |

---

## 12. Tài Liệu Tham Khảo

- AWS EKS Documentation: https://docs.aws.amazon.com/eks/
- Kubernetes Official Docs: https://kubernetes.io/docs/
- eksctl Documentation: https://eksctl.io/

---

## Tóm Tắt Lab

✅ Tạo VPC và networking infrastructure  
✅ Tạo IAM roles cho EKS cluster và worker nodes  
✅ Tạo EKS cluster  
✅ Tạo worker node group  
✅ Cấu hình kubectl để quản lý cluster  
✅ Deploy ứng dụng Nginx  
✅ Truy cập ứng dụng thông qua LoadBalancer  
✅ Dọn dẹp tài nguyên  

Bạn đã hoàn thành lab EKS cơ bản! 🎉
