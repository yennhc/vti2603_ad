# 🚀 Hướng dẫn từng bước: Deploy Nginx trên Kubernetes

> **Mục tiêu:** Sau bài lab này, học viên sẽ hiểu cách triển khai một ứng dụng Nginx lên cụm Kubernetes bằng script tự động hóa, đồng thời nắm rõ từng thành phần (Namespace, Deployment, Service) và cách vận hành chúng.

---

## 📋 Mục lục

1. [Yêu cầu trước khi bắt đầu](#1-yêu-cầu-trước-khi-bắt-đầu)
2. [Tổng quan kiến trúc](#2-tổng-quan-kiến-trúc)
3. [Bước 1 – Hiểu cấu trúc script](#3-bước-1--hiểu-cấu-trúc-script)
4. [Bước 2 – Chạy Deploy](#4-bước-2--chạy-deploy)
5. [Bước 3 – Kiểm tra trạng thái](#5-bước-3--kiểm-tra-trạng-thái)
6. [Bước 4 – Truy cập Nginx](#6-bước-4--truy-cập-nginx)
7. [Bước 5 – Thử nghiệm Scale & Update](#7-bước-5--thử-nghiệm-scale--update)
8. [Bước 6 – Dọn dẹp tài nguyên](#8-bước-6--dọn-dẹp-tài-nguyên)
9. [Giải thích chi tiết từng thành phần](#9-giải-thích-chi-tiết-từng-thành-phần)
10. [Bài tập thực hành](#10-bài-tập-thực-hành)
11. [Xử lý lỗi thường gặp](#11-xử-lý-lỗi-thường-gặp)

---

## 1. Yêu cầu trước khi bắt đầu

### Phần mềm cần cài đặt

| Công cụ | Mục đích | Cài đặt |
|---------|---------|---------|
| **kubectl** | CLI quản lý Kubernetes | [Hướng dẫn cài đặt](https://kubernetes.io/docs/tasks/tools/) |
| **minikube** hoặc **kind** | Tạo cụm K8s trên máy local | [minikube](https://minikube.sigs.k8s.io/docs/start/) / [kind](https://kind.sigs.k8s.io/) |
| **Docker** | Container runtime | [Docker Desktop](https://www.docker.com/products/docker-desktop/) |

### Khởi động cụm Kubernetes (nếu dùng minikube)

```bash
# Khởi động minikube
minikube start

# Kiểm tra cụm đã sẵn sàng
kubectl cluster-info

# Kiểm tra node
kubectl get nodes
```

**Kết quả mong đợi:**

```
Kubernetes control plane is running at https://127.0.0.1:xxxxx
CoreDNS is running at https://127.0.0.1:xxxxx/api/v1/...

NAME       STATUS   ROLES           AGE   VERSION
minikube   Ready    control-plane   1m    v1.30.0
```

---

## 2. Tổng quan kiến trúc

Trước khi bắt đầu, hãy hiểu những gì script sẽ tạo ra:

```
┌─────────────────────────────────────────────────────────────┐
│                  Kubernetes Cluster                         │
│                                                             │
│  ┌───────────────────────────────────────────────────────┐  │
│  │              Namespace: nginx-demo                    │  │
│  │                                                       │  │
│  │  ┌─────────────────────────────────────────────────┐  │  │
│  │  │          Deployment: nginx-deployment           │  │  │
│  │  │                                                 │  │  │
│  │  │   ┌──────────┐      ┌──────────┐               │  │  │
│  │  │   │  Pod 1   │      │  Pod 2   │               │  │  │
│  │  │   │ nginx:   │      │ nginx:   │               │  │  │
│  │  │   │ 1.27     │      │ 1.27     │               │  │  │
│  │  │   │ :80      │      │ :80      │               │  │  │
│  │  │   └────┬─────┘      └────┬─────┘               │  │  │
│  │  │        │                 │                      │  │  │
│  │  └────────┼─────────────────┼──────────────────────┘  │  │
│  │           │                 │                          │  │
│  │  ┌────────┴─────────────────┴──────────────────────┐  │  │
│  │  │         Service: nginx-service                  │  │  │
│  │  │         Type: NodePort                          │  │  │
│  │  │         Port: 80 → NodePort: 30080              │  │  │
│  │  └─────────────────────┬───────────────────────────┘  │  │
│  │                        │                              │  │
│  └────────────────────────┼──────────────────────────────┘  │
│                           │                                 │
└───────────────────────────┼─────────────────────────────────┘
                            │
                    Truy cập từ bên ngoài
                  http://<NODE_IP>:30080
```

### Giải thích luồng hoạt động

```
User gửi request
       │
       ▼
  NodePort :30080
       │
       ▼
  Service (nginx-service)
       │
       ├──── Load Balance ────┐
       ▼                      ▼
    Pod 1 (:80)           Pod 2 (:80)
    nginx:1.27            nginx:1.27
```

---

## 3. Bước 1 – Hiểu cấu trúc script

Mở file `deploy-nginx.sh` và đọc hiểu từng phần:

### Phần cấu hình (dòng 22-29)

```bash
NAMESPACE="nginx-demo"         # Tên namespace (môi trường cô lập)
DEPLOYMENT_NAME="nginx-deployment"  # Tên deployment
SERVICE_NAME="nginx-service"   # Tên service
NGINX_IMAGE="nginx:1.27"       # Image nginx sử dụng
REPLICAS=2                     # Số lượng Pod
CONTAINER_PORT=80              # Port container lắng nghe
SERVICE_PORT=80                # Port của Service
NODE_PORT=30080                # Port truy cập từ bên ngoài
```

> 💡 **Lưu ý:** Học viên có thể thay đổi các giá trị này để thực hành (ví dụ: đổi `REPLICAS=3`, đổi `NODE_PORT=30081`).

### Các lệnh chính của script

| Lệnh | Mô tả |
|-------|--------|
| `bash deploy-nginx.sh deploy` | Triển khai toàn bộ (namespace + deployment + service) |
| `bash deploy-nginx.sh status` | Xem trạng thái hiện tại |
| `bash deploy-nginx.sh cleanup` | Xóa toàn bộ tài nguyên đã tạo |

---

## 4. Bước 2 – Chạy Deploy

### 4.1 Cấp quyền thực thi cho script

```bash
chmod +x deploy-nginx.sh
```

### 4.2 Chạy deploy

```bash
bash deploy-nginx.sh deploy
```

### 4.3 Kết quả mong đợi

```
[INFO]  Running pre-flight checks...
[OK]    kubectl is available and cluster is reachable.
[INFO]  Creating namespace 'nginx-demo' (if not exists)...
namespace/nginx-demo created
[INFO]  Applying Nginx Deployment (2 replicas, image: nginx:1.27)...
deployment.apps/nginx-deployment created
[INFO]  Applying NodePort Service (port 80 → nodePort 30080)...
service/nginx-service created
[INFO]  Waiting for deployment to be ready...
deployment "nginx-deployment" successfully rolled out

[OK]    Nginx deployed successfully!
```

> 📝 **Ghi chú:** Nếu chạy lại lần 2, output sẽ hiện `configured` thay vì `created` – đây là tính năng **idempotent** của `kubectl apply`.

---

## 5. Bước 3 – Kiểm tra trạng thái

### 5.1 Dùng script

```bash
bash deploy-nginx.sh status
```

### 5.2 Dùng kubectl thủ công (khuyến khích thực hành)

```bash
# Xem tất cả resource trong namespace
kubectl get all -n nginx-demo

# Xem chi tiết pods
kubectl get pods -n nginx-demo -o wide

# Xem chi tiết deployment
kubectl describe deployment nginx-deployment -n nginx-demo

# Xem chi tiết service
kubectl describe service nginx-service -n nginx-demo

# Xem logs của một pod
kubectl logs -n nginx-demo -l app=nginx
```

### 5.3 Hiểu output của `kubectl get pods`

```
NAME                                READY   STATUS    RESTARTS   AGE
nginx-deployment-7c5b8c6d9-abc12   1/1     Running   0          2m
nginx-deployment-7c5b8c6d9-def34   1/1     Running   0          2m
```

| Cột | Ý nghĩa |
|-----|---------|
| `NAME` | Tên pod (tự sinh bởi Deployment) |
| `READY` | `1/1` = 1 container sẵn sàng / tổng 1 container |
| `STATUS` | `Running` = đang chạy bình thường |
| `RESTARTS` | Số lần container bị restart |
| `AGE` | Thời gian đã chạy |

---

## 6. Bước 4 – Truy cập Nginx

### Cách 1: Port-forward (khuyến nghị cho học tập)

```bash
kubectl port-forward svc/nginx-service 8080:80 -n nginx-demo
```

Mở trình duyệt: **http://localhost:8080**

> Nhấn `Ctrl + C` để dừng port-forward.

### Cách 2: NodePort (minikube)

```bash
# Lấy URL truy cập
minikube service nginx-service -n nginx-demo --url
```

### Cách 3: NodePort (truy cập trực tiếp)

```bash
# Lấy IP của Node
kubectl get nodes -o wide

# Truy cập
curl http://<NODE_IP>:30080
```

### Kết quả mong đợi

Bạn sẽ thấy trang **Welcome to nginx!** mặc định:

```html
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
...
</head>
<body>
<h1>Welcome to nginx!</h1>
<p>If you see this page, the nginx web server is successfully installed...</p>
</body>
</html>
```

---

## 7. Bước 5 – Thử nghiệm Scale & Update

### 7.1 Scale (thay đổi số lượng Pod)

```bash
# Tăng lên 4 replicas
kubectl scale deployment nginx-deployment --replicas=4 -n nginx-demo

# Xem pods mới được tạo
kubectl get pods -n nginx-demo -w
# (Nhấn Ctrl+C để thoát watch mode)

# Giảm xuống 1 replica
kubectl scale deployment nginx-deployment --replicas=1 -n nginx-demo

# Xem pod bị terminate
kubectl get pods -n nginx-demo
```

> 💡 **Câu hỏi suy nghĩ:** Khi scale xuống 1 pod, service vẫn hoạt động bình thường không? Tại sao?

### 7.2 Rolling Update (cập nhật image)

```bash
# Cập nhật image sang version mới
kubectl set image deployment/nginx-deployment nginx=nginx:1.26 -n nginx-demo

# Xem quá trình rolling update
kubectl rollout status deployment/nginx-deployment -n nginx-demo

# Kiểm tra image hiện tại
kubectl describe deployment nginx-deployment -n nginx-demo | grep Image
```

### 7.3 Rollback (quay về phiên bản trước)

```bash
# Xem lịch sử revision
kubectl rollout history deployment/nginx-deployment -n nginx-demo

# Rollback về revision trước đó
kubectl rollout undo deployment/nginx-deployment -n nginx-demo

# Kiểm tra lại image
kubectl describe deployment nginx-deployment -n nginx-demo | grep Image
# → Kỳ vọng: nginx:1.27 (quay về version ban đầu)
```

> 💡 **Ghi nhớ luồng Rolling Update:**
> ```
> Pod cũ (nginx:1.27)  ──→  Tạo Pod mới (nginx:1.26)
>                            ──→  Readiness check PASS
>                            ──→  Xóa Pod cũ
>                            ──→  Lặp lại cho Pod tiếp theo
>                            ──→  Hoàn tất, không downtime!
> ```

---

## 8. Bước 6 – Dọn dẹp tài nguyên

```bash
bash deploy-nginx.sh cleanup
```

```
[WARN]  This will delete ALL nginx resources in namespace 'nginx-demo'.
Are you sure? (y/N): y
[INFO]  Deleting service...
service "nginx-service" deleted
[INFO]  Deleting deployment...
deployment.apps "nginx-deployment" deleted
[INFO]  Deleting namespace...
namespace "nginx-demo" deleted
[OK]    Cleanup complete.
```

**Kiểm tra đã xóa sạch:**

```bash
kubectl get all -n nginx-demo
# Kỳ vọng: "No resources found in nginx-demo namespace." hoặc lỗi namespace không tồn tại
```

---

## 9. Giải thích chi tiết từng thành phần

### 9.1 Namespace

```yaml
kubectl create namespace nginx-demo
```

- **Namespace** = "phòng cách ly" trong cụm Kubernetes
- Mỗi namespace có tài nguyên riêng biệt, không ảnh hưởng lẫn nhau
- Mặc định Kubernetes có các namespace: `default`, `kube-system`, `kube-public`

```
Kubernetes Cluster
├── Namespace: default
├── Namespace: kube-system       ← Chạy các thành phần hệ thống
├── Namespace: nginx-demo        ← Namespace ta tạo
│   ├── Deployment
│   ├── Pods
│   └── Service
└── ...
```

### 9.2 Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
```

Deployment quản lý vòng đời của Pods:

| Tính năng | Mô tả |
|-----------|--------|
| `replicas: 2` | Luôn duy trì 2 Pod chạy |
| `selector.matchLabels` | Xác định Pod nào thuộc Deployment này |
| `resources.requests` | Tài nguyên tối thiểu cần cho mỗi Pod |
| `resources.limits` | Tài nguyên tối đa mỗi Pod được phép dùng |
| `readinessProbe` | Kiểm tra Pod đã sẵn sàng nhận traffic chưa |
| `livenessProbe` | Kiểm tra Pod còn sống không, nếu chết thì restart |

### 9.3 Service (NodePort)

```yaml
apiVersion: v1
kind: Service
spec:
  type: NodePort
```

Service là cách để expose ứng dụng ra bên ngoài:

```
Các loại Service:

ClusterIP (mặc định)
  → Chỉ truy cập được từ bên trong cluster
  → Dùng cho: giao tiếp giữa các service nội bộ

NodePort
  → Mở port trên mỗi Node (range: 30000-32767)
  → Dùng cho: truy cập từ bên ngoài (dev/test)

LoadBalancer
  → Tạo Load Balancer trên cloud (AWS ELB, GCP LB...)
  → Dùng cho: production trên cloud
```

### 9.4 Readiness vs Liveness Probe

```
                    ┌──────────────┐
   Container Start  │              │
        │           │  Startup     │  (nếu có)
        ▼           │  Probe       │
   ┌────────────┐   │              │
   │ Khởi động  │───┤  PASS?       │
   │ ứng dụng   │   │  ↓           │
   └────────────┘   └──────────────┘
        │
        ▼
   ┌────────────────────────────────────────┐
   │                                        │
   │  Readiness Probe        Liveness Probe │
   │  "Sẵn sàng nhận        "Còn sống      │
   │   traffic chưa?"        không?"        │
   │                                        │
   │  FAIL → Loại khỏi      FAIL → Restart │
   │         Service                 Pod    │
   │  PASS → Nhận traffic   PASS → Tiếp    │
   │                         tục chạy       │
   └────────────────────────────────────────┘
```

---

## 10. Bài tập thực hành

### Bài 1: Thay đổi cấu hình ⭐

1. Sửa file `deploy-nginx.sh`, đổi `REPLICAS=3`
2. Deploy lại và kiểm tra có đúng 3 pod không

### Bài 2: Tạo YAML riêng ⭐⭐

Thay vì dùng script, hãy tạo 2 file YAML riêng:
- `nginx-deployment.yaml`
- `nginx-service.yaml`

Rồi deploy thủ công bằng `kubectl apply -f`.

### Bài 3: Thêm ConfigMap ⭐⭐⭐

Tạo một ConfigMap chứa file `index.html` tùy chỉnh và mount vào nginx:

```bash
# Gợi ý:
kubectl create configmap nginx-html \
  --from-literal=index.html="<h1>Hello from VTI K8s Lab!</h1>" \
  -n nginx-demo
```

Sau đó thêm `volumeMounts` và `volumes` vào Deployment.

### Bài 4: Thử nghiệm Self-Healing ⭐⭐

1. Deploy nginx (2 replicas)
2. Xóa thủ công 1 pod: `kubectl delete pod <pod-name> -n nginx-demo`
3. Quan sát Kubernetes tự tạo pod mới: `kubectl get pods -n nginx-demo -w`
4. **Câu hỏi:** Tại sao pod được tạo lại tự động?

### Bài 5: Monitoring với kubectl ⭐⭐

```bash
# Xem resource usage (cần metrics-server)
kubectl top pods -n nginx-demo
kubectl top nodes

# Xem events
kubectl get events -n nginx-demo --sort-by='.lastTimestamp'
```

---

## 11. Xử lý lỗi thường gặp

### ❌ Lỗi: `error: unable to connect to the server`

**Nguyên nhân:** Cluster chưa chạy.

```bash
# Giải pháp
minikube start
# hoặc
kubectl cluster-info
```

### ❌ Lỗi: `ImagePullBackOff`

**Nguyên nhân:** Không kéo được image nginx.

```bash
# Kiểm tra
kubectl describe pod <pod-name> -n nginx-demo

# Giải pháp: kiểm tra tên image, kết nối internet
# Hoặc pull image trước
docker pull nginx:1.27
```

### ❌ Lỗi: `Pending` status

**Nguyên nhân:** Không đủ tài nguyên trên Node.

```bash
# Kiểm tra tài nguyên
kubectl describe node minikube

# Giải pháp: giảm resource requests hoặc tăng tài nguyên minikube
minikube start --cpus=4 --memory=4096
```

### ❌ Lỗi: `NodePort 30080 is already in use`

**Nguyên nhân:** Port đã bị chiếm bởi service khác.

```bash
# Kiểm tra
kubectl get svc --all-namespaces | grep 30080

# Giải pháp: đổi NODE_PORT trong script sang port khác (30000-32767)
```

### ❌ Lỗi: `CrashLoopBackOff`

**Nguyên nhân:** Container liên tục crash và restart.

```bash
# Xem logs
kubectl logs <pod-name> -n nginx-demo
kubectl logs <pod-name> -n nginx-demo --previous

# Xem events
kubectl describe pod <pod-name> -n nginx-demo
```
