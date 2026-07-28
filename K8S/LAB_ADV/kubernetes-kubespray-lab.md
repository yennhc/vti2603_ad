# LAB: Triển khai Kubernetes bằng Kubespray trên Ubuntu 24.04 LTS

## I. GIỚI THIỆU

**Kubespray** là một công cụ tự động hóa triển khai Kubernetes sử dụng Ansible. Nó cho phép cài đặt cluster Kubernetes một cách dễ dàng và có thể tái sử dụng.

**Mục tiêu LAB:**
- Thiết lập cluster Kubernetes 3 node (1 master + 2 worker) bằng kubespray
- Cấu hình networking CNI (Container Network Interface)
- Xác minh cluster hoạt động đúng

---

## II. YÊU CẦU HỆ THỐNG

### A. Yêu cầu phần cứng

| Thành phần | Yêu cầu tối thiểu | Khuyên dùng |
|-----------|-----------------|-----------|
| **CPU** | 2 vCPU/node | 4 vCPU/node |
| **RAM** | 2GB/node | 4GB/node |
| **Storage** | 20GB/node | 50GB/node |
| **Network** | 1 NIC | Ít nhất 1 Gbps |

### B. Yêu cầu phần mềm

- Ubuntu 24.04 LTS
- Python 3.10+
- SSH access giữa các node
- Internet connectivity (để tải images và packages)

### C. Cấu trúc LAB

```
┌─────────────────────────────────────────┐
│     Ansible Control Machine             │
│  (có thể là một trong các node)          │
└─────────────────────────────────────────┘
            ↓     ↓     ↓
   ┌────────┴─────┴─────┴────────┐
   ↓        ↓        ↓            ↓
┌──────┐ ┌──────┐ ┌──────┐
│Master│ │Worker│ │Worker│
│k8s-1 │ │k8s-2 │ │k8s-3 │
└──────┘ └──────┘ └──────┘
```

**Địa chỉ IP mẫu:**
- k8s-1 (Master): 192.168.100.10
- k8s-2 (Worker): 192.168.100.11
- k8s-3 (Worker): 192.168.100.12

---

## III. BƯỚC 1: CHUẨN BỊ CÁC NODE

### 3.1 Cài đặt Ubuntu 24.04 LTS trên tất cả các node

**Các bước thực hiện:**

1. Tải ISO Ubuntu 24.04 LTS và cài đặt trên mỗi máy ảo
2. Cấu hình địa chỉ IP tĩnh trên mỗi node

**Cấu hình IP tĩnh (ví dụ cho k8s-1):**

```bash
sudo nano /etc/netplan/99-custom.yaml
```

```yaml
network:
  version: 2
  ethernets:
    eth0:
      addresses:
        - 192.168.100.10/24
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
      routes:
        - to: default
          via: 192.168.100.1
```

Áp dụng cấu hình:
```bash
sudo netplan apply
sudo reboot
```

### 3.2 Cập nhật hệ thống

Chạy trên **tất cả các node:**

```bash
sudo apt-get update
sudo apt-get upgrade -y
sudo apt-get install -y git python3-pip python3-venv openssh-server
```

### 3.3 Cấu hình SSH không cần mật khẩu

**Trên Control Machine (nơi chạy Ansible):**

Tạo key pair:
```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""
```

Sao chép key public đến các node (thay IP phù hợp):
```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub ubuntu@192.168.100.10
ssh-copy-id -i ~/.ssh/id_ed25519.pub ubuntu@192.168.100.11
ssh-copy-id -i ~/.ssh/id_ed25519.pub ubuntu@192.168.100.12
```

**Hoặc tự động với SSH password:**

```bash
sshpass -p 'password' ssh-copy-id -i ~/.ssh/id_ed25519.pub ubuntu@192.168.100.10
```

### 3.4 Cấu hình /etc/hosts trên tất cả các node

```bash
sudo bash -c 'cat >> /etc/hosts << EOF
192.168.100.10  k8s-1
192.168.100.11  k8s-2
192.168.100.12  k8s-3
EOF'
```

### 3.5 Vô hiệu hóa Swap (bắt buộc cho Kubernetes)

**Trên tất cả các node:**

```bash
# Vô hiệu hóa swap tạm thời
sudo swapoff -a

# Vô hiệu hóa swap vĩnh viễn
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# Xác minh
free -m
```

### 3.6 Cấu hình Kernel parameters

**Trên tất cả các node:**

```bash
sudo bash -c 'cat >> /etc/sysctl.conf << EOF
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF'

sudo sysctl -p
```

Load kernel modules:
```bash
sudo bash -c 'cat >> /etc/modules-load.d/k8s.conf << EOF
overlay
br_netfilter
EOF'

sudo modprobe overlay
sudo modprobe br_netfilter
```

---

## IV. BƯỚC 2: CHUẨN BỊ KUBESPRAY

### 4.1 Clone Kubespray repository

**Trên Control Machine:**

```bash
cd ~
git clone https://github.com/kubernetes-sigs/kubespray.git
cd kubespray
```

Kiểm tra version:
```bash
git branch -a
# Chọn version phù hợp (v2.24.0 hoặc mới hơn cho k8s 1.28+)
git checkout v2.24.0
```

### 4.2 Cài đặt Ansible dependencies

```bash
sudo apt-get install -y python3-pip
pip3 install --upgrade pip
pip3 install -r requirements.txt
```

Hoặc tạo virtual environment:
```bash
python3 -m venv kubespray-env
source kubespray-env/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
```

---

## V. BƯỚC 3: CẤU HÌNH INVENTORY

### 5.1 Tạo inventory từ template

```bash
cp -r inventory/sample inventory/mycluster
```

### 5.2 Tạo file inventory.ini

```bash
cat > inventory/mycluster/hosts.ini << 'EOF'
[all]
k8s-1 ansible_host=192.168.100.10 ansible_user=ubuntu
k8s-2 ansible_host=192.168.100.11 ansible_user=ubuntu
k8s-3 ansible_host=192.168.100.12 ansible_user=ubuntu

[kube_control_plane]
k8s-1

[kube_node]
k8s-2
k8s-3

[etcd]
k8s-1

[k8s_cluster:children]
kube_control_plane
kube_node
EOF
```

### 5.3 Cấu hình group_vars

Sửa file `inventory/mycluster/group_vars/all/all.yml`:

```bash
nano inventory/mycluster/group_vars/all/all.yml
```

Các cấu hình quan trọng:
```yaml
# Kubernetes version
kube_version: v1.28.0

# Pod network CIDR
kube_pods_subnet: 10.244.0.0/16
kube_pods_subnet_ipv6: fd85:ee78:d8a6:8607::1:0/112

# Service CIDR
kube_service_addresses: 10.96.0.0/12
kube_service_addresses_ipv6: fd85:ee78:d8a6:8607::1000:0/116
```

Sửa file `inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml`:

```bash
nano inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml
```

Các cấu hình CNI (chọn một):

**Option 1: Flannel (đơn giản, nhẹ)**
```yaml
kube_network_plugin: flannel
flannel_backend_type: vxlan
```

**Option 2: Calico (mạnh mẽ, hỗ trợ network policies)**
```yaml
kube_network_plugin: calico
calico_iptables_backend: "NFTables"
```

**Option 3: Cilium (hiệu suất cao, eBPF)**
```yaml
kube_network_plugin: cilium
cilium_enable_hubble: true
```

### 5.4 Cấu hình các tùy chọn khác

Trong `inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml`:

```yaml
# DNS
dns_mode: coredns
dns_replicas: 2

# Metrics Server
metrics_server_enabled: true

# Ingress Controller
ingress_nginx_enabled: true

# Container runtime
container_manager: containerd

# Kubernetes dashboard (tuỳ chọn)
dashboard_enabled: false
```

---

## VI. BƯỚC 4: XÁC MINH CẤU HÌNH TRƯỚC KHI TRIỂN KHAI

### 6.1 Test connectivity

```bash
ansible -i inventory/mycluster/hosts.ini all -m ping
```

Output mong đợi:
```
k8s-1 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
k8s-2 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
k8s-3 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

### 6.2 Kiểm tra Python trên remote hosts

```bash
ansible -i inventory/mycluster/hosts.ini all -m raw -a "python3 --version"
```

### 6.3 Xác minh SSH

```bash
ansible -i inventory/mycluster/hosts.ini all -a "whoami"
```

---

## VII. BƯỚC 5: TRIỂN KHAI KUBERNETES CLUSTER

### 7.1 Chạy kubespray playbook

```bash
cd ~/kubespray

# Tùy chọn 1: Triển khai đầy đủ
ansible-playbook -i inventory/mycluster/hosts.ini cluster.yml -v

# Tùy chọn 2: Triển khai với số luồng tăng (nhanh hơn)
ansible-playbook -i inventory/mycluster/hosts.ini cluster.yml -v -f 10

# Tùy chọn 3: Triển khai chỉ các tag cụ thể
ansible-playbook -i inventory/mycluster/hosts.ini cluster.yml --tags="bastion,bootstrap-os,preinstall,docker" -v
```

**Quá trình này sẽ:**
- Cài đặt container runtime (containerd)
- Cài đặt kubelet, kubeadm, kubectl
- Khởi tạo control plane
- Kết nối worker nodes
- Cấu hình network plugin
- Cài đặt addons (coredns, metrics-server, ingress-nginx)

### 7.2 Thời gian chờ

Triển khai thường mất **10-20 phút** tùy thuộc vào tốc độ mạng và phần cứng.

### 7.3 Xử lý lỗi

**Nếu playbook thất bại:**

```bash
# Xem logs chi tiết
ansible-playbook -i inventory/mycluster/hosts.ini cluster.yml -v -e "ansible_stdout_callback=debug"

# Retry playbook
ansible-playbook -i inventory/mycluster/hosts.ini cluster.yml -v --start-at-task="task_name"

# SSH vào node để debug
ssh -i ~/.ssh/id_ed25519 ubuntu@192.168.100.10
```

---

## VIII. BƯỚC 6: XÁC MINH CLUSTER KUBERNETES

### 8.1 Sao chép kubeconfig

Sau khi triển khai thành công, sao chép kubeconfig:

```bash
# Từ control machine hoặc từ master node
mkdir -p ~/.kube
scp ubuntu@192.168.100.10:/etc/kubernetes/admin.conf ~/.kube/config
chmod 600 ~/.kube/config
```

### 8.2 Kiểm tra cluster status

```bash
kubectl cluster-info
```

Expected output:
```
Kubernetes control plane is running at https://192.168.100.10:6443
CoreDNS is running at https://192.168.100.10:6443/api/v1/namespaces/kube-system/services/coredns:dns/proxy
```

### 8.3 Kiểm tra các node

```bash
kubectl get nodes
kubectl get nodes -o wide
```

Expected output:
```
NAME    STATUS   ROLES                  AGE   VERSION
k8s-1   Ready    control-plane,master   5m    v1.28.0
k8s-2   Ready    <none>                 4m    v1.28.0
k8s-3   Ready    <none>                 4m    v1.28.0
```

### 8.4 Kiểm tra pods trong kube-system

```bash
kubectl get pods -n kube-system
```

Expected output:
```
NAME                                        READY   STATUS    RESTARTS   AGE
coredns-558bd4d5db-xxx                      1/1     Running   0          3m
etcd-k8s-1                                  1/1     Running   0          4m
kube-apiserver-k8s-1                        1/1     Running   0          4m
kube-controller-manager-k8s-1               1/1     Running   0          4m
kube-flannel-xxx                            1/1     Running   0          3m
kube-flannel-xxx                            1/1     Running   0          3m
kube-flannel-xxx                            1/1     Running   0          3m
kube-proxy-xxx                              1/1     Running   0          3m
kube-proxy-xxx                              1/1     Running   0          3m
kube-scheduler-k8s-1                        1/1     Running   0          4m
```

### 8.5 Kiểm tra metrics-server

```bash
kubectl get deployment -n kube-system metrics-server
kubectl top nodes
```

### 8.6 Kiểm tra network connectivity

Test ping giữa pods trên các node khác nhau:

```bash
# Tạo test pod trên k8s-2
kubectl run test-pod-1 --image=busybox --rm -it -- /bin/sh

# Trong pod shell
ping google.com
exit

# Tạo pod khác trên k8s-3 và ping pod đầu tiên
```

---

## IX. BƯỚC 7: TEST TRIỂN KHAI

### 9.1 Triển khai ứng dụng sample

```bash
kubectl create deployment nginx --image=nginx:latest --replicas=3
kubectl expose deployment nginx --port=80 --target-port=80 --type=LoadBalancer
kubectl get svc nginx
```

### 9.2 Kiểm tra pods

```bash
kubectl get pods -o wide
```

### 9.3 Truy cập ứng dụng

```bash
# Port-forward (nếu không có LoadBalancer)
kubectl port-forward svc/nginx 8080:80

# Từ máy khác, truy cập: http://localhost:8080
```

### 9.4 Xem logs

```bash
kubectl logs -f deployment/nginx
```

### 9.5 Dọn dẹp

```bash
kubectl delete deployment nginx
kubectl delete svc nginx
```

---

## X. TROUBLESHOOTING

### 10.1 Node không ready

```bash
# Kiểm tra tình trạng node
kubectl describe node k8s-2

# Kiểm tra kubelet logs
ssh ubuntu@192.168.100.11
sudo journalctl -u kubelet -f

# Kiểm trap cni
sudo ls -la /etc/cni/net.d/
```

### 10.2 Pods pending

```bash
# Mô tả pod để thấy sự kiện
kubectl describe pod <pod-name> -n kube-system

# Kiểm tra resource limits
kubectl describe nodes

# Kiểm tra network plugin
kubectl get daemonset -n kube-system
```

### 10.3 API server không accessible

```bash
# SSH vào master node
ssh ubuntu@192.168.100.10

# Kiểm tra API server container
sudo crictl ps | grep kube-apiserver

# Kiểm tra logs
sudo journalctl -u kubelet -n 50

# Kiểm tra port 6443
sudo netstat -tlnp | grep 6443
```

### 10.4 DNS issues

```bash
# Test DNS từ pod
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup kubernetes.default

# Kiểm tra coredns
kubectl logs -f deployment/coredns -n kube-system

# Kiểm tra resolv.conf trên node
ssh ubuntu@192.168.100.10
cat /etc/resolv.conf
```

### 10.5 Xóa và triển khai lại

```bash
# Reset cluster (từ kubespray directory)
ansible-playbook -i inventory/mycluster/hosts.ini reset.yml -v

# Sau đó triển khai lại
ansible-playbook -i inventory/mycluster/hosts.ini cluster.yml -v
```

---

## XI. NÂNG CAO

### 11.1 Thêm worker node mới

```bash
# Thêm node mới vào hosts.ini
[kube_node]
k8s-2
k8s-3
k8s-4  # node mới

# Chạy scale playbook
ansible-playbook -i inventory/mycluster/hosts.ini scale.yml -v
```

### 11.2 Cập nhật Kubernetes version

```bash
# Sửa kube_version trong group_vars
kube_version: v1.29.0

# Chạy upgrade playbook
ansible-playbook -i inventory/mycluster/hosts.ini upgrade-cluster.yml -v
```

### 11.3 Cấu hình persistent volume

```bash
# Cài đặt local-path-provisioner
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml

# Hoặc tạo PV thủ công
```

### 11.4 Cấu hình RBAC

```bash
# Tạo ServiceAccount
kubectl create serviceaccount myapp -n default

# Tạo Role
kubectl create role myrole --verb=get,list,watch --resource=pods -n default

# Tạo RoleBinding
kubectl create rolebinding myrole-binding --role=myrole --serviceaccount=default:myapp -n default
```

---

## XII. CHECKLIST HOÀN THÀNH LAB

- [ ] Tất cả 3 node được cài đặt Ubuntu 24.04 LTS
- [ ] SSH không cần mật khẩu được cấu hình
- [ ] Swap bị vô hiệu hóa trên tất cả node
- [ ] Kubespray được clone và dependencies được cài đặt
- [ ] Inventory được cấu hình chính xác
- [ ] Ansible ping all nodes thành công
- [ ] Kubespray playbook chạy thành công
- [ ] `kubectl get nodes` hiển thị 3 node ở trạng thái Ready
- [ ] Tất cả pods trong kube-system ở trạng thái Running
- [ ] Test deployment nginx chạy thành công
- [ ] Network connectivity giữa pods hoạt động

---

## XIII. TÀI LIỆU THAM KHẢO

- Kubespray GitHub: https://github.com/kubernetes-sigs/kubespray
- Kubernetes Documentation: https://kubernetes.io/docs
- Container Networks: https://www.cni.dev/
- CNI Plugins: https://github.com/containernetworking/plugins

---

**Ghi chú:** Tài liệu này được tạo cho mục đích học tập. Đảm bảo thực hành trong môi trường lab, không sử dụng trực tiếp cho production mà không có kinh nghiệm.
