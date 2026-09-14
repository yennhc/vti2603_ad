# LAB: Docker Image & Layer

*Tìm hiểu cách Docker tạo image từ Dockerfile và cơ chế layer*

## 1. Mục tiêu

- Hiểu Dockerfile là gì và cách Docker build image từ Dockerfile.
- Phân biệt các chỉ thị tạo layer mới và chỉ thị chỉ thay đổi metadata.
- Sử dụng `docker history` và `docker image inspect` để quan sát layer thực tế.
- Áp dụng thứ tự chỉ thị hợp lý để tối ưu cache khi build image.

## 2. Yêu cầu trước khi thực hành

- Máy đã cài Docker Engine (`docker --version` chạy được).
- Đã hiểu cơ bản về container là gì (đã học lab trước).
- Quyền sudo hoặc user thuộc nhóm `docker`.

## 3. Lý thuyết tóm tắt

Image được tạo bằng lệnh `docker build`, đọc các chỉ thị trong Dockerfile theo thứ tự từ trên xuống. Không phải mọi chỉ thị đều tạo ra một layer filesystem mới:

| Chỉ thị | Có tạo layer filesystem? | Ghi chú |
|---|---|---|
| `FROM` | Có | Layer nền (base image) |
| `RUN` | Có | Mỗi `RUN` là 1 layer — nên gộp nhiều lệnh bằng `&&` để giảm số layer |
| `COPY` / `ADD` | Có | Ghi lại file được thêm vào image |
| `ENV` | Không | Chỉ thêm biến môi trường vào metadata |
| `LABEL` | Không | Chỉ thêm metadata mô tả image |
| `EXPOSE` | Không | Chỉ khai báo cổng, không mở cổng thật |
| `WORKDIR` | Không | Đổi thư mục làm việc mặc định (metadata) |
| `CMD` / `ENTRYPOINT` | Không | Chỉ định lệnh chạy khi container khởi động |

Các layer được cache theo thứ tự: nếu một layer không đổi so với lần build trước, Docker tái sử dụng layer cũ (cache hit) và bỏ qua toàn bộ các layer phía sau nó nếu chúng cũng không đổi — vì vậy đặt lệnh ít thay đổi lên trước sẽ giúp build nhanh hơn.

## 4. Dockerfile minh hoạ

Tạo thư mục thực hành và file Dockerfile sau:

```bash
mkdir ~/docker-layer-lab && cd ~/docker-layer-lab
touch app.py requirements.txt
```

Nội dung Dockerfile:

```dockerfile
FROM python:3.11-slim

LABEL maintainer="vti-academy"

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

ENV APP_ENV=production
EXPOSE 8000

CMD ["python", "app.py"]
```

## 5. Các bước thực hành

### Bước 1 — Build image lần đầu

```bash
docker build -t demo-layers:v1 .
```

Quan sát output: mỗi dòng "Step X/Y" tương ứng với một chỉ thị trong Dockerfile.

### Bước 2 — Kiểm tra danh sách layer

```bash
docker history demo-layers:v1
```

So sánh cột SIZE giữa các dòng: các dòng `ENV`, `LABEL`, `EXPOSE`, `CMD` có SIZE = 0B (không tạo layer filesystem), trong khi `RUN` và `COPY` có kích thước > 0.

### Bước 3 — Xem chi tiết layer bằng inspect

```bash
docker image inspect demo-layers:v1 --format '{{json .RootFS.Layers}}' | python3 -m json.tool
```

Mỗi phần tử trong mảng là một layer ID (dạng sha256), tương ứng với các chỉ thị `FROM`, `RUN`, `COPY`.

### Bước 4 — Kiểm chứng cơ chế cache

Sửa nội dung `app.py` (không đổi `requirements.txt`), sau đó build lại:

```bash
echo "# updated" >> app.py
docker build -t demo-layers:v2 .
```

Quan sát output: các bước trước `COPY app.py` hiển thị "CACHED", chỉ các bước từ `COPY app.py` trở đi được build lại.

### Bước 5 — So sánh nếu đổi thứ tự (phản ví dụ)

Thử đổi Dockerfile để `COPY` toàn bộ mã nguồn (`COPY . .`) trước khi `RUN pip install`, rồi build lại sau khi sửa `app.py`. Quan sát: lúc này bước `RUN pip install` cũng bị build lại dù `requirements.txt` không đổi — vì layer `COPY` phía trước nó đã thay đổi.

## 6. Bảng ghi nhận kết quả

| Bước | Lệnh đã chạy | Layer bị build lại? | Ghi chú quan sát |
|---|---|---|---|
| 1 | `docker build -t demo-layers:v1 .` | | |
| 4 | `docker build -t demo-layers:v2 .` | | |
| 5 | `docker build` (sau khi đổi thứ tự) | | |

## 7. Troubleshooting

| Hiện tượng | Nguyên nhân thường gặp | Cách xử lý |
|---|---|---|
| Build luôn chạy lại toàn bộ RUN dù không đổi code | `COPY` toàn bộ source đặt trước `RUN install` dependency | Tách `COPY requirements/package` trước, `RUN install`, rồi mới `COPY` source |
| `docker build` báo "no space left on device" | Quá nhiều layer/image cũ tồn đọng | Dọn bằng `docker system prune -a` (cẩn thận: xoá cả image/cache không dùng) |
| `docker history` hiển thị `<missing>` | Layer kế thừa từ base image đã pull, không có metadata build cục bộ | Bình thường với base image chính thức; dùng `docker image inspect` để xem digest |
| Image quá lớn dù Dockerfile ngắn | `RUN apt-get install` không dọn cache trong cùng lệnh | Gộp `apt-get update`, `install`, `rm -rf /var/lib/apt/lists/*` trong 1 `RUN` duy nhất |

## 8. Checklist hoàn thành lab

- [ ] Build thành công image `demo-layers:v1`
- [ ] Chạy được `docker history` và xác định đúng layer nào có SIZE = 0B
- [ ] Chạy được `docker image inspect` và liệt kê được các layer ID
- [ ] Quan sát và giải thích được hiện tượng CACHED khi build v2
- [ ] Thực hiện phản ví dụ ở bước 5 và giải thích được vì sao cache bị mất tác dụng
- [ ] Điền đầy đủ bảng ghi nhận kết quả ở mục 6

## 9. Câu hỏi củng cố

- Nếu đổi vị trí `LABEL` xuống cuối Dockerfile, số layer filesystem của image có đổi không? Vì sao?
- Vì sao nên tách `COPY requirements.txt` và `COPY app.py` thành hai lệnh riêng thay vì gộp chung `COPY . .`?
- `docker history` cho biết được nội dung thay đổi trong từng layer không, hay chỉ biết kích thước và lệnh?
