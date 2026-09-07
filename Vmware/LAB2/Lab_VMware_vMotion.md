# LAB THỰC HÀNH: Tạo Máy Ảo và Thực Hiện vMotion trong VMware vCenter

## Mục tiêu bài lab

Sau khi hoàn thành bài lab, học viên có thể:

- Tạo mới một máy ảo (VM) trên ESXi host thông qua vCenter
- Cấu hình VMkernel Adapter dành riêng cho vMotion
- Tạo và cấu hình Distributed Switch (vDS) cho hạ tầng vMotion
- Thực hiện di chuyển VM đang chạy giữa hai host (vMotion) không gián đoạn dịch vụ
- Xác định nguyên nhân và xử lý các lỗi vMotion thường gặp

## Yêu cầu hạ tầng (Lab Topology)

| Thành phần | Số lượng | Ghi chú |
|---|---|---|
| vCenter Server Appliance (VCSA) | 1 | Quản lý cả 2 ESXi host |
| ESXi Host | 2 (ESXi-A, ESXi-B) | Cùng version, cùng CPU family (hoặc bật EVC) |
| Shared Datastore | 1 | NFS hoặc iSCSI, cả 2 host cùng thấy |
| Card mạng (pNIC) mỗi host | ≥ 2 | 1 cho Management, 1 cho vMotion (khuyến nghị tách riêng) |
| Máy trạm quản trị | 1 | Trình duyệt truy cập vCenter (HTML5 Client) |

**Sơ đồ mạng dự kiến:**

```
                     ┌────────────────────┐
                     │   vCenter Server    │
                     └──────────┬──────────┘
                                │ quản lý
        ┌───────────────────────┴───────────────────────┐
        │                                                │
 ┌──────────────┐                                ┌──────────────┐
 │  ESXi-Host-A  │                                │  ESXi-Host-B  │
 │  Mgmt: vmnic0 │◀── VLAN 10 (Management) ──────▶│  Mgmt: vmnic0 │
 │  vMotion:vmnic1│◀── VLAN 20 (vMotion, isolated)─▶│  vMotion:vmnic1│
 └──────┬────────┘                                └────────┬──────┘
        │                                                   │
        └─────────────────── Shared Datastore ──────────────┘
                          (NFS/iSCSI - VMFS)
```

## Checklist chuẩn bị trước khi bắt đầu

- [ ] Đã đăng nhập được vào vCenter bằng HTML5 Client
- [ ] Cả 2 ESXi host đã join vào cùng 1 Datacenter/Cluster trong vCenter
- [ ] Đã cấu hình Shared Datastore, cả 2 host cùng nhìn thấy
- [ ] Mỗi host có tối thiểu 2 pNIC còn trống (chưa gán vSwitch)
- [ ] Đã có file ISO hệ điều hành (VD: Ubuntu Server, Windows) để cài VM test
- [ ] Kiểm tra thời gian NTP đồng bộ giữa các host

---

## PHẦN 1 — Tạo Máy Ảo (VM) Test

### Bước 1.1: Khởi tạo New Virtual Machine

1. Vào **vCenter > Hosts and Clusters**, chuột phải vào Cluster/Host → **New Virtual Machine**
2. Chọn **Create a new virtual machine** → Next
3. Đặt tên VM: `VM-Test-vMotion-01`
4. Chọn vị trí (Datacenter/Folder) lưu VM
5. Chọn **Compute Resource**: ESXi-Host-A (host nguồn)
6. Chọn **Storage**: chọn **Shared Datastore** (bắt buộc — không chọn local datastore, vì vMotion compute cần shared storage)

### Bước 1.2: Cấu hình phần cứng ảo

| Thông số | Giá trị đề xuất |
|---|---|
| Guest OS Family | Linux / Windows (tùy ISO) |
| CPU | 2 vCPU |
| RAM | 2 GB |
| Hard Disk | 20 GB, Thin Provision |
| Network Adapter | Gán vào Port Group **VM-Network** (port group của VM traffic, không phải vMotion) |
| CD/DVD Drive | Datastore ISO File → trỏ đến file ISO cài đặt |

> ⚠️ **Lưu ý quan trọng cho vMotion:** không được gắn ISO ở dạng **Client Device** (ổ đĩa vật lý/local trên máy trạm) — đây là nguyên nhân phổ biến gây lỗi vMotion "device is not accessible" sau này. Luôn dùng **Datastore ISO File**.

### Bước 1.3: Cài đặt hệ điều hành

1. Power On VM
2. Mở **Console**, cài đặt OS theo ISO đã chọn
3. Cài xong, gỡ kết nối ISO (Edit Settings > CD/DVD > Disconnected) để tránh vướng khi test vMotion
4. Đặt IP tĩnh cho VM, kiểm tra ping thông tới gateway

**✅ Checklist Phần 1:**
- [ ] VM đã tạo thành công và Power On được
- [ ] VM đang nằm trên Shared Datastore (không phải local datastore)
- [ ] Không còn ISO gắn kiểu Client Device
- [ ] VM có IP, ping thông ra ngoài

---

## PHẦN 2 — Cấu hình VMkernel Adapter cho vMotion

### Bước 2.1: Tạo VMkernel Adapter trên từng host

Thực hiện trên **cả ESXi-Host-A và ESXi-Host-B**:

```
vCenter > Hosts and Clusters > chọn Host
  → Configure > Networking > VMkernel Adapters
  → Add Networking
    → Select connection type: VMkernel Network Adapter
    → Select target device: New Distributed Port Group (hoặc chọn vSwitch có sẵn)
    → Port properties:
        - Enable services: ✅ vMotion traffic
        - (không tick Management traffic ở đây)
    → IPv4 settings: gán IP tĩnh, ví dụ:
        ESXi-Host-A: 192.168.20.11/24
        ESXi-Host-B: 192.168.20.12/24
```

### Bước 2.2: Bảng cấu hình tham chiếu

| Host | VMkernel Port | IP | VLAN | Service Enabled |
|---|---|---|---|---|
| ESXi-Host-A | vmk1 | 192.168.20.11/24 | VLAN 20 | vMotion |
| ESXi-Host-B | vmk1 | 192.168.20.12/24 | VLAN 20 | vMotion |

> 📌 Hai VMkernel vMotion phải **cùng subnet/VLAN L2** (trừ khi dùng Routed vMotion từ vSphere 6.0 trở lên, yêu cầu cấu hình static route riêng).

### Bước 2.3: Kiểm tra kết nối giữa 2 VMkernel

Từ ESXi shell (SSH vào host) hoặc qua vCenter Host Client:

```bash
# Trên ESXi-Host-A, ping tới VMkernel vMotion của Host-B
vmkping -I vmk1 192.168.20.12

# Kiểm tra chi tiết interface vmk1
esxcli network ip interface list
esxcli network ip interface ipv4 get
```

Kết quả mong đợi: **0% packet loss**.

**✅ Checklist Phần 2:**
- [ ] Cả 2 host đều có VMkernel adapter riêng, gắn service "vMotion traffic"
- [ ] IP 2 VMkernel cùng subnet, ping thông qua `vmkping`
- [ ] Không có host nào tick nhầm "vMotion" lên VMkernel Management

---

## PHẦN 3 — Tạo Distributed Switch (vDS) cho vMotion

> Distributed Switch giúp cấu hình network đồng nhất giữa nhiều host, thay vì cấu hình lặp lại vSwitch chuẩn (Standard Switch) trên từng host — rất hữu ích khi mở rộng cluster nhiều host.

### Bước 3.1: Tạo mới vDS

```
vCenter > Networking > chuột phải Datacenter
  → Distributed Switch > New Distributed Switch
    → Name: dvSwitch-vMotion
    → Version: chọn version tương thích ESXi đang dùng
    → Number of uplinks: 2 (để có redundancy)
    → Create a default port group: bỏ chọn (sẽ tạo riêng ở bước sau)
```

### Bước 3.2: Tạo Distributed Port Group riêng cho vMotion

```
Chuột phải vào dvSwitch-vMotion → Distributed Port Group > New Distributed Port Group
  → Name: PG-vMotion
  → VLAN type: VLAN, VLAN ID = 20
  → Advanced: Customize policies configuration (tick để cấu hình Teaming ở bước sau)
```

### Bước 3.3: Add hosts vào Distributed Switch

```
Chuột phải dvSwitch-vMotion → Add and Manage Hosts
  → Add hosts → chọn ESXi-Host-A, ESXi-Host-B
  → Manage physical adapters: gán vmnic1 (dự phòng vmnic2 nếu có) làm Uplink
  → Manage VMkernel adapters: migrate vmk1 (vMotion) đã tạo ở Phần 2 sang PG-vMotion
```

### Bước 3.4: Cấu hình Teaming and Failover (đảm bảo Network Redundancy)

```
PG-vMotion > Edit Settings > Teaming and Failover
  → Load balancing: Route based on physical NIC load (khuyến nghị)
  → Active uplinks: uplink1, uplink2 (cả 2 đều active)
  → Standby uplinks: (để trống hoặc cấu hình dự phòng tùy hạ tầng)
```

> 📌 Đây chính là bước khắc phục lỗi **"vMotion interface is not configured for redundancy"** — cảnh báo này xuất hiện khi PG-vMotion chỉ có **1 uplink active duy nhất**, không có failover.

**✅ Checklist Phần 3:**
- [ ] dvSwitch-vMotion đã tạo, cả 2 host đã join
- [ ] PG-vMotion có VLAN ID đúng, có ít nhất 2 uplink active
- [ ] VMkernel vmk1 (vMotion) đã migrate thành công sang PG-vMotion
- [ ] Kiểm tra lại `vmkping` giữa 2 host vẫn thông sau khi migrate network

---

## PHẦN 4 — Thực hiện Test vMotion

### Bước 4.1: Kiểm tra điều kiện tiên quyết (Compatibility Check)

Trước khi migrate, vCenter tự chạy compatibility check. Học viên có thể tự rà soát trước:

| Điều kiện | Cách kiểm tra |
|---|---|
| CPU tương thích | Cluster > Configure > VMware EVC — nếu CPU khác đời, cần bật EVC baseline phù hợp |
| Shared Storage | Datastore của VM phải hiển thị "Accessible" trên cả 2 host |
| Port Group đích tồn tại trên host đích | Host-B > Configure > Networking > Virtual switches — kiểm tra có PG "VM-Network" trùng tên |
| VM không gắn thiết bị local | Edit Settings VM — không còn CD/DVD Client Device, USB passthrough |
| VMkernel vMotion hoạt động | `vmkping` giữa 2 host phải thông |

### Bước 4.2: Thực hiện Migrate VM

```
vCenter > VMs and Templates > chuột phải VM-Test-vMotion-01 → Migrate
  → Migration type: Change compute resource only  (Compute vMotion)
  → Destination: ESXi-Host-B
  → Select Networks: giữ nguyên PG "VM-Network" (không đổi network)
  → Select vMotion priority: Reserve CPU for optimal migration (mặc định)
  → Finish
```

### Bước 4.3: Theo dõi và xác nhận

1. Theo dõi tiến trình ở tab **Recent Tasks**
2. Trong lúc migrate, mở **liên tục ping** đến IP của VM từ máy khác:

```bash
ping -t 192.168.1.100    # Windows
ping 192.168.1.100       # Linux/Mac, Ctrl+C để dừng
```

3. Kỳ vọng: **tối đa 1–2 gói ping timeout** (thường 0 gói mất, tuỳ hạ tầng), VM không bị reboot, session SSH/RDP vào VM (nếu có) không bị ngắt.
4. Sau khi hoàn tất, kiểm tra tab **Summary** của VM để xác nhận host hiện tại đã đổi sang ESXi-Host-B.

**✅ Checklist Phần 4:**
- [ ] Compatibility check pass, không có cảnh báo đỏ
- [ ] Task "Migrate virtual machine" hiển thị **Completed** 100%
- [ ] VM đang chạy trên ESXi-Host-B, IP/network không đổi
- [ ] Ping liên tục trong lúc test không bị mất gói kéo dài (mất kết nối)

---

## PHẦN 5 — Troubleshooting: Các lỗi vMotion thường gặp

### 5.1. Bảng lỗi và cách xử lý

| Lỗi thường gặp | Nguyên nhân phổ biến | Cách xử lý |
|---|---|---|
| **Compatibility checks failed** | CPU giữa 2 host khác family/thế hệ, không bật EVC | Vào Cluster > Configure > VMware EVC → Enable EVC, chọn baseline thấp nhất tương thích cả 2 CPU. Có thể cần Power Off VM để đổi EVC lần đầu |
| **No network redundancy** | Port Group vMotion chỉ có 1 uplink active, không có standby/active thứ 2 | Edit Teaming and Failover trên Port Group vMotion, thêm uplink thứ 2 vào Active uplinks |
| **Device is not accessible** | VM đang gắn CD/DVD ở chế độ Client Device hoặc USB passthrough vật lý | Edit Settings VM → Disconnect hoặc gỡ thiết bị local trước khi migrate |
| **The VM failed to resume on the destination during early power on** | Thiếu tài nguyên (CPU reservation, RAM) trên host đích, hoặc datastore không kịp đồng bộ | Kiểm tra tài nguyên trống trên host đích; kiểm tra Storage latency |
| **Currently connected device 'Network adapter' uses backing 'VM Network', which is not accessible** | Port Group nguồn không tồn tại/không cùng tên trên host đích | Tạo Port Group cùng tên (hoặc dùng chung Distributed Switch) trên cả 2 host |
| **vMotion migration [xxx] failed to create a connection with the remote host** | VMkernel vMotion không thông (sai VLAN, firewall chặn) | Chạy `vmkping -I vmk1 <IP đích>`; kiểm tra firewall ESXi cho phép port TCP 8000, 8100, 8200 (vMotion) |
| **Timed out waiting for migration data** | Băng thông vMotion quá thấp hoặc đường truyền lỗi (MTU không khớp) | Kiểm tra MTU đồng nhất (thường 1500 hoặc 9000) giữa vSwitch, port group, và switch vật lý |
| **A general system error occurred: Failed to reserve resources on host** (đủ RAM nhưng vẫn lỗi) | Bật Admission Control quá chặt ở mức Cluster (HA) | Configure > vSphere Availability > Admission Control, nới policy tạm thời để test |

### 5.2. Câu lệnh hỗ trợ chẩn đoán (ESXi Shell / SSH)

```bash
# Kiểm tra danh sách VMkernel interface và service enable
esxcli network ip interface list

# Kiểm tra bảng định tuyến, xác nhận VMkernel vMotion đúng subnet
esxcli network ip route ipv4 list

# Test kết nối VMkernel vMotion tới host đích (dùng đúng source interface)
vmkping -I vmk1 <IP_VMkernel_dich> -s 8972 -d   # test luôn MTU 9000 (Jumbo Frame)

# Xem log vMotion chi tiết (khi task fail)
tail -f /var/log/vmkernel.log | grep -i vmotion
tail -f /var/log/hostd.log | grep -i migrat

# Kiểm tra firewall rule cho phép vMotion
esxcli network firewall ruleset list | grep -i vmotion
esxcli network firewall ruleset set --ruleset-id vMotion --enabled true
```

### 5.3. Quy trình xử lý sự cố đề xuất (Troubleshooting Flow)

```
Migrate FAILED
   │
   ├─▶ Có báo "Compatibility check failed"?
   │     └─ Có → Kiểm tra CPU family / bật EVC ở Cluster
   │
   ├─▶ Có báo lỗi liên quan Network/Device?
   │     └─ Có → Kiểm tra Port Group đích tồn tại + gỡ Client Device/USB
   │
   ├─▶ Có báo "no network redundancy" (chỉ warning, không chặn)?
   │     └─ Có → Bổ sung uplink active thứ 2 cho PG-vMotion
   │
   ├─▶ Migrate bị treo / timeout giữa chừng?
   │     └─ vmkping test → kiểm tra MTU, VLAN, firewall port 8000/8100/8200
   │
   └─▶ Vẫn fail sau các bước trên?
         └─ Đọc log chi tiết: vmkernel.log, hostd.log, vpxd.log (trên VCSA)
```

**✅ Checklist Phần 5:**
- [ ] Học viên tái tạo được ít nhất 2 lỗi trong bảng (VD: gỡ EVC để gây compatibility check failed, tắt 1 uplink để gây no network redundancy)
- [ ] Học viên đọc và diễn giải được log `vmkernel.log`/`hostd.log` liên quan vMotion
- [ ] Học viên tự khắc phục và migrate lại thành công

---

## Bài tập mở rộng (tùy chọn, nâng cao)

1. Thử cấu hình **Storage vMotion**: di chuyển VM sang datastore khác trong khi vẫn giữ nguyên host — so sánh sự khác biệt về network traffic so với Compute vMotion.
2. Bật **Encrypted vMotion** (VM Options > Encryption > vMotion Encryption = Required) và quan sát chênh lệch thời gian migrate.
3. Giả lập tình huống mất kết nối VMkernel vMotion giữa chừng (rút cáp/disable uplink) khi đang migrate — quan sát vCenter xử lý rollback ra sao.
4. So sánh thời gian migrate giữa VM có RAM 2GB và RAM 8GB có tải CPU cao (stress-test) để hiểu ảnh hưởng của "dirty page rate" tới vMotion.

---

## Tài liệu tham khảo nội bộ

- Yêu cầu hạ tầng: shared storage NFS/iSCSI, VMkernel riêng cho vMotion, băng thông ≥ 1Gbps (khuyến nghị 10Gbps)
- Cổng vMotion mặc định: TCP 8000, 8100, 8200 (ESXi 6.x trở lên)
- EVC (Enhanced vMotion Compatibility): bắt buộc khi cluster có CPU khác đời để tránh lỗi compatibility check
