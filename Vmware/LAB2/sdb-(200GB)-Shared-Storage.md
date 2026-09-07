# Cấu hình sdb (200GB) làm Shared Storage

Vì `sdb` đang là ổ trống (chưa partition, chưa format), có 2 hướng dùng cho lab:

- **NFS**: format sdb thành filesystem (ext4), mount vào thư mục, rồi export qua NFS — giống hướng dẫn trước.
- **iSCSI**: dùng thẳng `/dev/sdb` làm raw block backstore, không cần format — gần với cách storage array thật hoạt động hơn.

Mình hướng dẫn cả hai, anh/chị chọn theo mục đích lab.

---

## PHƯƠNG ÁN A — Dùng sdb cho NFS

### Bước 1: Format và mount sdb

```bash
# Format sdb thành ext4 (toàn bộ 200GB, không tạo partition table riêng)
sudo mkfs.ext4 /dev/sdb

# Tạo thư mục mount point
sudo mkdir -p /mnt/nfs-datastore

# Mount thủ công để test
sudo mount /dev/sdb /mnt/nfs-datastore

# Kiểm tra đã mount đúng dung lượng chưa
df -h /mnt/nfs-datastore
```

### Bước 2: Mount tự động khi khởi động lại (fstab)

```bash
# Lấy UUID của sdb
sudo blkid /dev/sdb
```

Thêm dòng sau vào `/etc/fstab` (thay UUID lấy được ở trên):

```bash
sudo nano /etc/fstab
```

```
UUID=<uuid-cua-sdb>  /mnt/nfs-datastore  ext4  defaults  0  2
```

```bash
# Test lại fstab không lỗi trước khi reboot thật
sudo mount -a
```

### Bước 3: Cài và export NFS (nếu chưa làm ở bước trước)

```bash
sudo apt update && sudo apt install -y nfs-kernel-server

sudo chown nobody:nogroup /mnt/nfs-datastore
sudo chmod 777 /mnt/nfs-datastore

sudo nano /etc/exports
```

Thêm dòng (thay dải IP đúng theo mạng lab, ví dụ dải Management/vMotion của 2 host):

```
/mnt/nfs-datastore  192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash,insecure)
```

```bash
sudo exportfs -ra
sudo systemctl restart nfs-kernel-server
sudo systemctl enable nfs-kernel-server

# Xác nhận export đã lên đúng thư mục, đúng dung lượng
showmount -e localhost
df -h /mnt/nfs-datastore
```

Sau bước này, quay lại **Bước 2 (Mount NFS Datastore trên ESXi-Host-A và Host-B)** ở hướng dẫn trước — dùng đúng path `/mnt/nfs-datastore` và IP của máy Ubuntu này.

**✅ Checklist:**
- [ ] `df -h` thấy `/mnt/nfs-datastore` = ~196GB (200GB trừ overhead ext4)
- [ ] `mount -a` không báo lỗi (fstab đúng)
- [ ] `showmount -e localhost` hiển thị đúng path và dải IP export

---

## PHƯƠNG ÁN B — Dùng sdb làm iSCSI Block Backstore (không cần format)

Cách này tận dụng nguyên block device 200GB, không qua filesystem trung gian — mô phỏng gần giống LUN thật của SAN.

### Bước 1: Cài targetcli

```bash
sudo apt update && sudo apt install -y targetcli-fb
sudo targetcli
```

### Bước 2: Tạo backstore trỏ thẳng vào /dev/sdb

Trong shell của `targetcli`:

```
/backstores/block create name=ds_block_1 dev=/dev/sdb
/iscsi create iqn.2026-09.local.lab:datastore1
/iscsi/iqn.2026-09.local.lab:datastore1/tpg1/luns create /backstores/block/ds_block_1
```

### Bước 3: Cấp quyền truy cập cho 2 host ESXi (ACL theo IQN)

Trước tiên lấy IQN của từng ESXi host (chạy trên mỗi host qua SSH):

```bash
esxcli iscsi adapter list
esxcli iscsi adapter get -A vmhba<số>
```

Copy đúng IQN của Host-A, Host-B, rồi quay lại `targetcli`:

```
/iscsi/iqn.2026-09.local.lab:datastore1/tpg1/acls create <IQN-Host-A>
/iscsi/iqn.2026-09.local.lab:datastore1/tpg1/acls create <IQN-Host-B>
/iscsi/iqn.2026-09.local.lab:datastore1/tpg1 set attribute authentication=0
saveconfig
exit
```

### Bước 4: Mở firewall port iSCSI trên Ubuntu (nếu có ufw)

```bash
sudo ufw allow 3260/tcp
```

### Bước 5: Cấu hình phía ESXi (cả 2 host)

```
Host > Configure > Storage Adapters
  → Add Software Adapter → Add software iSCSI adapter
  → Chọn adapter vmhba<x> > Targets > Dynamic Discovery > Add
    → nhập IP máy Ubuntu, port 3260
  → Rescan Storage Adapter
```

Sau khi rescan, LUN 200GB sẽ xuất hiện ở cả 2 host — chỉ tạo **VMFS datastore 1 lần duy nhất** trên Host-A, Host-B rescan sẽ tự nhận cùng datastore.

**✅ Checklist:**
- [ ] `lsblk` xác nhận sdb chưa bị format bởi bước A (nếu chọn phương án B thì bỏ qua mkfs)
- [ ] ACL đã thêm đúng IQN thật của cả 2 host (không dùng IQN mẫu)
- [ ] Rescan Storage Adapter trên cả 2 host thấy cùng 1 LUN 200GB
- [ ] Chỉ format VMFS 1 lần, host còn lại tự nhận sau rescan

---

## Lưu ý chọn phương án

| Nếu... | Nên chọn |
|---|---|
| Muốn nhanh, quen thao tác Linux filesystem, không cần học sâu về LUN/iSCSI | **Phương án A (NFS)** |
| Muốn học gần với cách SAN storage thật hoạt động (LUN, IQN, multipathing) | **Phương án B (iSCSI)** |
| Đã lỡ `mkfs.ext4 /dev/sdb` rồi mới đổi ý sang iSCSI | Cần `wipefs -a /dev/sdb` trước khi tạo lại backstore block, tránh ESXi nhận nhầm filesystem cũ |

Anh/chị muốn dùng sdb theo hướng nào giữa 2 cái trên, hay đã format ext4 rồi và chỉ cần mình hỗ trợ tiếp phần export NFS?