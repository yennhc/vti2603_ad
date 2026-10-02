# LAB: Xây dựng CI/CD Pipeline trên AWS triển khai ứng dụng lên EKS

**Cấp độ:** Mới bắt đầu (Basic)
**Thời lượng dự kiến:** 3 - 4 giờ
**Ứng dụng mẫu:** `github.com/yennhc/nodejs-cicd-demo`

---

## 1. Mục tiêu bài lab

Sau khi hoàn thành lab, học viên có thể:

- Hiểu luồng CI/CD cơ bản: Source → Build → Deploy
- Tạo và cấu hình cụm **Amazon EKS** bằng `eksctl`
- Build Docker image và đẩy lên **Amazon ECR**
- Cấu hình **AWS CodePipeline** + **CodeBuild** để tự động build và deploy ứng dụng Node.js lên EKS
- Kiểm tra và xử lý một số lỗi thường gặp trong pipeline

---

## 2. Kiến trúc tổng quan

```
GitHub (nodejs-cicd-demo)
        │  (push code)
        ▼
   AWS CodePipeline
        │
   ┌────┴─────┐
   │  Source  │  Lấy code từ GitHub (qua CodeStar Connection)
   └────┬─────┘
        ▼
   ┌──────────┐
   │  Build   │  AWS CodeBuild:
   │          │   - Build Docker image
   │          │   - Push image lên Amazon ECR
   │          │   - Cập nhật kubeconfig
   │          │   - kubectl apply (deploy lên EKS)
   └────┬─────┘
        ▼
   Amazon EKS Cluster
        │
   Pod chạy ứng dụng Node.js (LoadBalancer Service)
```

---

## 3. Chuẩn bị (Prerequisites)

| Yêu cầu | Ghi chú |
|---|---|
| Tài khoản AWS | Có quyền IAM đủ để tạo EKS, ECR, CodePipeline, CodeBuild, IAM Role |
| AWS CLI | Đã cấu hình `aws configure` |
| eksctl | Dùng để tạo cụm EKS nhanh |
| kubectl | Quản lý cụm Kubernetes |
| Docker | Build image (test local, không bắt buộc nếu build hoàn toàn trên CodeBuild) |
| Tài khoản GitHub | Fork/clone repo `nodejs-cicd-demo` |
| Region | Khuyến nghị `ap-southeast-1` (Singapore) |

Cài đặt nhanh trên macOS:

```bash
brew install eksctl kubectl awscli
aws configure
```

---

## 4. Bước 1 — Tạo cụm EKS

```bash
eksctl create cluster \
  --name eks-cicd-lab \
  --region ap-southeast-1 \
  --nodegroup-name eks-cicd-nodes \
  --node-type t3.medium \
  --nodes 2 \
  --nodes-min 2 \
  --nodes-max 3 \
  --managed
```

> ⏳ Bước này mất khoảng 15-20 phút. Trong lúc chờ, có thể chuyển sang Bước 2.

Kiểm tra cụm sau khi tạo xong:

```bash
kubectl get nodes
aws eks update-kubeconfig --name eks-cicd-lab --region ap-southeast-1
```

**Checklist:**
- [ ] Cụm EKS ở trạng thái `ACTIVE`
- [ ] `kubectl get nodes` hiển thị 2 node ở trạng thái `Ready`

---

## 5. Bước 2 — Tạo Amazon ECR Repository

```bash
aws ecr create-repository \
  --repository-name nodejs-cicd-demo \
  --region ap-southeast-1
```

Ghi lại **Repository URI**, ví dụ:
```
<account-id>.dkr.ecr.ap-southeast-1.amazonaws.com/nodejs-cicd-demo
```

---

## 6. Bước 3 — Chuẩn bị repo GitHub

Clone repo mẫu về máy (hoặc dùng lại repo đã có):

```bash
git clone https://github.com/yennhc/nodejs-cicd-demo.git
cd nodejs-cicd-demo
```

Đảm bảo repo có `Dockerfile` ở thư mục gốc. Nếu chưa có, tạo file `Dockerfile`:

```dockerfile
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
EXPOSE 3000
CMD ["node", "server.js"]
```

Tạo file Kubernetes manifest `k8s/deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nodejs-cicd-demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nodejs-cicd-demo
  template:
    metadata:
      labels:
        app: nodejs-cicd-demo
    spec:
      containers:
        - name: nodejs-cicd-demo
          image: <ECR_REPO_URI>:latest
          ports:
            - containerPort: 3000
---
apiVersion: v1
kind: Service
metadata:
  name: nodejs-cicd-demo-svc
spec:
  type: LoadBalancer
  selector:
    app: nodejs-cicd-demo
  ports:
    - port: 80
      targetPort: 3000
```

> Lưu ý: `<ECR_REPO_URI>` sẽ được thay thế tự động bằng lệnh `sed` trong buildspec ở Bước 4.

Commit và push:

```bash
git add Dockerfile k8s/deployment.yaml
git commit -m "Add Dockerfile and k8s manifest for CI/CD lab"
git push origin main
```

---

## 7. Bước 4 — Tạo file `buildspec.yml`

Tạo file `buildspec.yml` ở thư mục gốc repo:

```yaml
version: 0.2

env:
  variables:
    CLUSTER_NAME: "eks-cicd-lab"
    AWS_REGION: "ap-southeast-1"
    ECR_REPO: "nodejs-cicd-demo"

phases:
  install:
    commands:
      - curl -o kubectl https://s3.us-west-2.amazonaws.com/amazon-eks/1.29.0/2024-01-04/bin/linux/amd64/kubectl
      - chmod +x ./kubectl && mv ./kubectl /usr/local/bin

  pre_build:
    commands:
      - echo "Đăng nhập vào Amazon ECR..."
      - aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
      - REPO_URI=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO
      - IMAGE_TAG=$(echo $CODEBUILD_RESOLVED_SOURCE_VERSION | cut -c 1-7)

  build:
    commands:
      - echo "Build Docker image..."
      - docker build -t $REPO_URI:$IMAGE_TAG -t $REPO_URI:latest .

  post_build:
    commands:
      - echo "Push image lên ECR..."
      - docker push $REPO_URI:$IMAGE_TAG
      - docker push $REPO_URI:latest
      - echo "Cập nhật kubeconfig..."
      - aws eks update-kubeconfig --name $CLUSTER_NAME --region $AWS_REGION
      - echo "Deploy lên EKS..."
      - sed -i "s|<ECR_REPO_URI>|$REPO_URI|g" k8s/deployment.yaml
      - kubectl set image deployment/nodejs-cicd-demo nodejs-cicd-demo=$REPO_URI:$IMAGE_TAG --record || kubectl apply -f k8s/deployment.yaml
      - kubectl rollout status deployment/nodejs-cicd-demo
```

Cần biến môi trường `AWS_ACCOUNT_ID` — sẽ khai báo trong CodeBuild project ở Bước 6.

Commit và push file này:

```bash
git add buildspec.yml
git commit -m "Add buildspec for CodeBuild"
git push origin main
```

---

## 8. Bước 5 — Cấp quyền EKS cho CodeBuild (quan trọng)

CodeBuild cần quyền `kubectl` trên cụm EKS. Người tạo cụm (bạn) là admin mặc định, nhưng CodeBuild chạy bằng **IAM Role** khác nên cần được thêm vào `aws-auth` ConfigMap.

Trước tiên tạo IAM Role cho CodeBuild (`codebuild-eks-role`) — thực hiện ở Bước 6 khi tạo CodeBuild project. Sau khi có ARN của role, chạy:

```bash
eksctl create iamidentitymapping \
  --cluster eks-cicd-lab \
  --region ap-southeast-1 \
  --arn arn:aws:iam::<ACCOUNT_ID>:role/codebuild-eks-role \
  --group system:masters \
  --username codebuild
```

> ⚠️ Đây là bước học viên **hay quên nhất** và là nguyên nhân phổ biến nhất khiến pipeline báo lỗi `Unauthorized` khi `kubectl apply`.

---

## 9. Bước 6 — Tạo AWS CodeBuild Project

Trong AWS Console → **CodeBuild** → **Create build project**:

| Thiết lập | Giá trị |
|---|---|
| Project name | `nodejs-cicd-eks-build` |
| Source | GitHub → chọn repo `nodejs-cicd-demo` (qua CodeStar Connection) |
| Environment image | Managed image, Ubuntu, Standard, runtime `aws/codebuild/standard:7.0` |
| Privileged | ✅ Bật (bắt buộc để build Docker image) |
| Service role | Tạo mới → đặt tên `codebuild-eks-role` |
| Environment variables | `AWS_ACCOUNT_ID` = số tài khoản AWS |
| Buildspec | Use a buildspec file (`buildspec.yml`) |

Sau khi tạo xong, vào **IAM → Roles → codebuild-eks-role**, gắn thêm các policy:
- `AmazonEC2ContainerRegistryPowerUser`
- `AmazonEKSClusterPolicy` (hoặc policy tùy chỉnh cho phép `eks:DescribeCluster`)

Sau đó quay lại **Bước 5** để chạy lệnh `eksctl create iamidentitymapping` với ARN chính xác của role vừa tạo.

---

## 10. Bước 7 — Tạo AWS CodePipeline

Trong Console → **CodePipeline** → **Create pipeline**:

1. **Pipeline settings:** đặt tên `nodejs-cicd-eks-pipeline`, tạo role mới
2. **Source stage:** GitHub (qua CodeStar Connections) → chọn repo `nodejs-cicd-demo`, nhánh `main`
3. **Build stage:** chọn CodeBuild project `nodejs-cicd-eks-build` vừa tạo
4. **Deploy stage:** bỏ qua (vì deploy đã nằm trong buildspec `post_build`)
5. Bấm **Create pipeline**

Pipeline sẽ tự chạy lần đầu ngay sau khi tạo.

---

## 11. Bước 8 — Kiểm tra kết quả

```bash
kubectl get pods
kubectl get svc nodejs-cicd-demo-svc
```

Lấy `EXTERNAL-IP` của service (LoadBalancer) và truy cập bằng trình duyệt hoặc `curl`:

```bash
curl http://<EXTERNAL-IP>
```

**Checklist hoàn thành:**
- [ ] Pipeline chạy thành công (màu xanh ở cả 2 stage)
- [ ] `kubectl get pods` hiển thị pod ở trạng thái `Running`
- [ ] Truy cập được ứng dụng qua LoadBalancer

---

## 12. Thử nghiệm: Kích hoạt CI/CD tự động

Sửa một dòng trong `server.js` (ví dụ đổi nội dung trang chủ), sau đó:

```bash
git add .
git commit -m "Test auto CI/CD trigger"
git push origin main
```

Quan sát CodePipeline tự động chạy lại và cập nhật deployment (`kubectl rollout status` sẽ hiển thị rolling update).

---

## 13. Xử lý lỗi thường gặp

| Lỗi | Nguyên nhân | Cách khắc phục |
|---|---|---|
| `error: You must be logged in to the server (Unauthorized)` | CodeBuild role chưa được map vào `aws-auth` | Chạy lại `eksctl create iamidentitymapping` (Bước 5) với đúng ARN role |
| `docker: permission denied` khi build | CodeBuild project chưa bật **Privileged mode** | Vào project settings → Environment → bật Privileged |
| `no basic auth credentials` khi push ECR | Thiếu bước `aws ecr get-login-password` hoặc sai region | Kiểm tra lại `pre_build` trong buildspec |
| Pipeline báo lỗi ngay ở Source stage | Chưa cấp quyền cho CodeStar Connection | Vào **Developer Tools → Settings → Connections**, cập nhật trạng thái thành `Available` |
| `ImagePullBackOff` trên pod | Image tag sai hoặc ECR repo không đúng | Kiểm tra `kubectl describe pod <pod-name>`, đối chiếu `REPO_URI` trong buildspec |
| Rollout treo mãi không xong | Container app crash ngay khi start | Xem log: `kubectl logs deployment/nodejs-cicd-demo` |

---

## 14. Dọn dẹp tài nguyên (tránh phát sinh chi phí)

```bash
kubectl delete -f k8s/deployment.yaml
eksctl delete cluster --name eks-cicd-lab --region ap-southeast-1
aws ecr delete-repository --repository-name nodejs-cicd-demo --region ap-southeast-1 --force
```

Xóa thêm CodePipeline và CodeBuild project trong Console nếu không còn sử dụng.

---

