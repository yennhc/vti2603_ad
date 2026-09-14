# LAB: Docker Compose — Xây dựng Web Application nhiều service

*Dùng Docker Compose để build và chạy một ứng dụng web gồm app server, database, và cache*

## 1. Mục tiêu

- Hiểu cấu trúc file `docker-compose.yml` và các khối chính: `services`, `networks`, `volumes`.
- Biết cách một service tự build image từ Dockerfile ngay trong Compose (`build:`).
- Dùng biến môi trường qua file `.env` thay vì hard-code trong compose file.
- Hiểu `depends_on` kèm `healthcheck` để đảm bảo thứ tự khởi động đúng.
- Dùng volume để lưu dữ liệu persistent qua các lần `up`/`down`.
- Thực hành các lệnh vận hành: `up`, `down`, `logs`, `exec`, `scale`.

## 2. Yêu cầu trước khi thực hành

- Đã hoàn thành lab "Docker Image & Layer" và "Docker Network".
- Docker Engine có kèm Docker Compose v2 (`docker compose version` chạy được — dùng `docker compose`, không phải `docker-compose`).
- Hiểu cơ bản Python hoặc sẵn sàng copy code mẫu không cần hiểu sâu.

## 3. Khái niệm cốt lõi

### 3.1. Vì sao cần Docker Compose

Với ứng dụng nhiều container (web + database + cache), chạy tay từng `docker run` rất dễ sai thứ tự, quên network, quên volume. Compose cho phép khai báo **toàn bộ stack trong 1 file YAML**, chạy bằng 1 lệnh `docker compose up`.

### 3.2. Các khối chính trong `docker-compose.yml`

| Khối | Vai trò |
|---|---|
| `services` | Danh sách các container sẽ chạy (web, db, cache...) |
| `build` | Chỉ Compose tự build image từ Dockerfile thay vì pull sẵn |
| `image` | Dùng image có sẵn từ registry (không cần build) |
| `environment` / `env_file` | Truyền biến môi trường vào container |
| `volumes` | Gắn thư mục/named volume để lưu dữ liệu persistent |
| `networks` | Khai báo network riêng cho stack (mặc định Compose đã tự tạo 1 network chung) |
| `depends_on` | Quy định thứ tự khởi động giữa các service |
| `healthcheck` | Cho Docker biết khi nào service thực sự "sẵn sàng", không chỉ "đã start" |
| `ports` | Publish port ra host, giống `-p` của `docker run` |

### 3.3. `depends_on` KHÔNG tự đợi service sẵn sàng

Điểm hay bị hiểu sai: `depends_on` mặc định chỉ đảm bảo **thứ tự start container**, không đảm bảo service bên trong (ví dụ Postgres) đã sẵn sàng nhận kết nối. Muốn chờ đúng nghĩa, phải kết hợp với `healthcheck` + `condition: service_healthy`.

### 3.4. Volume — lưu dữ liệu sống ngoài vòng đời container

Named volume (`db-data:`) tồn tại độc lập với container. Xoá container (`docker compose down`) không xoá volume, trừ khi thêm cờ `-v`. Đây là cách chuẩn để lưu dữ liệu database.

## 4. Sơ đồ kiến trúc ứng dụng

```
                     Docker Compose stack: "webapp"
   ┌───────────────────────────────────────────────────────────┐
   │  network: webapp_default                                   │
   │                                                              │
   │   ┌────────┐      ┌────────┐      ┌────────┐               │
   │   │  web   │─────▶│  cache │      │   db   │               │
   │   │ (Flask)│      │ (Redis)│      │(Postgres)│             │
   │   └───┬────┘      └────────┘      └───┬────┘               │
   │       │                                │  volume: db-data   │
   └───────┼────────────────────────────────┼────────────────────┘
           │ -p 5000:5000
           ▼
      http://localhost:5000
```

## 5. Chuẩn bị mã nguồn

```bash
mkdir -p ~/compose-webapp/web && cd ~/compose-webapp
```

**`web/app.py`** — Flask app đơn giản, đếm số lượt truy cập bằng Redis và đọc thời gian từ Postgres:

```python
import os
import redis
import psycopg2
from flask import Flask

app = Flask(__name__)
r = redis.Redis(host="cache", port=6379, decode_responses=True)

def get_db_connection():
    return psycopg2.connect(
        host="db",
        dbname=os.environ["POSTGRES_DB"],
        user=os.environ["POSTGRES_USER"],
        password=os.environ["POSTGRES_PASSWORD"],
    )

@app.route("/")
def index():
    visits = r.incr("visits")
    conn = get_db_connection()
    cur = conn.cursor()
    cur.execute("SELECT NOW();")
    db_time = cur.fetchone()[0]
    cur.close()
    conn.close()
    return f"Xin chào! Số lượt truy cập: {visits} — Giờ server DB: {db_time}"

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
```

**`web/requirements.txt`**

```
flask==3.0.3
redis==5.0.4
psycopg2-binary==2.9.9
```

**`web/Dockerfile`**

```dockerfile
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

EXPOSE 5000

CMD ["python", "app.py"]
```

**`.env`** — biến môi trường dùng chung, KHÔNG commit file này vào git khi dùng thật:

```
POSTGRES_DB=appdb
POSTGRES_USER=appuser
POSTGRES_PASSWORD=demo123
```

**`docker-compose.yml`**

```yaml
services:
  web:
    build: ./web
    ports:
      - "5000:5000"
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    depends_on:
      db:
        condition: service_healthy
      cache:
        condition: service_started

  db:
    image: postgres:16-alpine
    env_file: .env
    volumes:
      - db-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER}"]
      interval: 5s
      timeout: 3s
      retries: 5

  cache:
    image: redis:7-alpine

volumes:
  db-data:
```

## 6. Các bước thực hành

### Bước 1 — Build và khởi động toàn bộ stack

```bash
docker compose up -d --build
docker compose ps
```

Quan sát: 3 service `web`, `db`, `cache` đều ở trạng thái `running`, `db` có thêm cột `healthy` sau vài giây.

### Bước 2 — Kiểm tra ứng dụng

```bash
curl http://localhost:5000
curl http://localhost:5000
```

Quan sát: số lượt truy cập tăng dần (lưu trong Redis), giờ DB trả về từ Postgres.

### Bước 3 — Xem log tổng hợp và log riêng từng service

```bash
docker compose logs -f web
```

Nhấn `Ctrl+C` để thoát xem log real-time. So sánh với:

```bash
docker compose logs db
```

### Bước 4 — Xác nhận `depends_on` + `healthcheck` hoạt động

```bash
docker compose down
docker compose up -d
docker compose ps
```

Quan sát cột `STATUS` của `web`: nó sẽ chờ `db` chuyển sang `healthy` rồi mới start, thay vì start song song.

### Bước 5 — Kiểm chứng volume tồn tại sau khi xoá container

```bash
curl http://localhost:5000    # ghi thêm dữ liệu vào Redis (không persistent) để so sánh
docker compose down
docker volume ls | grep db-data
docker compose up -d
curl http://localhost:5000
```

Quan sát: số lượt truy cập (Redis, không volume) reset về 1, nhưng nếu bạn có ghi dữ liệu vào bảng Postgres, dữ liệu đó vẫn còn — vì `db-data` là named volume tồn tại độc lập.

### Bước 6 — Scale service `web` lên nhiều instance

```bash
docker compose up -d --scale web=3
docker compose ps
```

Quan sát: có 3 container `web` chạy song song. Lưu ý: cấu hình `ports: "5000:5000"` cố định sẽ gây xung đột port khi scale — đây là điểm cần sửa (xem Troubleshooting).

### Bước 7 — Dừng và dọn toàn bộ stack

```bash
docker compose down
```

So sánh với:

```bash
docker compose down -v
```

Quan sát: cờ `-v` xoá luôn named volume `db-data` — dữ liệu Postgres mất hoàn toàn.

## 7. Bảng ghi nhận kết quả

| Bước | Thao tác | Kết quả quan sát | Ghi chú |
|---|---|---|---|
| 1 | `docker compose up -d --build` | | |
| 4 | `docker compose ps` (cột STATUS của web) | | |
| 5 | So sánh dữ liệu Redis vs Postgres sau `down`/`up` | | |
| 6 | `docker compose up -d --scale web=3` | | |
| 7 | So sánh `down` thường vs `down -v` | | |

## 8. Troubleshooting

| Hiện tượng | Nguyên nhân thường gặp | Cách xử lý |
|---|---|---|
| `web` báo lỗi kết nối tới `db` ngay khi start | `depends_on` không có `condition: service_healthy`, web start trước khi Postgres sẵn sàng | Thêm `healthcheck` cho `db` và `condition: service_healthy` ở `depends_on` |
| Đổi code `app.py` nhưng chạy `up` không thấy thay đổi | Compose dùng lại image cache cũ, không rebuild | Chạy `docker compose up -d --build` hoặc `docker compose build --no-cache` |
| `docker compose up --scale web=3` báo lỗi port đã được dùng | Khai báo `ports: "5000:5000"` cố định, không thể có 3 container cùng bind 1 port host | Bỏ cổng cố định, dùng `ports: - "5000"` (Docker tự chọn port ngẫu nhiên) hoặc dùng reverse proxy/load balancer phía trước |
| Biến trong `.env` không được Compose nhận | File đặt sai tên (không phải `.env`) hoặc chạy `docker compose` từ thư mục khác | Đảm bảo file tên đúng `.env` nằm cùng thư mục với `docker-compose.yml` |
| Sau `docker compose down -v` mất hết dữ liệu ngoài ý muốn | Nhầm `-v` là xoá container thường, không biết nó xoá cả volume | Chỉ dùng `-v` khi chắc chắn muốn xoá dữ liệu; dùng `down` (không `-v`) cho thao tác thường ngày |

## 9. Checklist hoàn thành lab

- [ ] Build và chạy thành công stack 3 service bằng `docker compose up -d --build`
- [ ] Truy cập được `http://localhost:5000` và thấy số lượt truy cập tăng dần
- [ ] Xác nhận `db` phải "healthy" trước khi `web` start (bước 4)
- [ ] Phân biệt được dữ liệu nào mất, dữ liệu nào còn sau `down`/`up` (bước 5)
- [ ] Scale `web` lên nhiều instance và giải thích được lỗi port nếu có (bước 6)
- [ ] Giải thích được khác biệt giữa `docker compose down` và `down -v`
- [ ] Điền đầy đủ bảng ghi nhận kết quả ở mục 7

## 10. Dọn dẹp môi trường sau lab

```bash
docker compose down -v
docker image rm compose-webapp-web
```
