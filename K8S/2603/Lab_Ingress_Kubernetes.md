# BÀI LAB: TRIỂN KHAI VÀ CẤU HÌNH INGRESS TRONG KUBERNETES

**VTI IT Academy** — Khóa học: Hệ Thống Kubernetes & Container Orchestration
*Định tuyến HTTP/HTTPS đa dịch vụ với NGINX Ingress Controller*

| Thời lượng | Mức độ | Hình thức |
|---|---|---|
| 120 – 150 phút | Trung cấp (Intermediate) | Thực hành trên cluster K8s (Kubespray / eksctl / Minikube) |

---

## 1. Mục tiêu bài lab

Sau khi hoàn thành bài lab, học viên có khả năng:

- Giải thích được vai trò của Ingress Resource và Ingress Controller trong Kubernetes.
- Cài đặt NGINX Ingress Controller trên cluster tự quản (on-prem / Kubespray).
- Viết Ingress Resource định tuyến nhiều Service theo host-based và path-based routing.
- Cấu hình TLS termination cho Ingress bằng Secret thủ công.
- Chẩn đoán và xử lý các lỗi thường gặp (404, 502, không có địa chỉ IP, TLS lỗi).

## 2. Yêu cầu tiên quyết

| Hạng mục | Yêu cầu |
|---|---|
| Kiến thức | Đã hoàn thành lab Kubernetes cơ bản: Pod, Deployment, Service, Namespace |
| Cluster | Kubernetes cluster đang chạy (Kubespray, eksctl, hoặc Minikube) với ít nhất 1 worker node |
| Công cụ CLI | kubectl đã cấu hình trỏ đúng cluster (`kubectl get nodes` chạy được) |
| Quyền truy cập | Quyền tạo namespace, deployment, service, ingress trên cluster |
| DNS/hosts | Quyền chỉnh sửa file hosts trên máy học viên (hoặc DNS nội bộ) |

## 3. Kiến trúc lab

Lab triển khai 2 ứng dụng demo (app-v1, app-v2) và định tuyến qua một Ingress Controller duy nhất:

```
Client (curl / trình duyệt)
        │  DNS/hosts: shop.lab.local, api.lab.local
        ▼
Ingress Controller (nginx-ingress, NodePort 30080/30443)
        │  Định tuyến theo Host header
   ┌────┴─────┐
   ▼          ▼
app-v1-svc   app-v2-svc
   │          │
   ▼          ▼
 Pod(s)      Pod(s)
```

## 4. Chuẩn bị môi trường

### 4.1. Tạo namespace riêng cho lab

```bash
kubectl create namespace ingress-lab
kubectl config set-context --current --namespace=ingress-lab
```

### 4.2. Cài đặt NGINX Ingress Controller

Nếu cluster chưa có Ingress Controller, cài bằng Helm:

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.service.type=NodePort \
  --set controller.service.nodePorts.http=30080 \
  --set controller.service.nodePorts.https=30443
```

Kiểm tra controller đã chạy:

```bash
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx
```

> **Lưu ý:** Trên cluster on-prem không có cloud LoadBalancer, dùng `type=NodePort` rồi forward port qua pfSense, hoặc cài thêm MetalLB nếu muốn Service `type=LoadBalancer` cấp IP ảo.

## 5. Các bước thực hành

### Bước 1 — Triển khai 2 ứng dụng demo

Tạo file `app-v1.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-v1
spec:
  replicas: 2
  selector:
    matchLabels: { app: app-v1 }
  template:
    metadata:
      labels: { app: app-v1 }
    spec:
      containers:
      - name: web
        image: hashicorp/http-echo
        args: ["-text=Xin chao tu APP V1"]
        ports: [{ containerPort: 5678 }]
---
apiVersion: v1
kind: Service
metadata:
  name: app-v1-svc
spec:
  selector: { app: app-v1 }
  ports: [{ port: 80, targetPort: 5678 }]
```

Sao chép tương tự cho `app-v2.yaml` (đổi tên thành app-v2, app-v2-svc, text khác), sau đó áp dụng cả hai:

```bash
kubectl apply -f app-v1.yaml
kubectl apply -f app-v2.yaml
kubectl get pods,svc
```

### Bước 2 — Tạo Ingress Resource định tuyến theo host

Tạo file `ingress-lab.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: lab-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - host: shop.lab.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: app-v1-svc
            port: { number: 80 }
  - host: api.lab.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: app-v2-svc
            port: { number: 80 }
```

```bash
kubectl apply -f ingress-lab.yaml
kubectl get ingress
kubectl describe ingress lab-ingress
```

### Bước 3 — Cập nhật DNS/hosts và kiểm tra

Trên máy học viên, thêm vào file hosts (Linux/Mac: `/etc/hosts`, Windows: `C:\Windows\System32\drivers\etc\hosts`):

```
<IP-node-hoặc-VIP>  shop.lab.local
<IP-node-hoặc-VIP>  api.lab.local
```

Kiểm tra định tuyến bằng curl:

```bash
curl -H 'Host: shop.lab.local' http://<IP-node>:30080/
curl -H 'Host: api.lab.local'  http://<IP-node>:30080/
```

> **Kết quả mong đợi:** Mỗi request trả về đúng nội dung text-echo tương ứng với app-v1 hoặc app-v2 — chứng tỏ Ingress đã định tuyến đúng theo Host header.

### Bước 4 — Cấu hình TLS (HTTPS)

Tạo self-signed certificate cho mục đích lab:

```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout tls.key -out tls.crt \
  -subj "/CN=shop.lab.local/O=vti-lab"

kubectl create secret tls lab-tls-secret --cert=tls.crt --key=tls.key
```

Thêm phần `tls` vào `ingress-lab.yaml` rồi apply lại:

```yaml
  tls:
  - hosts:
    - shop.lab.local
    secretName: lab-tls-secret
```

```bash
kubectl apply -f ingress-lab.yaml
curl -k https://shop.lab.local:30443/ --resolve shop.lab.local:30443:<IP-node>
```

### Bước 5 — Path-based routing (nâng cao)

Thêm 1 rule mới trong cùng host `shop.lab.local`, định tuyến `/v2` sang `app-v2-svc`, giữ `/` cho `app-v1-svc`. Đây là bài tập học viên tự triển khai (xem mục 6).

## 6. Bài tập / thử thách (tự làm)

1. Sửa Ingress để cùng host `shop.lab.local`, path `/v1` → `app-v1-svc` và `/v2` → `app-v2-svc`.
2. Thêm annotation giới hạn rate-limit: `nginx.ingress.kubernetes.io/limit-rps: "5"` và kiểm chứng bằng cách gửi liên tục request.
3. Scale app-v1 xuống 0 replicas, quan sát lỗi trả về khi truy cập `shop.lab.local` — giải thích nguyên nhân.
4. Cấu hình basic-auth cho `api.lab.local` bằng Secret loại `kubernetes.io/basic-auth` và annotation `auth-type`/`auth-secret`.

## 7. Xử lý sự cố thường gặp

| Triệu chứng | Nguyên nhân khả dĩ | Cách kiểm tra |
|---|---|---|
| 404 Not Found | Host/path trong Ingress không khớp request | `kubectl describe ingress lab-ingress` |
| 502 Bad Gateway | Pod backend chưa Ready hoặc sai selector | `kubectl get endpoints app-v1-svc` |
| Không có ADDRESS ở `kubectl get ingress` | Ingress Controller chưa chạy / chưa có class | `kubectl get pods -n ingress-nginx` |
| `curl: SSL certificate problem` | Dùng self-signed cert nhưng thiếu `-k` / `--insecure` | Thêm `-k` khi test bằng curl |
| Không match `ingressClassName` | Tên class khai báo sai hoặc thiếu IngressClass | `kubectl get ingressclass` |
| Request không tới đúng Service | Sai tên hoặc port trong `backend.service` | `kubectl get svc -o wide` |

## 8. Checklist hoàn thành bài lab

- [ ] Ingress Controller (ingress-nginx) đã chạy ở trạng thái Running
- [ ] 2 Deployment + 2 Service (app-v1, app-v2) đã triển khai thành công
- [ ] Ingress Resource áp dụng không lỗi, `kubectl describe` không báo Warning
- [ ] curl với Host header trả đúng nội dung cho từng app
- [ ] TLS hoạt động — truy cập HTTPS không bị từ chối kết nối
- [ ] Hoàn thành ít nhất 2/4 bài tập nâng cao ở mục 6
- [ ] Giải thích được sự khác biệt giữa Ingress Resource và Ingress Controller

## 9. Tiêu chí đánh giá

| Tiêu chí | Điểm |
|---|---|
| Triển khai đúng app-v1/app-v2 và Service | 20 |
| Ingress host-based routing hoạt động đúng | 25 |
| Cấu hình TLS thành công | 20 |
| Hoàn thành bài tập path-based routing | 20 |
| Trả lời đúng câu hỏi giải thích kiến trúc khi được hỏi trực tiếp | 15 |

---

*— Hết bài lab —*
