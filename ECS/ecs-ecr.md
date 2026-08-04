## Lab: Đưa ứng dụng Docker lên ECR và chạy bằng ECS Fargate

Mục tiêu: tạo một website nhỏ → đóng gói Docker → lưu image trong ECR → triển khai một ECS Service trên Fargate → truy cập bằng IP công khai.

Thời gian: khoảng 45–60 phút.  
Chuẩn bị: AWS account, Docker Desktop, AWS CLI đã cấu hình (`aws configure`). Hãy dùng một Region duy nhất xuyên suốt, ví dụ `ap-southeast-1`.

> Lab dùng public IP để đơn giản hóa việc học. Hãy xóa tài nguyên ở cuối để tránh phát sinh chi phí.

### 1. Tạo ứng dụng

Tạo thư mục `ecs-ecr-lab`, rồi tạo hai file sau.

`index.html`

```html
<!doctype html>
<html>
  <head>
    <title>ECS + ECR Lab</title>
  </head>
  <body>
    <h1>Chào từ Amazon ECS Fargate!</h1>
    <p>Image này được lưu trong Amazon ECR.</p>
  </body>
</html>
```

`Dockerfile`

```dockerfile
FROM nginx:alpine
COPY index.html /usr/share/nginx/html/index.html
EXPOSE 80
```

Build và thử chạy ở máy của bạn:

```bash
docker build -t ecs-ecr-lab:1.0 .
docker run --rm -p 8080:80 ecs-ecr-lab:1.0
```

Mở `http://localhost:8080`. Khi thấy trang web, dừng container bằng `Ctrl+C`.

### 2. Tạo repository và đẩy image vào ECR

Đặt các biến, thay Region nếu cần:

```bash
export AWS_REGION=ap-southeast-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export REPOSITORY=ecs-ecr-lab
```

Tạo ECR repository:

```bash
aws ecr create-repository \
  --repository-name $REPOSITORY \
  --region $AWS_REGION
```

Đăng nhập Docker vào ECR, gắn tag và push:

```bash
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin \
  $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

docker tag ecs-ecr-lab:1.0 \
  $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$REPOSITORY:1.0

docker push \
  $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$REPOSITORY:1.0
```

Vào AWS Console → **ECR → Repositories → ecs-ecr-lab** để kiểm tra image tag `1.0`.

ECR yêu cầu repository tồn tại trước khi push; lệnh đăng nhập lấy token có hiệu lực 12 giờ. [Tài liệu AWS ECR](https://docs.aws.amazon.com/AmazonECR/latest/userguide/docker-push-ecr-image.html)

### 3. Tạo ECS Cluster

Trong AWS Console:

1. Mở **Amazon ECS** → **Clusters** → **Create cluster**.
2. Đặt tên: `ecs-ecr-lab-cluster`.
3. Chọn cấu hình mặc định/Fargate, rồi tạo cluster.

### 4. Tạo Task Definition

1. Vào **Task definitions** → **Create new task definition**.
2. Chọn **Fargate**.
3. Đặt tên family: `ecs-ecr-lab-task`.
4. Chọn CPU `0.25 vCPU` và Memory `0.5 GB`.
5. Trong phần container:
   - Name: `web`
   - Image URI:
     ```text
     <ACCOUNT_ID>.dkr.ecr.ap-southeast-1.amazonaws.com/ecs-ecr-lab:1.0
     ```
   - Container port: `80`, protocol `TCP`
6. Tạo Task Definition.

AWS sẽ tạo hoặc dùng **Task Execution Role** để ECS có quyền pull image từ ECR và ghi log nếu bạn bật CloudWatch Logs.

### 5. Tạo Service để chạy ứng dụng

Trong cluster `ecs-ecr-lab-cluster`:

1. Chọn **Create** trong phần Services.
2. Launch type: **Fargate**.
3. Application type: **Service**.
4. Chọn Task Definition `ecs-ecr-lab-task`.
5. Service name: `ecs-ecr-lab-service`.
6. Desired tasks: `1`.
7. Networking:
   - Chọn VPC mặc định.
   - Chọn một **public subnet**.
   - Tạo security group mới, ví dụ `ecs-ecr-lab-sg`.
   - Inbound rule: **HTTP / TCP / port 80 / source My IP**.  
     Nếu chỉ phục vụ lab và muốn dễ kiểm tra, có thể chọn `0.0.0.0/0`, nhưng không nên giữ cách này cho production.
   - Bật **Assign public IP**.
8. Không cần Load Balancer trong lab này.
9. Tạo service và chờ Task có trạng thái `RUNNING`.

Fargate task trong public subnet có thể được gán public IP; task cũng cần đường ra Internet để pull image. [Tài liệu AWS ECS](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/fargate-task-networking.html)

### 6. Kiểm tra kết quả

1. ECS → cluster → service → tab **Tasks**.
2. Mở Task đang `RUNNING`.
3. Trong phần **Networking**, lấy **Public IP**.
4. Mở trên trình duyệt:

```text
http://<PUBLIC_IP>
```

Bạn sẽ thấy: “Chào từ Amazon ECS Fargate!”

### 7. Kiểm chứng kiến thức

Tự trả lời các câu sau:

1. Image của bạn nằm ở đâu?  
   → ECR repository `ecs-ecr-lab`.

2. Cấu hình container như image, CPU/RAM và port nằm ở đâu?  
   → Task Definition.

3. Thành phần giữ cho luôn có một container chạy?  
   → ECS Service, với `desired count = 1`.

4. Vì sao Service tạo Task mới khi Task bị dừng?  
   → Để duy trì desired count.

5. ECS pull image từ ECR bằng quyền nào?  
   → Task Execution Role.

### 8. Dọn dẹp

Để tránh chi phí:

1. ECS → Cluster → Service → cập nhật Desired tasks thành `0`, sau đó xóa Service.
2. Xóa cluster.
3. ECR → repository `ecs-ecr-lab` → xóa repository và các image trong đó.
4. Xóa security group `ecs-ecr-lab-sg` nếu không dùng nữa.

AWS cũng cung cấp flow chính thức tương tự: tạo cluster, Task Definition, Service, kiểm tra Task và dọn dẹp. [ECS Fargate CLI tutorial](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ECS_AWSCLI_Fargate.html)