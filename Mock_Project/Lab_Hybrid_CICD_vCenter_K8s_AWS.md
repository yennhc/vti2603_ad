# LAB THỰC HÀNH: Xây Dựng Hybrid CI/CD Pipeline
## (VMware vCenter + Kubernetes + Jenkins + GitHub + AWS)

**Đối tượng:** Sinh viên đã học qua Kubernetes, VMware vCenter, Jenkins CI/CD, GitHub, AWS cơ bản
**Mức độ:** Trung bình (Intermediate)
**Thời lượng đề xuất:** 2 buổi (8–10 giờ) hoặc 1 tuần tự học
**Hình thức:** Mock project cá nhân hoặc nhóm 2–3 sinh viên

---

## 1. BỐI CẢNH DỰ ÁN (SCENARIO)

Bạn là Kỹ sư DevOps mới được tuyển vào công ty **"VietTech Solutions"**. Công ty đang vận hành một hạ tầng ảo hóa VMware (vCenter) tại chỗ và muốn hiện đại hóa quy trình triển khai phần mềm bằng cách:

1. Tự động build và test mã nguồn mỗi khi có commit mới trên GitHub.
2. Đóng gói ứng dụng thành Docker image.
3. Đẩy image lên **Amazon ECR** (registry trên cloud) để tận dụng tính sẵn sàng cao.
4. Triển khai ứng dụng lên **Kubernetes cluster** chạy trên các VM nội bộ (VMware vCenter) — mô hình "on-prem K8s, cloud registry".
5. Có khả năng rollback nhanh khi deploy lỗi.

Nhiệm vụ của bạn: xây dựng toàn bộ pipeline này từ đầu, trên một môi trường lab mô phỏng.

---

## 2. KIẾN TRÚC TỔNG THỂ

```
 [Dev push code]
        │
        ▼
   ┌─────────────┐        webhook        ┌─────────────────────┐
   │   GitHub    │ ─────────────────────▶│   Jenkins Server     │
   │ (source code)│                       │  (VM trên vCenter)   │
   └─────────────┘                       └──────────┬───────────┘
                                                     │ 1. Checkout code
                                                     │ 2. Build & Test
                                                     │ 3. Build Docker image
                                                     │ 4. Push image
                                                     ▼
                                          ┌─────────────────────┐
                                          │   Amazon ECR        │
                                          │ (Docker Registry)   │
                                          └──────────┬──────────┘
                                                     │ 5. kubectl apply / helm upgrade
                                                     ▼
                                          ┌─────────────────────┐
                                          │  Kubernetes Cluster  │
                                          │  (3 VM trên vCenter: │
                                          │  1 master + 2 worker)│
                                          └─────────────────────┘
```

**Hạ tầng cần chuẩn bị (VM trên vCenter hoặc VMware Workstation nếu không có vCenter thật):**

| VM | Vai trò | Cấu hình đề xuất |
|---|---|---|
| `jenkins-srv` | Jenkins Controller | 2 vCPU, 4GB RAM, Ubuntu 24.04 |
| `k8s-master` | Kubernetes Control Plane | 2 vCPU, 4GB RAM, Ubuntu 24.04 |
| `k8s-worker-01` | Kubernetes Worker Node | 2 vCPU, 4GB RAM, Ubuntu 24.04 |
| `k8s-worker-02` | Kubernetes Worker Node | 2 vCPU, 4GB RAM, Ubuntu 24.04 |

> 💡 Nếu phòng lab không có vCenter thật, có thể dùng VMware Workstation/ESXi Free để giả lập, hoặc dùng multipass/VirtualBox — cách làm tương tự.

---

## 3. YÊU CẦU TIÊN QUYẾT

- [ ] Tài khoản AWS (Free Tier đủ dùng), đã tạo IAM user có quyền `AmazonEC2ContainerRegistryFullAccess`
- [ ] Tài khoản GitHub, đã tạo 1 repository chứa ứng dụng demo (Node.js/Java/Python đơn giản, có Dockerfile)
- [ ] 4 VM đã dựng trên vCenter (hoặc tương đương), network thông nhau (cùng subnet hoặc route được)
- [ ] AWS CLI đã cài trên `jenkins-srv`
- [ ] `kubectl`, `kubeadm`, `docker`/`containerd` đã cài đặt theo lab K8s bạn đã học

---

## 4. CÁC BƯỚC THỰC HÀNH

### Phần A — Dựng Kubernetes Cluster trên vCenter (ôn lại kiến thức đã học)

1. Trên `k8s-master`, khởi tạo cluster:
```bash
sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address=<IP_MASTER>
```
2. Cấu hình `kubectl` cho user thường:
```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```
3. Cài CNI plugin (Flannel hoặc Calico):
```bash
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
```
4. Join 2 worker node bằng lệnh `kubeadm join` được sinh ra từ bước init.
5. Kiểm tra:
```bash
kubectl get nodes -o wide
```
✅ **Checkpoint:** Cả 3 node ở trạng thái `Ready`.

---

### Phần B — Chuẩn bị Amazon ECR

1. Tạo repository trên ECR:
```bash
aws ecr create-repository --repository-name viettech-demo-app --region ap-southeast-1
```
2. Ghi lại URI repository, dạng:
```
<account_id>.dkr.ecr.ap-southeast-1.amazonaws.com/viettech-demo-app
```
3. Tạo IAM user/role riêng cho Jenkins (không dùng root), gắn policy tối thiểu cần thiết (ECR push/pull).

---

### Phần C — Cài đặt Jenkins trên VM (`jenkins-srv`)

1. Cài Jenkins + Java, cài Docker CLI trên cùng máy Jenkins (để build image).
2. Cài các plugin cần thiết: `Docker Pipeline`, `Amazon ECR`, `GitHub Integration`, `Kubernetes CLI`.
3. Cấu hình credentials trong Jenkins:
   - GitHub Personal Access Token (để checkout private repo, nếu cần)
   - AWS Access Key/Secret (hoặc dùng `aws configure` trực tiếp trên host nếu không muốn lưu credentials trong Jenkins)
   - Kubeconfig file của cluster (copy từ `k8s-master` về, lưu làm "Secret file" credential)

---

### Phần D — Viết Jenkinsfile (Pipeline as Code)

Tạo file `Jenkinsfile` trong repo GitHub với nội dung mẫu:

```groovy
pipeline {
    agent any

    environment {
        AWS_ACCOUNT_ID = '123456789012'
        AWS_REGION     = 'ap-southeast-1'
        ECR_REPO       = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/viettech-demo-app"
        IMAGE_TAG      = "${env.BUILD_NUMBER}"
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Run Tests') {
            steps {
                sh 'npm install && npm test'   // hoặc mvn test, pytest ... tùy ứng dụng
            }
        }

        stage('Build Docker Image') {
            steps {
                sh "docker build -t ${ECR_REPO}:${IMAGE_TAG} ."
            }
        }

        stage('Push to ECR') {
            steps {
                sh """
                    aws ecr get-login-password --region ${AWS_REGION} | \
                    docker login --username AWS --password-stdin ${ECR_REPO}
                    docker push ${ECR_REPO}:${IMAGE_TAG}
                """
            }
        }

        stage('Deploy to Kubernetes') {
            steps {
                withCredentials([file(credentialsId: 'k8s-kubeconfig', variable: 'KUBECONFIG')]) {
                    sh """
                        kubectl set image deployment/viettech-app \
                        viettech-app=${ECR_REPO}:${IMAGE_TAG} --record
                        kubectl rollout status deployment/viettech-app
                    """
                }
            }
        }
    }

    post {
        failure {
            echo 'Build/Deploy thất bại — kiểm tra log để rollback nếu cần.'
        }
    }
}
```

> 📝 Sinh viên cần tự điều chỉnh lệnh test/build theo ngôn ngữ ứng dụng thật của mình.

---

### Phần E — Tạo Kubernetes Deployment & Service ban đầu

Trên `k8s-master`, tạo file `deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: viettech-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: viettech-app
  template:
    metadata:
      labels:
        app: viettech-app
    spec:
      containers:
      - name: viettech-app
        image: <account_id>.dkr.ecr.ap-southeast-1.amazonaws.com/viettech-demo-app:latest
        ports:
        - containerPort: 3000
---
apiVersion: v1
kind: Service
metadata:
  name: viettech-app-svc
spec:
  type: NodePort
  selector:
    app: viettech-app
  ports:
  - port: 80
    targetPort: 3000
    nodePort: 30080
```

Áp dụng lần đầu (thủ công, để Jenkins sau này chỉ cần update image):
```bash
kubectl apply -f deployment.yaml
```

> ⚠️ **Lưu ý quan trọng:** Node K8s cần có quyền pull image từ ECR (tạo Kubernetes Secret loại `docker-registry` với credentials AWS, hoặc dùng IAM Roles Anywhere nếu muốn nâng cao).

```bash
kubectl create secret docker-registry ecr-secret \
  --docker-server=<account_id>.dkr.ecr.ap-southeast-1.amazonaws.com \
  --docker-username=AWS \
  --docker-password=$(aws ecr get-login-password --region ap-southeast-1)
```

---

### Phần F — Kết nối GitHub Webhook → Jenkins

1. Trong GitHub repo → Settings → Webhooks → thêm URL: `http://<jenkins-ip>:8080/github-webhook/`
2. Trong Jenkins Job, tick "GitHub hook trigger for GITScm polling".
3. Test: commit + push code mới → kiểm tra Jenkins tự động chạy build.

✅ **Checkpoint cuối:** Push code lên GitHub → Jenkins build → image lên ECR → Pod trong K8s tự cập nhật phiên bản mới (kiểm tra bằng `kubectl get pods -w`).

---

## 5. BÀI TẬP MỞ RỘNG (Nâng cao độ khó nếu cần)

Chọn 1–2 bài để tăng thử thách:

1. **Rollback tự động:** Thêm stage kiểm tra health-check sau deploy; nếu fail, tự động `kubectl rollout undo`.
2. **Multi-environment:** Tạo 2 namespace `staging` và `production`, deploy staging trước, cần approval thủ công (`input` step trong Jenkinsfile) mới deploy production.
3. **So sánh với AWS-native CI/CD:** Dựng thêm 1 pipeline song song bằng AWS CodePipeline + CodeBuild (không dùng Jenkins) để deploy lên EKS, rồi viết báo cáo so sánh ưu/nhược điểm giữa 2 cách tiếp cận (on-prem Jenkins vs. full AWS-native).
4. **Giám sát:** Tích hợp Zabbix hoặc Prometheus/Grafana để giám sát Pod health và Jenkins build status.
5. **Bảo mật:** Thay vì lưu AWS key trong Jenkins, thử dùng `IAM Roles Anywhere` hoặc Vault để quản lý secret.

---

## 6. TIÊU CHÍ ĐÁNH GIÁ (RUBRIC — Thang điểm 100)

| Tiêu chí | Điểm |
|---|---|
| K8s cluster khởi tạo đúng, 3 node Ready | 15 |
| Jenkins cài đặt và cấu hình plugin đầy đủ | 10 |
| Jenkinsfile chạy đủ các stage (build, test, push, deploy) | 25 |
| Image build và push thành công lên ECR | 15 |
| Deploy thành công lên K8s, Pod chạy ổn định | 15 |
| Webhook GitHub → Jenkins hoạt động tự động | 10 |
| Báo cáo/screenshot đầy đủ từng bước + xử lý lỗi gặp phải | 10 |

**Điểm cộng (tối đa +15):** Hoàn thành 1 trong các bài tập mở rộng ở mục 5.

---

## 7. CÁC LỖI THƯỜNG GẶP & HƯỚNG XỬ LÝ

| Lỗi | Nguyên nhân thường gặp | Cách khắc phục |
|---|---|---|
| Jenkins không push được lên ECR | Chưa `aws ecr get-login-password` hoặc IAM thiếu quyền | Kiểm tra lại IAM policy, thử login thủ công trước |
| Pod ở trạng thái `ImagePullBackOff` | Thiếu Secret `docker-registry` hoặc token ECR hết hạn (12h) | Tạo lại secret, hoặc dùng CronJob refresh token |
| Webhook không trigger | Firewall chặn GitHub gọi vào Jenkins, hoặc Jenkins sau NAT | Dùng ngrok để test, hoặc mở port đúng trên pfSense/firewall |
| Worker node `NotReady` | CNI plugin chưa cài, hoặc swap chưa tắt | `swapoff -a`, kiểm tra lại Flannel/Calico pods |
| `kubectl` trong Jenkins báo lỗi kết nối | Kubeconfig credential sai hoặc IP master đổi (DHCP) | Đặt IP tĩnh cho `k8s-master`, cập nhật lại credential |

---

## 8. GHI CHÚ CHO GIẢNG VIÊN

- Nếu lớp không có sẵn vCenter, có thể thay bằng VMware Workstation Pro hoặc ESXi Free — vẫn giữ nguyên tinh thần "hạ tầng ảo hóa on-prem".
- Có thể rút gọn còn 1 buổi bằng cách bỏ Phần A (dùng K8s cluster dựng sẵn từ lab trước) và tập trung vào Jenkins + ECR + Deploy.
- Nên chuẩn bị sẵn 1 ứng dụng demo tối giản (ví dụ Node.js Express "Hello World" có `/health` endpoint) để sinh viên không mất thời gian viết code, tập trung vào DevOps pipeline.
