# BÀI LAB: TÌM HIỂU VÀ THỰC HÀNH VỚI CLUSTERIP SERVICE

**VTI IT Academy** — Khóa học: Hệ Thống Kubernetes & Container Orchestration
*Cơ chế Service, Endpoints, kube-proxy và DNS nội bộ trong Kubernetes*

| Thời lượng | Mức độ | Hình thức |
|---|---|---|
| 90 – 120 phút | Cơ bản → Trung cấp | Thực hành trên cluster K8s (Kubespray / eksctl / Minikube) |

---

## 1. Mục tiêu bài lab

Sau khi hoàn thành bài lab, học viên có khả năng:

- Giải thích được ClusterIP là gì và vì sao Pod IP không đủ tin cậy để giao tiếp trực tiếp.
- Tạo Service loại ClusterIP và ánh xạ đúng tới Pod thông qua label selector.
- Quan sát Endpoints/EndpointSlice tự động cập nhật khi Pod thay đổi (scale, xóa, tái tạo).
- Kiểm chứng DNS nội bộ CoreDNS phân giải tên Service.
- Quan sát rule iptables mà kube-proxy sinh ra để DNAT traffic.
- Phân biệt ClusterIP thường và headless Service (`clusterIP: None`).
- Chẩn đoán lỗi phổ biến: Service không có Endpoints, sai selector, sai port.

## 2. Yêu cầu tiên quyết

| Hạng mục | Yêu cầu |
|---|---|
| Kiến thức | Đã biết Pod, Deployment, Namespace, Label/Selector cơ bản |
| Cluster | Kubernetes cluster đang chạy, có quyền exec vào Pod và vào node |
| Công cụ CLI | kubectl đã cấu hình đúng cluster (`kubectl get nodes` chạy được) |
| Quyền truy cập | Quyền tạo namespace, deployment, service; quyền SSH vào 1 node để xem iptables |

## 3. Kiến trúc lab

Lab triển khai 1 Deployment 3 Pod đứng sau 1 ClusterIP Service, cùng với 1 Pod client dùng để test truy cập:

```
Pod client (curl-client)
     │  gọi: backend-svc.clusterip-lab.svc.cluster.local
     ▼  CoreDNS phân giải → ClusterIP (VD: 10.96.x.x)
ClusterIP Service (backend-svc)
     │  kube-proxy DNAT theo Endpoints
  ┌──┼──┐
  ▼  ▼  ▼
Pod1 Pod2 Pod3   (label: app=backend)
```

## 4. Các bước thực hành

### Bước 1 — Tạo namespace và Deployment backend

Tạo file `backend.yaml`:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: clusterip-lab
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  namespace: clusterip-lab
spec:
  replicas: 3
  selector:
    matchLabels: { app: backend }
  template:
    metadata:
      labels: { app: backend }
    spec:
      containers:
      - name: web
        image: hashicorp/http-echo
        args: ["-text=Xin chao tu $(POD_NAME)"]
        env:
        - name: POD_NAME
          valueFrom:
            fieldRef: { fieldPath: metadata.name }
        ports: [{ containerPort: 5678 }]
```

```bash
kubectl apply -f backend.yaml
kubectl get pods -n clusterip-lab -o wide
```

### Bước 2 — Tạo ClusterIP Service

Tạo file `backend-svc.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: backend-svc
  namespace: clusterip-lab
spec:
  type: ClusterIP
  selector:
    app: backend
  ports:
  - port: 80
    targetPort: 5678
```

```bash
kubectl apply -f backend-svc.yaml
kubectl get svc -n clusterip-lab
kubectl get endpoints backend-svc -n clusterip-lab
```

> **Kết quả mong đợi:** Cột CLUSTER-IP của `backend-svc` có 1 địa chỉ (VD `10.96.x.x`). Lệnh `get endpoints` hiển thị đúng 3 IP:5678 tương ứng 3 Pod backend.

### Bước 3 — Triển khai Pod client và kiểm tra kết nối

```bash
kubectl run curl-client --image=curlimages/curl -n clusterip-lab -it --rm -- sh
```

Bên trong Pod client, chạy các lệnh sau và quan sát:

```bash
# Gọi bằng tên DNS đầy đủ
curl backend-svc.clusterip-lab.svc.cluster.local

# Gọi lặp lại nhiều lần — quan sát tên Pod trả về thay đổi
for i in $(seq 1 6); do curl -s backend-svc; echo; done
```

> **Kết quả mong đợi:** Mỗi lần curl có thể trả về từ Pod khác nhau (backend-xxxxx) — chứng tỏ ClusterIP đang load balance qua kube-proxy giữa 3 Pod backend.

### Bước 4 — Kiểm tra DNS nội bộ (CoreDNS)

```bash
kubectl run dns-test --image=busybox:1.36 -n clusterip-lab -it --rm -- nslookup backend-svc
```

Ghi lại địa chỉ IP trả về và so sánh với CLUSTER-IP ở Bước 2 — chúng phải trùng nhau.

### Bước 5 — Quan sát Endpoints thay đổi tự động

```bash
kubectl scale deployment backend -n clusterip-lab --replicas=1
kubectl get endpoints backend-svc -n clusterip-lab
kubectl scale deployment backend -n clusterip-lab --replicas=4
kubectl get endpoints backend-svc -n clusterip-lab
```

> **Quan sát:** Danh sách IP trong Endpoints tự thu nhỏ/mở rộng theo số Pod đang Ready — Service không cần cấu hình lại thủ công.

### Bước 6 — Xem rule iptables do kube-proxy sinh ra (nâng cao)

SSH vào 1 worker node rồi chạy (cần quyền root/sudo):

```bash
sudo iptables -t nat -L KUBE-SERVICES -n | grep backend-svc
sudo iptables -t nat -L | grep <CLUSTER-IP-cua-backend-svc>
```

Quan sát các rule DNAT trỏ từ ClusterIP sang từng Pod IP thật — đây chính là cơ chế thực thi load balancing.

### Bước 7 — So sánh với Headless Service

Tạo thêm 1 Service headless để so sánh hành vi DNS:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: backend-headless
  namespace: clusterip-lab
spec:
  clusterIP: None
  selector:
    app: backend
  ports:
  - port: 80
    targetPort: 5678
```

```bash
kubectl apply -f -
kubectl run dns-test2 --image=busybox:1.36 -n clusterip-lab -it --rm -- nslookup backend-headless
```

> **So sánh:** `nslookup backend-svc` trả về 1 IP ảo duy nhất. `nslookup backend-headless` trả về trực tiếp danh sách IP của từng Pod — không qua load balancing ảo.

## 5. Bài tập / thử thách (tự làm)

1. Sửa selector của `backend-svc` sang một label không tồn tại (VD `app: khong-ton-tai`), quan sát `kubectl get endpoints` trả về gì và giải thích.
2. Đổi port trong Service sang port khác `targetPort` thực tế của container, kiểm chứng lỗi kết nối xảy ra ở đâu.
3. Dùng `kubectl get endpointslice -n clusterip-lab` để xem cấu trúc EndpointSlice (phiên bản mới thay thế dần Endpoints).
4. Viết 1 Service ClusterIP thứ hai trỏ tới cùng Pod backend nhưng expose port khác (VD 8080), kiểm tra cả 2 Service cùng hoạt động song song.

## 6. Xử lý sự cố thường gặp

| Triệu chứng | Nguyên nhân khả dĩ | Cách kiểm tra |
|---|---|---|
| Endpoints rỗng (`<none>`) | Selector Service không khớp label Pod | `kubectl get pods --show-labels -n clusterip-lab` |
| `curl: Connection refused` | targetPort sai với port container đang lắng nghe | `kubectl exec` vào Pod, kiểm tra process đang listen port nào |
| nslookup không phân giải được | CoreDNS chưa chạy hoặc Pod client sai namespace/svc suffix | `kubectl get pods -n kube-system -l k8s-app=kube-dns` |
| Chỉ 1 Pod luôn nhận traffic | Session affinity đang bật (ClientIP) hoặc số lượng request quá ít | `kubectl get svc backend-svc -o yaml \| grep sessionAffinity` |
| Không thấy rule trong iptables | Cluster dùng chế độ IPVS thay vì iptables cho kube-proxy | `kubectl get configmap kube-proxy -n kube-system -o yaml \| grep mode` |

## 7. Checklist hoàn thành bài lab

- [ ] Deployment backend chạy 3/3 Pod ở trạng thái Running
- [ ] Service backend-svc có CLUSTER-IP và Endpoints hiển thị đủ 3 Pod IP
- [ ] curl từ Pod client trả về nội dung, xoay vòng giữa nhiều Pod khác nhau
- [ ] nslookup backend-svc trả về đúng IP trùng với CLUSTER-IP
- [ ] Quan sát được Endpoints tự cập nhật khi scale Deployment
- [ ] Tìm được ít nhất 1 rule iptables liên quan tới ClusterIP (hoặc giải thích được vì sao dùng IPVS)
- [ ] Giải thích được sự khác biệt giữa ClusterIP thường và headless Service

## 8. Tiêu chí đánh giá

| Tiêu chí | Điểm |
|---|---|
| Triển khai đúng Deployment + ClusterIP Service | 20 |
| Kiểm chứng load balancing qua curl lặp lại | 20 |
| Kiểm chứng DNS nội bộ (CoreDNS) đúng | 15 |
| Quan sát Endpoints tự động cập nhật khi scale | 15 |
| Hoàn thành bước so sánh headless Service | 15 |
| Trả lời đúng câu hỏi giải thích cơ chế khi được hỏi trực tiếp | 15 |

---

*— Hết bài lab —*
