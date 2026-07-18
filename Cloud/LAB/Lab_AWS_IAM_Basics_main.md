# Bài Lab: AWS Identity and Access Management (IAM) - Cơ Bản

## 📋 Mục tiêu bài lab

Sau khi hoàn thành bài lab này, bạn sẽ hiểu biết:
- Khái niệm cơ bản về AWS IAM
- Cách tạo và quản lý IAM Users
- Cách tổ chức Users thành Groups
- Cách gán Policies để kiểm soát quyền truy cập
- Cách tạo Access Keys và sử dụng programmatic access

## 🎯 Kết quả mong đợi

Hoàn thành bài lab, bạn sẽ:
1. Tạo 2 IAM Users (Admin User và Limited User)
2. Tạo 1 Group và gán Users vào Group
3. Gán Managed Policies cho User
4. Tạo Custom Policy để giới hạn quyền
5. Tạo Access Keys và kiểm tra quyền truy cập

---

## 📚 Kiến thức cơ bản

### IAM là gì?

AWS Identity and Access Management (IAM) là dịch vụ cho phép bạn quản lý quyền truy cập vào tài nguyên AWS một cách an toàn. IAM giúp bạn:

- **Tạo và quản lý AWS users**: Người dùng cần truy cập vào tài nguyên AWS
- **Tạo và quản lý AWS roles**: Các vai trò được gán cho EC2 instances, Lambda functions, v.v.
- **Kiểm soát quyền truy cập**: Sử dụng Policies để xác định ai được làm gì với tài nguyên nào

### Các thành phần chính của IAM

| Thành phần | Mô tả |
|-----------|-------|
| **Users** | Người dùng AWS cá nhân hoặc ứng dụng |
| **Groups** | Tập hợp các Users để dễ quản lý quyền hạn |
| **Roles** | Một tập hợp quyền mà AWS services có thể giả định |
| **Policies** | Tài liệu JSON định nghĩa quyền cho Users, Groups, hoặc Roles |
| **Access Keys** | Chứng chỉ cho Programmatic Access (CLI, API) |
| **MFA** | Multi-Factor Authentication để tăng bảo mật |

---

## 📌 Điều kiện tiên quyết

1. Tài khoản AWS với quyền Root hoặc Admin
2. Quyền truy cập vào AWS Management Console
3. Trình duyệt web hiện đại
4. (Tùy chọn) AWS CLI được cài đặt

---

## 🔧 Các bước thực hiện

### PHẦN 1: Tạo IAM Users

#### Bước 1.1: Đăng nhập vào AWS Console

1. Truy cập [https://console.aws.amazon.com](https://console.aws.amazon.com)
2. Đăng nhập bằng tài khoản Root hoặc Admin

#### Bước 1.2: Truy cập IAM Dashboard

1. Tìm kiếm "IAM" trong thanh tìm kiếm
2. Nhấp vào **Identity and Access Management**
3. Từ menu bên trái, chọn **Users**

#### Bước 1.3: Tạo User thứ nhất - "admin-user"

1. Nhấp nút **Create user**
2. Nhập **User name**: `admin-user`
3. Chọn **Provide user access to the AWS Management Console**
4. Chọn **I want to create an IAM user**
5. Đặt mật khẩu: 
   - Chọn **Custom password**
   - Nhập mật khẩu mạnh: `AwsLab2024!Secure#`
6. **Bỏ chọn** "Users must create a new password on next sign-in" (để tránh phức tạp)
7. Nhấp **Next**

#### Bước 1.4: Gán quyền cho "admin-user"

1. Chọn **Attach policies directly**
2. Tìm kiếm policy: `AdministratorAccess`
3. **Chọn** policy này
4. Nhấp **Next** rồi **Create user**
5. **Ghi chú**: User và mật khẩu để sử dụng sau

#### Bước 1.5: Tạo User thứ hai - "read-only-user"

1. Lặp lại các bước 1.2-1.3 với:
   - **User name**: `read-only-user`
   - **Password**: `ReadOnlyUser2024!Pass`
2. Nhấp **Next**
3. Chọn **Attach policies directly**
4. Tìm kiếm: `ReadOnlyAccess`
5. Chọn policy này
6. Nhấp **Next** rồi **Create user**

---

### PHẦN 2: Tạo Group và Quản lý Users

#### Bước 2.1: Tạo Group mới

1. Từ menu bên trái, chọn **User groups**
2. Nhấp **Create group**
3. Nhập **Group name**: `Developer`
4. Chọn **Attach policy** - tìm `PowerUserAccess`
5. Nhấp **Create group**

#### Bước 2.2: Thêm Users vào Group

1. Nhấp vào Group **Developer**
2. Chọn tab **Users**
3. Nhấp **Add users**
4. Chọn `admin-user`
5. Nhấp **Add users**

---

### PHẦN 3: Tạo Custom Policy

#### Bước 3.1: Tạo Policy để chỉ cho phép S3 ReadOnly

1. Từ menu bên trái, chọn **Policies**
2. Nhấp **Create policy**
3. Chọn **JSON** tab
4. Dán đoạn code sau:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": "*"
    }
  ]
}
```

5. Nhấp **Next**
6. Đặt tên: `S3ReadOnlyPolicy`
7. Nhấp **Create policy**

#### Bước 3.2: Gán Custom Policy cho User

1. Từ **Users**, chọn `read-only-user`
2. Nhấp tab **Permissions**
3. Nhấp **Add permissions** → **Attach policies**
4. Tìm `S3ReadOnlyPolicy`
5. Chọn policy và nhấp **Attach policies**

---

### PHẦN 4: Tạo Access Keys (Programmatic Access)

#### Bước 4.1: Tạo Access Key cho "admin-user"

1. Từ **Users**, chọn `admin-user`
2. Chọn tab **Security credentials**
3. Nhấp **Create access key**
4. Chọn **Command Line Interface (CLI)**
5. Chọn checkbox xác nhận
6. Nhấp **Next**
7. Nhấp **Create access key**
8. **Lưu lại**:
   - Access Key ID
   - Secret Access Key
9. Nhấp **Done**

#### Bước 4.2: Tạo Access Key cho "read-only-user"

1. Lặp lại các bước 4.1 với `read-only-user`
2. Lưu Access Keys

---

### PHẦN 5: Kiểm tra quyền truy cập (tùy chọn - Cần AWS CLI)

#### Bước 5.1: Cấu hình AWS CLI với Access Keys

```bash
# Cấu hình cho admin-user
aws configure --profile admin-user
# Nhập:
# AWS Access Key ID: <admin-user access key>
# AWS Secret Access Key: <admin-user secret key>
# Default region: ap-southeast-1
# Default output: json

# Cấu hình cho read-only-user
aws configure --profile read-only-user
# Nhập:
# AWS Access Key ID: <read-only-user access key>
# AWS Secret Access Key: <read-only-user secret key>
# Default region: ap-southeast-1
# Default output: json
```

#### Bước 5.2: Kiểm tra quyền của admin-user

```bash
# Xem danh sách S3 buckets (nên thành công)
aws s3 ls --profile admin-user

# Xem danh sách EC2 instances (nên thành công)
aws ec2 describe-instances --profile admin-user
```

#### Bước 5.3: Kiểm tra quyền của read-only-user

```bash
# Xem danh sách S3 buckets (nên thành công)
aws s3 ls --profile read-only-user

# Xem danh sách EC2 instances (nên THẤT BẠI - Access Denied)
aws ec2 describe-instances --profile read-only-user
```

---

## ✅ Kiểm tra kết quả

Để xác nhận bài lab hoàn thành thành công, hãy kiểm tra:

- [ ] Tạo được 2 IAM Users: `admin-user` và `read-only-user`
- [ ] Tạo được 1 Group: `Developer`
- [ ] `admin-user` được thêm vào Group `Developer`
- [ ] Tạo được Custom Policy: `S3ReadOnlyPolicy`
- [ ] `read-only-user` có cả `ReadOnlyAccess` và `S3ReadOnlyPolicy`
- [ ] Tạo được Access Keys cho cả 2 Users
- [ ] (Tùy chọn) Kiểm tra được quyền truy cập qua CLI

---

## 📝 Bài tập nâng cao

1. **Tạo Inline Policy**: Tạo một Inline Policy cho `read-only-user` cho phép chỉ liệt kê (ListOnly) EC2 instances

   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": "ec2:DescribeInstances",
         "Resource": "*"
       }
     ]
   }
   ```

2. **Tạo IAM Role**: Tạo một IAM Role có tên `EC2ReadOnlyRole` với `ReadOnlyAccess` policy, để sử dụng cho EC2 instances

3. **Kích hoạt MFA**: Kích hoạt Multi-Factor Authentication cho `admin-user` bằng Google Authenticator hoặc Authy

4. **Tạo Policy với Condition**: Tạo một policy cho phép S3 access chỉ từ một IP cụ thể

   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": "s3:*",
         "Resource": "*",
         "Condition": {
           "IpAddress": {
             "aws:SourceIp": "203.0.113.0/24"
           }
         }
       }
     ]
   }
   ```

---

## 🔒 Best Practices

1. **Không sử dụng Root account**: Chỉ sử dụng cho administrative tasks
2. **Principle of Least Privilege**: Cấp quyền tối thiểu cần thiết
3. **Định kỳ audit**: Kiểm tra quyền của Users và Roles
4. **Sử dụng Groups**: Quản lý quyền thông qua Groups thay vì từng User
5. **Xoá Access Keys cũ**: Xoá các Access Keys không sử dụng
6. **Kích hoạt MFA**: Đặc biệt cho các tài khoản có quyền cao
7. **Sử dụng Roles cho Services**: Không sử dụng Access Keys cho EC2/Lambda, dùng Roles

---

## 📚 Tài liệu tham khảo

- [AWS IAM Documentation](https://docs.aws.amazon.com/iam/)
- [IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
- [Policy Examples](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_examples.html)

---

## 🆘 Xử lý sự cố

| Vấn đề | Giải pháp |
|--------|----------|
| **Access Denied** | Kiểm tra xem User/Role có policy phù hợp không |
| **User không thể đăng nhập** | Kiểm tra User name và password, đảm bảo User có Console access |
| **MFA không hoạt động** | Đồng bộ hóa thời gian trên thiết bị, thử tạo MFA mới |
| **Access Key không hoạt động** | Kiểm tra Access Key chưa được deactivate, kiểm tra region |

---

**Ngày tạo**: 2024  
**Phiên bản**: 1.0  
**Tác giả**: VTI Infrastructure Team
