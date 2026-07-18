# Lab: Làm Quen với AWS EC2

## 1. Mục Tiêu Lab

Sau khi hoàn thành lab này, bạn sẽ có thể:
- Tạo một instance EC2 trên AWS
- Cấu hình Security Group cho phép SSH access
- Kết nối đến instance sử dụng SSH
- Chạy các lệnh Linux cơ bản trên instance
- Dọn dẹp tài nguyên AWS

**Thời gian hoàn thành**: 20-30 phút  
**Mức độ**: Beginner  
**Chi phí ước tính**: Free tier (nếu sử dụng AWS Free Tier account)

---

## 2. Yêu Cầu Tiên Quyết

- Tài khoản AWS (có thể dùng Free Tier)
- SSH client được cài đặt trên máy tính của bạn
  - **Linux/macOS**: Terminal (có sẵn)
  - **Windows**: PuTTY hoặc Windows Subsystem for Linux (WSL)
- Một cặp khóa SSH (key pair) AWS hoặc sẵn sàng tạo trong quá trình lab

---

## 3. Kiến Thức Nền Tảng

### EC2 là gì?
Amazon EC2 (Elastic Compute Cloud) là dịch vụ máy chủ ảo trên AWS. Nó cho phép bạn:
- Khởi động các máy chủ Linux hoặc Windows
- Quản lý tài nguyên compute (CPU, RAM)
- Mở rộng hoặc giảm quy mô dễ dàng
- Trả tiền theo mức sử dụng

### Instance Types
Các loại instance phổ biến:
- **t2.micro**: Được dùng cho Free Tier (1 vCPU, 1 GB RAM)
- **t2.small**: 1 vCPU, 2 GB RAM
- **t3**: Instance thế hệ mới, tiết kiệm chi phí hơn

### Region & Availability Zone
- **Region**: Vùng địa lý (ví dụ: ap-southeast-1 cho Singapore/Việt Nam)
- **Availability Zone (AZ)**: Trung tâm dữ liệu trong một region

---

## 4. Các Bước Thực Hiện

### Bước 1: Đăng Nhập AWS Console

1. Mở trình duyệt và truy cập [https://aws.amazon.com](https://aws.amazon.com)
2. Nhấp **Sign In** và đăng nhập với tài khoản AWS của bạn
3. Chọn Region phù hợp (ví dụ: **ap-southeast-1** cho Việt Nam)

---

### Bước 2: Tạo hoặc Chọn Key Pair

Để kết nối SSH đến instance, bạn cần một key pair.

**Nếu bạn chưa có key pair:**

1. Trong AWS Console, tìm kiếm **EC2**
2. Chọn **EC2** service
3. Ở menu bên trái, chọn **Key Pairs** (dưới Network & Security)
4. Nhấp **Create key pair**
   - **Name**: `my-ec2-key` (hoặc tên tuỳ ý)
   - **Key pair type**: RSA
   - **File format**: .pem (cho Linux/macOS) hoặc .ppk (cho PuTTY)
5. Nhấp **Create key pair**
6. File sẽ tự động tải về máy tính của bạn
7. **LƯU Ý**: Giữ file key an toàn, không chia sẻ với ai

**Lưu file key:**
```bash
# Trên Linux/macOS
mv ~/Downloads/my-ec2-key.pem ~/.ssh/
chmod 400 ~/.ssh/my-ec2-key.pem
```

---

### Bước 3: Tạo Security Group

Security Group là firewall ảo kiểm soát incoming/outgoing traffic.

1. Trong EC2 Console, chọn **Security Groups** (dưới Network & Security)
2. Nhấp **Create security group**
3. Điền thông tin:
   - **Security group name**: `ec2-lab-sg`
   - **Description**: `Security group for EC2 lab - Allow SSH`
   - **VPC**: Chọn default VPC
4. Trong phần **Inbound rules**, nhấp **Add rule**
   - **Type**: SSH
   - **Protocol**: TCP
   - **Port range**: 22
   - **Source**: My IP (nên chọn cái này để an toàn hơn)
     - Nếu không thấy "My IP", chọn Custom và nhập `0.0.0.0/0` (cho tất cả, không an toàn)
5. Nhấp **Create security group**

---

### Bước 4: Tạo EC2 Instance

1. Trong EC2 Console, chọn **Instances**
2. Nhấp **Launch instances**
3. Điền các thông tin sau:

#### Name and tags
- **Name**: `my-first-server` (hoặc tên tuỳ ý)

#### Application and OS Images (AMI)
- Chọn **Ubuntu**
- Chọn bản **Ubuntu Server 24.04 LTS** (hoặc phiên bản LTS mới nhất)
- Kiểm tra **Free tier eligible** nếu bạn có Free Tier

#### Instance type
- **t2.micro** (Free tier eligible)

#### Key pair
- Chọn key pair bạn vừa tạo: `my-ec2-key`

#### Network settings
- **VPC**: Default VPC
- **Subnet**: Để default
- **Public IP**: Enable (auto-assign)
- **Security group**: Chọn `ec2-lab-sg` mà bạn vừa tạo

#### Storage
- **Root volume**: 8 GB (default, đủ cho lab)
- **Volume type**: gp3 hoặc gp2

#### Summary
- Kiểm tra lại các cài đặt
- Nhấp **Launch instance**

---

### Bước 5: Kết Nối SSH đến Instance

Chờ instance khởi động xong (status thay đổi thành "running").

1. Trong Instances list, chọn instance vừa tạo
2. Lấy **Public IPv4 address** (ví dụ: `54.123.45.67`)
3. Mở Terminal (Linux/macOS) hoặc Command Prompt/PuTTY (Windows)

**Trên Linux/macOS:**
```bash
ssh -i ~/.ssh/my-ec2-key.pem ubuntu@<PUBLIC_IP>
```

**Ví dụ:**
```bash
ssh -i ~/.ssh/my-ec2-key.pem ubuntu@54.123.45.67
```

4. Lần đầu kết nối, bạn sẽ thấy câu hỏi:
   ```
   The authenticity of host '54.123.45.67 (54.123.45.67)' can't be established.
   Are you sure you want to continue connecting (yes/no)?
   ```
   - Gõ `yes` và Enter

5. Nếu kết nối thành công, bạn sẽ thấy prompt:
   ```
   ubuntu@ip-172-31-xx-xx:~$
   ```

---

### Bước 6: Chạy Các Lệnh Trên Instance

Bây giờ bạn đã kết nối vào server. Hãy thử các lệnh sau:

```bash
# Kiểm tra thông tin hệ thống
uname -a

# Kiểm tra phiên bản Ubuntu
lsb_release -a

# Kiểm tra tài nguyên (CPU, RAM)
free -h
df -h

# Cập nhật package manager
sudo apt update

# Cài đặt một ứng dụng đơn giản (web server)
sudo apt install -y nginx

# Kiểm tra trạng thái Nginx
sudo systemctl status nginx

# Xem địa chỉ IP của instance
hostname -I
```

---

### Bước 7: Kiểm Tra Nginx (Optional)

Nếu bạn cài Nginx ở bước trước, bạn có thể kiểm tra:

1. Cần cho phép HTTP traffic trong Security Group:
   - Vào EC2 Console → Security Groups → chọn `ec2-lab-sg`
   - Thêm inbound rule mới:
     - **Type**: HTTP
     - **Protocol**: TCP
     - **Port**: 80
     - **Source**: 0.0.0.0/0

2. Mở trình duyệt và truy cập:
   ```
   http://<PUBLIC_IP>
   ```
   - Bạn sẽ thấy trang Nginx mặc định

---

## 5. Kiểm Tra Kết Quả (Checklist)

Đánh dấu các mục khi hoàn thành:

- [ ] Tạo được key pair
- [ ] Tạo được Security Group với SSH access
- [ ] Tạo được EC2 instance
- [ ] Kết nối SSH thành công
- [ ] Chạy được các lệnh Linux cơ bản
- [ ] (Optional) Cài đặt và kiểm tra Nginx

---

## 6. Dọn Dẹp Tài Nguyên (Cleanup)

**QUAN TRỌNG**: Để tránh bị tính phí, hãy dọn dẹp sau khi hoàn thành lab.

### Ngắt kết nối SSH
```bash
exit
```

### Xóa Instance

1. Trong EC2 Console, chọn instance của bạn
2. Nhấp **Instance State** → **Terminate instance**
3. Xác nhận xóa

### Xóa Security Group (Optional)
1. Chọn **Security Groups**
2. Chọn `ec2-lab-sg`
3. Nhấp **Delete security group** (chỉ có thể xóa khi không có instance nào sử dụng)

### Giữ Key Pair
Bạn nên giữ key pair vì nó có thể sử dụng cho các lab khác.

---

## 7. Các Vấn Đề Thường Gặp

### Lỗi: "Permission denied (publickey)"
**Nguyên nhân**: Key file không có quyền đúng hoặc path sai  
**Giải pháp**:
```bash
chmod 400 ~/.ssh/my-ec2-key.pem
# Kiểm tra path file key đúng chưa
```

### Lỗi: "Connection timed out"
**Nguyên nhân**: Security Group không cho phép SSH  
**Giải pháp**:
- Kiểm tra Security Group có inbound rule cho SSH (port 22) không
- Kiểm tra source IP có đúng không

### Instance không lên được
**Nguyên nhân**: Instance còn đang khởi động  
**Giải pháp**:
- Chờ vài phút, refresh lại console
- Kiểm tra status của instance

### Public IP không hiển thị
**Nguyên nhân**: Không enable auto-assign public IP  
**Giải pháp**:
- Allocate một Elastic IP (có phí nếu không sử dụng)
- Hoặc tạo lại instance với auto-assign public IP enabled

---

## 8. Kiến Thức Mở Rộng

### Các bước tiếp theo:
1. **Elastic IP**: Giữ IP không đổi khi instance restart
2. **Elastic Block Store (EBS)**: Quản lý storage instance
3. **Auto Scaling**: Tự động tạo/xóa instance theo nhu cầu
4. **Load Balancer**: Phân tải traffic
5. **VPC & Networking**: Tạo network riêng biệt

### Tài liệu tham khảo:
- AWS EC2 Documentation: https://docs.aws.amazon.com/ec2/
- AWS Free Tier: https://aws.amazon.com/free/

---
