# Hướng dẫn cấu hình Shared Datastore cho 2 ESXi Host

Có 2 cách phổ biến để tạo Shared Datastore: **NFS** (đơn giản, dễ làm lab) và **iSCSI** (hiệu năng tốt hơn, gần với thực tế production hơn). Dưới đây là hướng dẫn cho cả hai.

## So sánh nhanh 2 phương án

| Tiêu chí | NFS | iSCSI |
|---|---|---|
| Độ phức tạp cấu hình | Thấp — chỉ cần export share | Trung bình — cần tạo target, IQN, có thể cần CHAP |
| Hiệu năng | Khá, phụ thuộc network | Tốt hơn, hỗ trợ multipathing |
| Phù hợp cho lab | ✅ Rất phù hợp | ✅ Phù hợp nếu muốn học gần production |
| Yêu cầu | NFS Server (TrueNAS, Linux NFS export) | iSCSI Target (TrueNAS, StarWind, Linux targetcli) |

Nếu mục đích là lab nhanh phục vụ bài vMotion, mình khuyến nghị dùng **NFS** trước — dễ dựng trong 10 phút bằng một VM Linux hoặc TrueNAS.

---

## PHƯƠNG ÁN A — Shared Datastore qua NFS

### Bước 1: Chuẩn bị NFS Server

Có thể dùng TrueNAS CORE/SCALE (khuyến nghị cho lab, có UI), hoặc Linux thuần (Ubuntu/CentOS).

**Nếu dùng Ubuntu/Linux làm NFS Server:**

```bash
# Cài NFS server
sudo apt update && sudo apt install -y nfs-kernel-server

# Tạo thư mục share
sudo mkdir -p /mnt/nfs-datastore
sudo chown nobody:nogroup /mnt/nfs-datastore
sudo chmod 777 /mnt/nfs-datastore

# Cấu hình export — cho phép dải IP của 2 host ESXi truy cập
sudo nano /etc/exports
```

Thêm dòng sau vào `/etc/exports` (thay IP theo dải mạng thật của bạn):

```
/mnt/nfs-datastore  192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash,insecure)
```

```bash
# Áp dụng cấu hình
sudo exportfs -ra
sudo systemctl restart nfs-kernel-server
sudo systemctl enable nfs-kernel-server

# Kiểm tra export đã lên chưa
sudo exportfs -v
showmount -e localhost
```

> ⚠️ Lưu ý bảo mật: option `no_root_squash` và `insecure` chỉ nên dùng trong môi trường lab. Ở production cần siết chặt hơn (giới hạn IP cụ thể, dùng `root_squash`).

### Bước 2: Mount NFS Datastore trên ESXi-Host-A

```
vCenter > Host ESXi-Host-A > Configure > Storage > Datastores
  → New Datastore
    → Type: NFS
    → NFS version: NFS 3 (hoặc NFS 4.1 nếu server hỗ trợ)
    → Datastore name: DS-Shared-NFS
    → Folder: /mnt/nfs-datastore
    → Server: <IP của NFS Server>
```

### Bước 3: Mount cùng datastore trên ESXi-Host-B

Lặp lại chính xác bước 2 trên Host-B — **quan trọng: phải đặt cùng tên Datastore** (`DS-Shared-NFS`) để vCenter nhận diện là cùng 1 shared datastore giữa 2 host, không tạo ra 2 datastore riêng biệt trùng dữ liệu.

### Bước 4: Xác nhận datastore đã "shared"

```
vCenter > Datacenter > Datastores > chọn DS-Shared-NFS
  → Tab "Hosts" → phải thấy CẢ 2 host (ESXi-Host-A, ESXi-Host-B) cùng liệt kê, trạng thái "Connected"
```

Hoặc kiểm tra bằng CLI trên từng host (SSH vào ESXi):

```bash
esxcli storage nfs list
```

Kết quả cần thấy dòng datastore với `Mounted: true` trên cả 2 host.

**✅ Checklist NFS:**
- [ ] NFS Server export thư mục, `showmount -e` thấy đúng path
- [ ] Cả 2 host mount cùng 1 tên Datastore
- [ ] Tab "Hosts" của Datastore hiển thị đủ 2 host, status Connected
- [ ] `esxcli storage nfs list` xác nhận Mounted: true trên cả 2 host

---

## PHƯƠNG ÁN B — Shared Datastore qua iSCSI

### Bước 1: Chuẩn bị iSCSI Target

Dùng TrueNAS hoặc Linux `targetcli`:

```bash
# Trên Linux (Ubuntu) làm iSCSI Target
sudo apt install -y targetcli-fb

sudo targetcli
```

Trong targetcli shell:

```
/backstores/fileio create ds_iscsi_1 /data/iscsi_disk.img 50G
/iscsi create iqn.2026-09.local.lab:datastore1
/iscsi/iqn.2026-09.local.lab:datastore1/tpg1/luns create /backstores/fileio/ds_iscsi_1
/iscsi/iqn.2026-09.local.lab:datastore1/tpg1/acls create iqn.2026-09.local.lab:esxi-host-a
/iscsi/iqn.2026-09.local.lab:datastore1/tpg1/acls create iqn.2026-09.local.lab:esxi-host-b
/iscsi/iqn.2026-09.local.lab:datastore1/tpg1 set attribute authentication=0
saveconfig
exit
```

### Bước 2: Cấu hình iSCSI Software Adapter trên từng ESXi Host

Thực hiện trên **cả 2 host**:

```
Host > Configure > Storage Adapters
  → Add Software Adapter → Add software iSCSI adapter → OK
  → Chọn adapter vmhba (vừa tạo) > Targets tab > Dynamic Discovery
  → Add: nhập IP của iSCSI Target Server, port 3260
  → Rescan Storage Adapter
```

### Bước 3: Lấy IQN của mỗi host để cấu hình ACL trên Target

```bash
esxcli iscsi adapter list
esxcli iscsi adapter get -A vmhba<số>
```

Copy đúng IQN của Host-A và Host-B, đưa vào ACL ở Bước 1 (thay vì tự đặt tên IQN như ví dụ).

### Bước 4: Tạo VMFS Datastore từ LUN

```
Host-A > Configure > Storage > Datastores > New Datastore
  → Type: VMFS
  → Chọn LUN vừa rescan thấy từ iSCSI Target
  → Datastore name: DS-Shared-iSCSI
  → VMFS version: VMFS 6
```

Trên Host-B: **không tạo mới**, mà rescan storage rồi datastore sẽ tự xuất hiện (vì cùng VMFS trên cùng LUN) — chỉ cần add host vào datastore nếu chưa tự nhận.

**✅ Checklist iSCSI:**
- [ ] Cả 2 host add đúng ACL/IQN được phép truy cập LUN
- [ ] Rescan Storage Adapter trên cả 2 host thấy cùng 1 LUN
- [ ] Chỉ tạo VMFS 1 lần trên 1 host, host còn lại tự nhận sau rescan
- [ ] Tab "Hosts" của Datastore hiển thị cả 2 host, Connected

---

## Lỗi thường gặp khi setup Shared Datastore

| Lỗi | Nguyên nhân | Cách xử lý |
|---|---|---|
| Host-B rescan không thấy LUN/NFS share | Firewall chặn port NFS (2049) hoặc iSCSI (3260) | Kiểm tra `esxcli network firewall ruleset list \| grep -iE "nfs\|iscsi"`, enable nếu đang disabled |
| "NFS mount unsuccessful" | Sai đường dẫn export, hoặc export chưa cho phép IP host đó | Kiểm tra lại `/etc/exports`, chạy `exportfs -ra`, đúng dải IP |
| 2 host thấy 2 datastore riêng trùng dữ liệu (không hợp nhất) | Đặt tên Datastore khác nhau giữa 2 host khi mount NFS | Xoá mount, mount lại với **cùng tên chính xác** trên cả 2 host |
| iSCSI target không cho kết nối | ACL chưa thêm đúng IQN của host, hoặc CHAP bật nhưng chưa cấu hình | Kiểm tra ACL trên target, tắt CHAP khi test lab hoặc cấu hình đúng CHAP secret |
| Datastore "Inaccessible" trên 1 host | Mất kết nối network tới storage, hoặc LUN ID conflict | Rescan lại, kiểm tra `vmkping` tới storage IP, kiểm tra log `vmkernel.log` |

Sau khi hoàn tất phần này, anh/chị có thể quay lại **Phần 1** của bài lab vMotion để tạo VM trên đúng Shared Datastore vừa dựng — datastore này sẽ dùng chung cho cả phần test Compute vMotion.