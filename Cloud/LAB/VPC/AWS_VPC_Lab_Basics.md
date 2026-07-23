# AWS VPC Lab - Cơ Bản

## Mục Tiêu Bài Lab

Sau khi hoàn thành bài lab này, học viên sẽ có khả năng:
- Tạo và cấu hình một Virtual Private Cloud (VPC) trong AWS
- Tạo công khai (public) và tư nhân (private) subnets
- Thiết lập Internet Gateway để kết nối ra internet
- Cấu hình Route Tables để điều hướng traffic
- Hiểu được cách các thành phần VPC hoạt động cùng nhau

## Yêu Cầu Tiên Quyết

- Tài khoản AWS (free tier)
- Quen thuộc với khái niệm mạng cơ bản (IP, subnet, gateway)
- Trình duyệt web để truy cập AWS Console
- Thời gian: **30-45 phút**

---

## Phần 1: Tạo VPC

### Bước 1.1: Truy Cập VPC Service

1. Đăng nhập vào [AWS Console](https://console.aws.amazon.com)
2. Chọn **Services** → tìm **VPC**
3. Nhấn vào **VPC** hoặc truy cập trực tiếp: `https://console.aws.amazon.com/vpc`

### Bước 1.2: Tạo VPC Mới

1. Ở menu bên trái, chọn **Your VPCs**
2. Nhấn nút **Create VPC**
3. Điền thông tin:
   - **Name tag**: `my-first-vpc`
   - **IPv4 CIDR block**: `10.0.0.0/16`
   - **IPv6 CIDR block**: Chọn **No IPv6 CIDR block**
   - **Tenancy**: `Default`

4. Nhấn **Create VPC**

**Giải thích:**
- `10.0.0.0/16` là khối IP cho toàn bộ VPC (cho phép ~65,536 địa chỉ IP)
- Đây là một Private IP range theo tiêu chuẩn RFC 1918

---

## Phần 2: Tạo Subnets

### Bước 2.1: Tạo Public Subnet

1. Ở menu bên trái, chọn **Subnets**
2. Nhấn **Create Subnet**
3. Điền thông tin:
   - **VPC**: Chọn `my-first-vpc`
   - **Subnet name**: `public-subnet-1a`
   - **Availability Zone**: `ap-southeast-1a` (hoặc zone đầu tiên)
   - **IPv4 CIDR block**: `10.0.1.0/24`

4. Nhấn **Create Subnet**

**Giải thích:**
- `10.0.1.0/24` cho phép ~256 địa chỉ IP trong subnet này
- Chọn AZ cụ thể là tốt practice

### Bước 2.2: Tạo Private Subnet

1. Nhấn **Create Subnet** lần nữa
2. Điền thông tin:
   - **VPC**: Chọn `my-first-vpc`
   - **Subnet name**: `private-subnet-1a`
   - **Availability Zone**: `ap-southeast-1a`
   - **IPv4 CIDR block**: `10.0.2.0/24`

3. Nhấn **Create Subnet**

**Kết quả dự kiến:**
Bạn sẽ có 2 subnets trong VPC:
- `public-subnet-1a` (10.0.1.0/24) - dùng cho EC2 instances công khai
- `private-subnet-1a` (10.0.2.0/24) - dùng cho databases hoặc resources nội bộ

---

## Phần 3: Tạo Internet Gateway

### Bước 3.1: Tạo IGW

1. Ở menu bên trái, chọn **Internet Gateways**
2. Nhấn **Create Internet Gateway**
3. Điền **Name tag**: `my-igw`
4. Nhấn **Create Internet Gateway**

### Bước 3.2: Gắn IGW vào VPC

1. Sau khi tạo xong, nhấn **Attach to VPC**
2. Chọn VPC: `my-first-vpc`
3. Nhấn **Attach Internet Gateway**

**Giải thích:**
- Internet Gateway là cổng để VPC kết nối đến internet
- Mỗi VPC chỉ có thể có **1 IGW**

---

## Phần 4: Cấu Hình Route Tables

### Bước 4.1: Tạo Route Table Cho Public Subnet

1. Ở menu bên trái, chọn **Route Tables**
2. Nhấn **Create Route Table**
3. Điền thông tin:
   - **Name tag**: `public-rt`
   - **VPC**: `my-first-vpc`

4. Nhấn **Create Route Table**

### Bước 4.2: Thêm Route để Kết Nối Internet

1. Chọn route table vừa tạo (`public-rt`)
2. Ở tab **Routes**, nhấn **Edit Routes**
3. Nhấn **Add Route**
4. Điền:
   - **Destination**: `0.0.0.0/0` (tất cả traffic)
   - **Target**: Chọn Internet Gateway → `my-igw`

5. Nhấn **Save Routes**

### Bước 4.3: Gắn Route Table Vào Public Subnet

1. Ở tab **Subnet Associations**
2. Nhấn **Edit Subnet Associations**
3. Chọn `public-subnet-1a`
4. Nhấn **Save Associations**

**Kết quả:**
- Route table `public-rt` bây giờ định hướng tất cả traffic (0.0.0.0/0) đến Internet Gateway
- Public subnet sẽ sử dụng route table này

### Bước 4.4: Kiểm Tra Default Route Table Cho Private Subnet

1. Quay lại **Route Tables**
2. Tìm route table có tên `Default` (được tạo tự động cùng VPC)
3. Kiểm tra tab **Subnet Associations** → nó sẽ được gắn với `private-subnet-1a`
4. Xem tab **Routes** → sẽ chỉ có 1 route cục bộ (10.0.0.0/16 → local)

**Giải thích:**
- Private subnet không có route đến internet → instances trong nó không thể truy cập internet trực tiếp
- Đây là điểm mạnh của kiến trúc VPC (security by design)

---

## Phần 5: Kiểm Tra Kết Quả

### Checklist Hoàn Thành:

- [ ] VPC `my-first-vpc` được tạo với CIDR `10.0.0.0/16`
- [ ] Public Subnet `public-subnet-1a` được tạo (10.0.1.0/24)
- [ ] Private Subnet `private-subnet-1a` được tạo (10.0.2.0/24)
- [ ] Internet Gateway `my-igw` được tạo và gắn vào VPC
- [ ] Route Table `public-rt` có route `0.0.0.0/0 → my-igw`
- [ ] Public subnet gắn với `public-rt`
- [ ] Private subnet gắn với default route table (chỉ có local route)

### Hình Vẽ Kiến Trúc (Text Diagram)

```
┌─────────────────────────────────────────────────────────┐
│                   VPC (10.0.0.0/16)                     │
│                                                         │
│  ┌──────────────────┐        ┌──────────────────┐     │
│  │  Public Subnet   │        │  Private Subnet  │     │
│  │  (10.0.1.0/24)   │        │  (10.0.2.0/24)   │     │
│  │  Zone: 1a        │        │  Zone: 1a        │     │
│  │                  │        │                  │     │
│  │  Route Table:    │        │  Route Table:    │     │
│  │  - Local: local  │        │  - Local: local  │     │
│  │  - 0.0.0.0/0 IGW │        │  (No IGW route)  │     │
│  └──────────────────┘        └──────────────────┘     │
│           ↓                                             │
│           └──────────────────────┐                     │
│                                  ↓                     │
│                         ┌────────────────┐             │
│                         │  IGW (my-igw)  │             │
│                         └────────────────┘             │
│                                  ↓                     │
└──────────────────────────────────┼──────────────────────┘
                                   ↓
                            ┌──────────────┐
                            │   INTERNET   │
                            └──────────────┘
```

---

## Phần 6: Câu Hỏi Ôn Tập

### Câu 1: VPC CIDR Block

**Q:** Tại sao chúng ta chọn `10.0.0.0/16` thay vì `10.0.0.0/24`?

<details>
<summary>Đáp án</summary>

Vì `/16` cung cấp nhiều IP địa chỉ hơn (65,536 IPs) so với `/24` (256 IPs). Với `/16`, chúng ta có đủ không gian để tạo nhiều subnets con (`/24`, `/25`, ...) mà không lo hết IP.

</details>

### Câu 2: Public vs Private Subnet

**Q:** Sự khác biệt chính giữa public và private subnet là gì?

<details>
<summary>Đáp án</summary>

- **Public Subnet**: Có route đến Internet Gateway → instances có thể kết nối ra internet
- **Private Subnet**: Không có route IGW → instances không thể kết nối ra internet trực tiếp, cần NAT Gateway để ra ngoài
- Điều này được kiểm soát bằng **Route Table**

</details>

### Câu 3: Internet Gateway

**Q:** Một VPC có thể có bao nhiêu Internet Gateways?

<details>
<summary>Đáp án</summary>

Chỉ **1 IGW** duy nhất. Đây là limitation của AWS. Nếu bạn cần high availability, bạn phải thiết kế khác (ví dụ: dùng NAT Gateway, VPN, ...).

</details>

### Câu 4: Route Table

**Q:** Tại sao chúng ta cần thêm route `0.0.0.0/0 → IGW` vào route table của public subnet?

<details>
<summary>Đáp án</summary>

Vì mặc định, route table mới chỉ có local route (10.0.0.0/16 → local). Muốn traffic đi ra ngoài VPC đến internet (0.0.0.0/0), chúng ta phải chỉ định target là IGW.

</details>

---

## Phần 7: Challenge (Tự Do)

### Challenge 1: Tạo Thêm Subnet Ở AZ Khác

Tạo thêm:
- `public-subnet-1b` (10.0.3.0/24) ở `ap-southeast-1b`
- `private-subnet-1b` (10.0.4.0/24) ở `ap-southeast-1b`
- Gắn public-subnet-1b vào `public-rt`

**Mục đích**: Tạo High Availability cho public layer

### Challenge 2: Tạo Thêm Route Table Cho Private Subnet

Tạo một Route Table mới tên `private-rt` và gắn nó vào private subnets (thay vì dùng default RT).

**Mục đích**: Tách biệt quản lý route cho public và private subnets

---

## Phần 8: Dọn Dẹp (Clean Up)

**QUAN TRỌNG:** Để tránh tính phí, hãy xóa các resources này:

1. **Detach Internet Gateway**:
   - VPC → Internet Gateways
   - Chọn `my-igw` → Detach from VPC

2. **Delete Internet Gateway**:
   - Nhấn Delete Internet Gateway

3. **Delete Subnets**:
   - VPC → Subnets
   - Xóa `public-subnet-1a` và `private-subnet-1a`

4. **Delete Route Tables**:
   - VPC → Route Tables
   - Xóa `public-rt` (KHÔNG xóa default RT)

5. **Delete VPC**:
   - VPC → Your VPCs
   - Chọn `my-first-vpc` → Delete VPC

---

## Tài Liệu Tham Khảo

- [AWS VPC Documentation](https://docs.aws.amazon.com/vpc/)
- [VPC CIDR Notation](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Subnets.html)
- [Internet Gateway Documentation](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Internet_Gateway.html)

---
