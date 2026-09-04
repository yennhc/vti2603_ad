# LAB: Cài đặt & Cấu hình VMware vCenter Server và Clustering (HA/DRS)

## 1. Mục tiêu bài LAB

Sau khi hoàn thành bài LAB, học viên có khả năng:

- Triển khai (deploy) VMware vCenter Server Appliance (VCSA) bằng GUI Installer.
- Tạo Datacenter, đưa các ESXi Host vào quản lý tập trung qua vCenter.
- Tạo Cluster và cấu hình **vSphere HA (High Availability)**.
- Cấu hình **vSphere DRS (Distributed Resource Scheduler)**.
- Thực hiện vMotion, mô phỏng sự cố Host để kiểm tra tính năng HA/DRS hoạt động đúng.

## 2. Yêu cầu chuẩn bị

### 2.1. Phần cứng / phần mềm

| Thành phần | Yêu cầu tối thiểu | Ghi chú |
|---|---|---|
| ESXi Host | Tối thiểu 02 host (khuyến nghị 03) | ESXi 7.0/8.0, CPU hỗ trợ ảo hóa (VT-x/AMD-V) |
| RAM mỗi Host | ≥ 16 GB | Đủ chạy VCSA + vài máy ảo test |
| Storage dùng chung | Shared Storage (NFS/iSCSI) | **Bắt buộc** để vMotion và HA hoạt động |
| vCenter Server Appliance | File ISO VCSA (7.0/8.0) | Deploy dưới dạng OVA |
| Mạng | Cùng 1 dải mạng/VLAN quản lý | Host, vCenter, vMotion nên tách VLAN riêng nếu có |
| Máy client | Windows/Linux có trình duyệt | Để truy cập vSphere Client (HTML5) |

### 2.2. Mô hình LAB đề xuất

```
                     +---------------------+
                     |   vCenter Server    |
                     |   (VCSA Appliance)  |
                     +----------+----------+
                                |
              Management Network (VLAN 10)
                                |
        +-----------------------------------------+
        |                                          |
+---------------+                        +---------------+
|   ESXi-01     |                        |   ESXi-02     |
| (Host trong   |<----- vMotion VLAN --->| (Host trong   |
|   Cluster)    |                        |   Cluster)    |
+-------+-------+                        +-------+-------+
        |                                        |
        +------------------+---------------------+
                           |
                  +--------+---------+
                  |  Shared Storage  |
                  |   (NFS/iSCSI)    |
                  +------------------+
```

> Ghi chú: Nếu lab trên VMware Workstation/ESXi lồng nhau (Nested ESXi), cần bật **Promiscuous Mode** và **Forged Transmits** trên vSwitch để Nested ESXi hoạt động đúng.

## 3. Nội dung thực hành

### Phần 1 — Triển khai vCenter Server Appliance (VCSA)

1. Mount file ISO VCSA trên máy quản trị, chạy trình cài đặt:
   - Windows: `installer.exe` (trong thư mục `vcsa-ui-installer\win32`)
   - Linux: `./installer` (trong thư mục `vcsa-ui-installer/lin64`)
2. Chọn **Install** → **Stage 1: Deploy vCenter Server**.
3. Nhập thông tin ESXi Host đích để deploy VCSA lên (host tạm, chưa cần vào Cluster):
   - FQDN/IP của ESXi Host
   - Username/password quản trị ESXi
4. Chọn kích cỡ (deployment size) phù hợp:

| Deployment Size | Số VM quản lý | vCPU | RAM |
|---|---|---|---|
| Tiny | ≤ 10 host / 100 VM | 2 | 12 GB |
| Small | ≤ 100 host / 1000 VM | 4 | 19 GB |
| Medium | ≤ 400 host / 4000 VM | 8 | 28 GB |

   → Với LAB học tập, chọn **Tiny**.

5. Chọn Datastore lưu VCSA, đặt mật khẩu **root** cho VCSA.
6. Cấu hình mạng cho VCSA: IP tĩnh, subnet mask, gateway, DNS, FQDN.
7. Kết thúc **Stage 1**, hệ thống deploy xong OVA của VCSA.
8. Chuyển sang **Stage 2: Set up vCenter Server**:
   - Đồng bộ thời gian (NTP hoặc theo ESXi Host)
   - Bật/tắt SSH (khuyến nghị bật để troubleshoot)
   - Tạo **SSO Domain** (ví dụ: `vsphere.local`) và mật khẩu Administrator
   - Chọn tham gia CEIP hay không
9. Sau khi hoàn tất, truy cập vCenter qua trình duyệt:

```
https://<FQDN-hoac-IP-vCenter>/ui
```

Đăng nhập bằng `administrator@vsphere.local`.

### Phần 2 — Tạo Datacenter và đưa Host vào quản lý

1. Trong vSphere Client → chuột phải vào **vCenter** → **New Datacenter** → đặt tên (VD: `DC-VTI`).
2. Chuột phải Datacenter → **Add Host**.
3. Nhập FQDN/IP của từng ESXi Host, tài khoản `root` + mật khẩu.
4. Xác nhận certificate (thumbprint) → Next → Finish.
5. Lặp lại để add đầy đủ các Host còn lại (tối thiểu 2 host).

### Phần 3 — Tạo Cluster và cấu hình cơ bản

1. Chuột phải Datacenter → **New Cluster**, đặt tên (VD: `Cluster-VTI`).
2. Trong màn hình tạo Cluster, bật sẵn 2 tính năng:
   - ☑ **vSphere DRS**
   - ☑ **vSphere HA**
3. Kéo thả các ESXi Host đã add vào trong Cluster vừa tạo.
4. Kiểm tra Cluster đã nhận đủ tài nguyên (CPU/RAM/Storage) từ các Host.

### Phần 4 — Cấu hình vSphere HA (High Availability)

1. Chọn Cluster → tab **Configure** → **vSphere Availability** → **Edit**.
2. Bật **Host Failure Response** → chọn **Restart VMs**.
3. Cấu hình **Admission Control**:
   - Chọn **Define failover capacity by**: `Slot Policy` hoặc `Percentage of cluster resources`
   - Với LAB 2-3 host, khuyến nghị dùng **Percentage-based**, đặt 25-33%.
4. Cấu hình **Host Monitoring**: Enabled.
5. Cấu hình **VM Monitoring** (tùy chọn): `VM and Application Monitoring` để tự khởi động lại VM bị treo OS.
6. Nhấn **OK** để lưu.

### Phần 5 — Cấu hình vSphere DRS

1. Chọn Cluster → tab **Configure** → **vSphere DRS** → **Edit**.
2. Chọn chế độ tự động hóa (**Automation Level**):

| Mức độ | Mô tả |
|---|---|
| Manual | DRS chỉ đề xuất, admin tự thực hiện di chuyển VM |
| Partially Automated | Tự động Power-on, nhưng migrate cần xác nhận |
| Fully Automated | Tự động cân bằng tải hoàn toàn (khuyến nghị cho LAB) |

3. Chọn **Migration Threshold** (mức độ nhạy khi cân bằng tải), để mặc định (mức 3/5) cho LAB.
4. Nhấn **OK**.

### Phần 6 — Kiểm thử HA và DRS

**Kiểm thử DRS (vMotion tự động):**
1. Tạo/di chuyển 2-3 VM test vào Cluster.
2. Theo dõi tab **Monitor → vSphere DRS → Recommendations/History** để xem DRS tự cân bằng tải giữa các host.
3. Có thể thử vMotion thủ công: chuột phải VM → **Migrate** → chọn Host đích.

**Kiểm thử HA (mô phỏng sự cố Host):**
1. Chọn 1 ESXi Host trong Cluster đang chạy VM test.
2. Ngắt kết nối mạng quản lý của Host đó (rút cáp ảo, hoặc tắt vSwitch uplink) — **không tắt vCenter**.
3. Quan sát: vCenter sẽ đánh dấu Host **Not Responding**, sau đó vSphere HA sẽ khởi động lại các VM trên host đó sang host còn sống trong Cluster.
4. Kiểm tra trong **Monitor → vSphere HA** để xem log sự kiện failover.

## 4. Checklist hoàn thành LAB

- [ ] Deploy thành công VCSA (Stage 1 + Stage 2)
- [ ] Đăng nhập được vSphere Client bằng `administrator@vsphere.local`
- [ ] Tạo Datacenter và add tối thiểu 2 ESXi Host
- [ ] Tạo Cluster, đưa Host vào Cluster
- [ ] Bật và cấu hình thành công vSphere HA (Admission Control, Host Monitoring)
- [ ] Bật và cấu hình thành công vSphere DRS (Automation Level)
- [ ] Thực hiện vMotion thủ công thành công (không mất kết nối VM)
- [ ] Mô phỏng sự cố Host và xác nhận HA tự động restart VM sang Host khác
- [ ] Chụp ảnh màn hình minh chứng từng bước, nộp báo cáo

## 5. Xử lý sự cố thường gặp (Troubleshooting)

| Sự cố | Nguyên nhân thường gặp | Cách khắc phục |
|---|---|---|
| Không deploy được VCSA, báo lỗi kết nối Host | Sai IP/thông tin đăng nhập ESXi, hoặc Host đang bị Lockdown Mode | Kiểm tra lại thông tin, tắt Lockdown Mode tạm thời trên ESXi |
| vCenter deploy xong nhưng không truy cập được Web UI | Sai DNS/FQDN, chưa đồng bộ được thời gian | Kiểm tra DNS resolve đúng chiều (forward + reverse), đồng bộ NTP |
| Add Host vào vCenter báo lỗi "Cannot contact license server"/certificate | Thumbprint SSL chưa được chấp nhận | Xác nhận lại thumbprint khi được hỏi, hoặc kiểm tra thời gian hệ thống Host/vCenter lệch nhau |
| vMotion thất bại | Không có Shared Storage, hoặc VMkernel vMotion chưa cấu hình đúng VLAN | Kiểm tra vSwitch có VMkernel port loại "vMotion", đảm bảo 2 host cùng subnet vMotion |
| HA báo "Insufficient resources to satisfy HA failover level" | Admission Control đặt quá cao so với tài nguyên thực tế Cluster | Giảm % dự phòng hoặc thêm Host vào Cluster |
| DRS không di chuyển VM dù mất cân bằng tải | Automation Level đang ở Manual, hoặc VM có gắn CD-ROM/USB pass-through | Chuyển sang Fully Automated, gỡ thiết bị cục bộ khỏi VM |
| Host bị "Not Responding" nhưng VM không failover | HA Agent trên Host lỗi, hoặc mất cả mạng quản lý lẫn Datastore heartbeat | Kiểm tra Datastore Heartbeating trong cấu hình HA, đảm bảo có ít nhất 2 Datastore dùng chung |

## 6. Bài tập nâng cao (mở rộng, không bắt buộc)

1. Cấu hình **DRS Affinity/Anti-Affinity Rules** để giữ 2 VM luôn chạy tách host nhau.
2. Cấu hình **vSphere Fault Tolerance (FT)** cho 1 VM quan trọng và kiểm thử.
3. Tích hợp **vCenter với Active Directory** để phân quyền đăng nhập theo nhóm user.
4. Thiết lập **Enhanced vMotion Compatibility (EVC)** khi Cluster có CPU khác đời.
