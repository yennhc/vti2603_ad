# BÀI LAB: VCENTER SERVER

**From Beginner to Advanced Level**

Mục tiêu: Nắm vững cấu trúc vCenter, quản lý tài nguyên, và tối ưu hóa hiệu suất hạ tầng ảo hóa

Thời gian: 3-4 tuần (30+ giờ thực hành)

Yêu cầu: ESXi 7.0+, VMware Workstation/Fusion, 32GB RAM khuyến nghị

---

## MỤC LỤC

### PHẦN 1: BEGINNER (Tuần 1-2)

- 1.1 Giới thiệu vCenter
- 1.2 Cài đặt vCenter Server
- 1.3 Kết nối ESXi Hosts
- 1.4 Quản lý VMs cơ bản
- 1.5 Networking cơ bản

### PHẦN 2: INTERMEDIATE (Tuần 2-3)

- 2.1 Resource Pools và Reservations
- 2.2 Datastore Management
- 2.3 Permissions và Roles
- 2.4 vSphere Clustering
- 2.5 Monitoring cơ bản

### PHẦN 3: ADVANCED (Tuần 3-4)

- 3.1 vMotion và Storage vMotion
- 3.2 DRS (Distributed Resource Scheduler)
- 3.3 High Availability (HA)
- 3.4 Performance Tuning
- 3.5 Troubleshooting & Optimization

---

## PHẦN 1: BEGINNER

### 1.1 Giới thiệu vCenter Server

vCenter Server là trung tâm quản lý tập trung của vSphere. Nó cung cấp quản lý tài nguyên, monitoring, security, và automation cho tất cả ESXi hosts và VMs trong infrastructure.

Các thành phần chính:

- vCenter Server (Appliance hoặc Windows-based)
- ESXi Hosts
- vSphere Client (Web UI + Traditional Client)
- Single Sign-On (SSO)
- Platform Services Controller (PSC)
- Database (embedded hoặc external)

### 1.2 Cài đặt vCenter Server

#### Bước 1: Chuẩn bị môi trường

| Yêu cầu | Chi tiết |
|----------|----------|
| CPU | Tối thiểu 4 cores, khuyến nghị 8+ cores |
| RAM | Tối thiểu 8GB, khuyến nghị 16-32GB |
| Storage | Tối thiểu 60GB, khuyến nghị 200GB+ SSD |
| Network | 1 Gbps network card, có thể là 10 Gbps |

#### Bước 2: Tải về và cài đặt vCenter Appliance

- Tải VMware vCenter Server Appliance từ vmware.com
- Deploy OVA file vào ESXi host bằng vSphere Client
- Cấu hình network: Hostname, IP address, DNS, gateway
- Thiết lập root password
- Chọn Deployment Type: Embedded (1 ESXi) hoặc External (nhiều ESXi)
- Chọn datastore cho vCenter

#### BÀI TẬP 1.1: Cài đặt vCenter Appliance

- Triển khai vCenter Server Appliance trên ESXi host của bạn
- Hoàn thành Initial Setup (SSO configuration)
- Truy cập vSphere Web Client (`https://<vCenter_IP>/ui`)
- Tạo account và kiểm tra dashboard

### 1.3 Kết nối ESXi Hosts

vCenter quản lý ESXi hosts thông qua kết nối mạng. Sau khi vCenter chạy, bạn cần thêm hosts vào inventory.

#### Bước 1: Thêm ESXi Host vào vCenter

- Mở vSphere Client → Hosts and Clusters
- Right-click on Datacenter → Add Host
- Nhập hostname/IP của ESXi host
- Cung cấp username/password (root/password)
- Chọn SSL Certificate (nếu cảnh báo)
- Chọn License (nếu cần)
- Hoàn thành việc thêm host

#### BÀI TẬP 1.2: Kết nối Multiple ESXi Hosts

- Chuẩn bị ít nhất 2-3 ESXi hosts (có thể dùng VMs nếu bị hạn chế tài nguyên)
- Thêm tất cả hosts vào vCenter
- Kiểm tra status của mỗi host (xanh = healthy)
- Ghi lại IP address, hostname của từng host

### 1.4 Quản lý VMs Cơ bản

Quy trình tạo và quản lý Virtual Machine

#### Bước 1: Tạo VM mới

- Right-click on Host → New Virtual Machine
- Chọn: Create a new virtual machine
- Đặt tên VM, chọn Compute Resource (ESXi host)
- Chọn Storage (datastore)
- Cấu hình: OS, CPU, Memory, Disk
- Chọn Network (VM network adapter)
- Hoàn thành tạo VM

#### Bước 2: Cài đặt OS trên VM

- Power on VM
- Mở Console của VM
- Cài đặt OS (Ubuntu, CentOS, Windows...)
- Cài đặt VMware Tools
- Cấu hình network trên VM

#### BÀI TẬP 1.3: Tạo VM Farm

- Tạo 3 VMs: 1x Ubuntu 22.04, 1x CentOS 8, 1x Windows Server 2022
- Cấu hình: 2 vCPU, 4GB RAM, 50GB disk cho mỗi VM
- Cài đặt OS, VMware Tools trên tất cả VMs
- Kiểm tra kết nối mạng giữa các VMs
- Ghi chép: tên VM, OS, IP address, resource allocation

### 1.5 Networking Cơ bản

Hiểu cấu trúc mạng trong vSphere

Kiến thức cơ bản:

- **Virtual Switch (vSwitch)**: Kết nối VMs với mạng vật lý
- **Port Groups**: Nhóm cổng cho VMs, định nghĩa VLAN
- **VMkernel**: Network trên ESXi để vCenter kết nối
- **Physical Network Adapters**: NIC vật lý trên ESXi

#### BÀI TẬP 1.4: Cấu hình vSwitch và Port Groups

- Tạo Virtual Switch: vSwitch1
- Thêm Physical NIC vào vSwitch1
- Tạo Port Group: Management, VM-Network, Storage
- Gán VMs vào Port Groups khác nhau
- Kiểm tra kết nối bằng ping giữa các Network

---

## PHẦN 2: INTERMEDIATE

### 2.1 Resource Pools và Reservations

Resource Pools cho phép quản lý tài nguyên (CPU, Memory) một cách linh hoạt giữa các VMs.

Khái niệm chính:

- **Reservation**: Tài nguyên đảm bảo cho một pool/VM
- **Limit**: Giới hạn tối đa tài nguyên mà một pool/VM có thể sử dụng
- **Shares**: Ưu tiên tài nguyên khi contention xảy ra
- **Expandable**: Cho phép pool con được cấp phát tài nguyên từ pool cha

#### BÀI TẬP 2.1: Tạo và Cấu hình Resource Pools

- Tạo Resource Pool hierarchy:
  - Production (40GB RAM, 16 vCPU)
  - Development (20GB RAM, 8 vCPU)
  - Test (10GB RAM, 4 vCPU)
- Cấu hình Reservations và Limits cho mỗi pool
- Di chuyển VMs vào các Resource Pools phù hợp
- Kiểm tra Resource allocation qua vCenter

### 2.2 Datastore Management

Quản lý lưu trữ cho VMs và snapshots

#### Bước 1: Thêm Datastore

- Chuẩn bị LUN trên SAN/NAS (hoặc dùng local storage)
- vCenter → Storage → Datastores → New Datastore
- Chọn ESXi hosts để mount datastore
- Định dạng filesystem: VMFS 6/7 hoặc NFS

#### Bước 2: Monitoring Datastore

- Kiểm tra capacity, free space
- Monitor I/O performance (latency, throughput)
- Tạo alarm khi datastore đầy trên 80%

#### BÀI TẬP 2.2: Quản lý Multiple Datastores

- Tạo 2-3 datastores: Local-Storage, SAN-Primary, SAN-Secondary
- Di chuyển VMs giữa datastores (dùng Storage vMotion)
- Tạo snapshots và kiểm tra space consumption
- Monitor datastore performance
- Thiết lập alarms và thực hành cleanup

### 2.3 Permissions và Roles

Quản lý quyền truy cập trong vCenter

Các Role cơ bản:

| Role | Quyền hạn |
|------|-----------|
| Administrator | Toàn quyền quản lý |
| Virtual Machine Admin | Quản lý VMs, snapshots |
| Virtual Machine User | Power on/off, console access |
| Read Only | Chỉ xem thông tin |

#### BÀI TẬP 2.3: Tạo Users và Gán Permissions

- Tạo các user: admin-prod, dev-user1, dev-user2, readonly-user
- Gán roles: admin-prod (Administrator), dev-users (VM Admin), readonly (Read-Only)
- Gán permissions scope: Datacenters, Resource Pools
- Test login với từng user và xác minh quyền hạn
- Tạo custom roles nếu cần (ví dụ: 'Storage Admin')

### 2.4 vSphere Clustering

Nhóm ESXi hosts lại để quản lý tập trung và cải thiện tính sẵn sàng

#### Bước tạo Cluster:

- vCenter → Hosts and Clusters → New Cluster
- Đặt tên cluster (ví dụ: Production-Cluster)
- Chọn features: HA, DRS, vSAN... (sẽ dùng ở Advanced)
- Thêm ESXi hosts vào cluster
- Tạo VM Folder trong cluster

#### BÀI TẬP 2.4: Tạo Cluster và Cấu hình

- Tạo 2 clusters: 'Prod-Cluster', 'Dev-Cluster'
- Thêm ESXi hosts vào clusters (tối thiểu 2-3 hosts/cluster)
- Tạo VM Folders: Prod-VMs, Dev-VMs
- Migrate VMs vào các clusters phù hợp

### 2.5 Monitoring Cơ bản

Sử dụng vCenter's built-in monitoring

#### BÀI TẬP 2.5: Thiết lập Monitoring

- Truy cập vCenter → Performance tabs
- Monitor: CPU, Memory, Disk, Network
- Tạo alarms: High CPU (>80%), Low Memory (<20%), Disk Space
- Kiểm tra Events log trong vCenter

---

## PHẦN 3: ADVANCED

### 3.1 vMotion và Storage vMotion

Chuyển đổi VMs giữa các ESXi hosts hoặc datastores mà không downtime

vMotion Requirements:

- 64-bit CPU compatible (same CPU family)
- Shared storage (NFS/iSCSI) hoặc VMFS datastore
- VMkernel network (vMotion enabled)
- Gigabit network tối thiểu

#### Quy trình vMotion:

- Right-click VM → Migrate
- Chọn Destination Host
- Chọn Priority: Scheduling, High
- Xác nhận → VM sẽ chuyển đổi

Storage vMotion: Di chuyển disk data sang datastore khác

#### BÀI TẬP 3.1: Thực hành vMotion

- Thiết lập vMotion network trên tất cả ESXi hosts
- Perform cold migration (power off VM, di chuyển, power on)
- Perform hot vMotion (VM running, di chuyển mà không downtime)
- Perform Storage vMotion (di chuyển disk sang datastore khác)
- Monitor network traffic khi vMotion diễn ra

### 3.2 DRS (Distributed Resource Scheduler)

Tự động cân bằng tài nguyên CPU/Memory giữa các VMs trong cluster

DRS Levels:

| Level | Hành động |
|-------|-----------|
| Manual | Đề xuất vMotion (admin quyết định) |
| Partially Automated | Tự động khi VM power on; đề xuất sau đó |
| Fully Automated | Tự động migrate VMs liên tục |

#### BÀI TẬP 3.2: Cấu hình DRS

- Kích hoạt DRS trên cluster (Cluster Settings)
- Cấu hình DRS Level: Partially Automated
- Tạo VM anti-affinity rules (VMs không chạy trên cùng host)
- Giám sát DRS recommendations
- Nâng cấp lên Fully Automated sau 1 tuần quan sát

### 3.3 High Availability (HA)

Bảo vệ VMs khỏi ESXi host failures bằng cách restart VMs trên host khác

HA Configuration:

- **Admission Control**: Đảm bảo cluster có capacity dự phòng
- **Isolation Response**: Hành động khi host isolation xảy ra
- **VM Monitoring**: Khôi phục VMs khi guest OS crash
- **Datastore Heartbeat**: Phát hiện host failures

#### BÀI TẬP 3.3: Cấu hình HA

- Kích hoạt HA trên cluster (tối thiểu 3 hosts)
- Cấu hình Admission Control: Reserve 1 host
- Bật VM Monitoring
- Shutdown một ESXi host → Xem VMs restart trên host khác
- Kiểm tra Events log để hiểu HA hoạt động

### 3.4 Performance Tuning

Tối ưu hóa hiệu suất hạ tầng ảo hóa

Best Practices:

- **CPU**: Tránh over-commitment (CPU ratio tối đa 4:1)
- **Memory**: Bật transparent page sharing, memory compression
- **Storage**: Sử dụng thick provisioning cho critical VMs
- **Network**: Tách vMotion, storage, management vào các networks riêng
- **VM Config**: 1 vCPU/2GB RAM là baseline, scale up nếu cần

#### BÀI TẬP 3.4: Performance Analysis

- Chạy workload stressor trên VMs (stress-ng, sysbench)
- Monitor performance metrics: CPU %, Memory %, Disk I/O, Network
- Xác định performance bottleneck
- Implement tuning changes (VM resizing, host balancing)
- Đo lường improvement sau tuning

### 3.5 Troubleshooting & Optimization

Giải quyết các vấn đề thường gặp

Các vấn đề phổ biến:

- Host không kết nối được → Kiểm tra network, ESXi services
- VM không power on → Kiểm tra resource, datastore, licenses
- vMotion failed → Kiểm tra network, CPU compatibility, memory
- High latency → Check network configuration, NIC drivers
- Datastore lock → Cleanup orphaned files, khôi động services

#### BÀI TẬP 3.5: Troubleshooting Scenarios

- **Scenario 1**: Simulate ESXi host network failure → Kiểm tra HA reaction
- **Scenario 2**: Datastore space full → Implement cleanup strategy
- **Scenario 3**: VM high memory usage → Troubleshoot root cause
- **Scenario 4**: vMotion network congestion → Optimize network
- Ghi lại từng troubleshooting step và resolution

---

## ĐÁNH GIÁ CUỐI

### Bài kiểm tra thực hành cuối khóa

Sinh viên phải hoàn thành:

- Xây dựng infrastructure: vCenter + 3+ ESXi hosts + clustered
- Tạo VM farm: 5+ VMs với OS khác nhau, networking riêng
- Cấu hình Resource Pools: 3+ levels với reservations/limits
- Thiết lập High Availability: HA enabled, tested with host shutdown
- Thực hiện vMotion: Hot vMotion, Storage vMotion với monitoring
- Performance optimization: Baseline test → Tuning → Re-test
- Troubleshooting report: Document 3+ scenarios và resolution
- Presentation: 20-30 phút trình bày infrastructure design

### Rubric (100 điểm):

| Criterion | Points | Notes |
|-----------|--------|-------|
| Infrastructure Setup | 20 | vCenter + 3+ hosts, clustered |
| VM Configuration | 15 | 5+ VMs, diverse OSes |
| Resource Management | 15 | Resource Pools, Reservations |
| High Availability | 15 | HA enabled, failover tested |
| Performance Testing | 15 | vMotion, DRS, tuning |
| Documentation | 5 | Clear, detailed troubleshooting log |

### Kết luận

Sau khóa lab này, sinh viên sẽ có khả năng:

- Thiết kế và triển khai vCenter infrastructure
- Quản lý VMs, resources, datastores một cách hiệu quả
- Cấu hình HA, DRS, vMotion cho uptime cao
- Optimize performance và xử lý sự cố
- Sẵn sàng cho VCP-DCV exam
