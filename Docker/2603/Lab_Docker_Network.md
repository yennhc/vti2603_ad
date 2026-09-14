# LAB: Docker Network

*Khái niệm cốt lõi và thực hành các loại network trong Docker*

## 1. Mục tiêu

- Hiểu các loại network driver trong Docker và khi nào dùng loại nào.
- Phân biệt bridge mặc định (default bridge) và bridge tự tạo (user-defined bridge).
- Hiểu cơ chế DNS nội bộ giúp container gọi nhau bằng tên thay vì IP.
- Thực hành tạo network, kết nối container, publish port, và cô lập network.

## 2. Yêu cầu trước khi thực hành

- Máy đã cài Docker Engine (`docker --version` chạy được).
- Đã hoàn thành lab "Docker Image & Layer" (hiểu image, container cơ bản).
- Quyền sudo hoặc user thuộc nhóm `docker`.

## 3. Khái niệm cốt lõi

### 3.1. Network driver — các loại mạng trong Docker

| Driver | Mô tả | Khi nào dùng |
|---|---|---|
| `bridge` | Mạng ảo riêng trên host, container trong cùng bridge thấy nhau qua IP nội bộ | Mặc định cho container chạy độc lập trên 1 host |
| `host` | Container dùng chung network stack với host, không cô lập | Cần hiệu năng cao, không cần cô lập port |
| `none` | Container không có network interface (trừ loopback) | Container không cần mạng (batch job, xử lý file) |
| `overlay` | Mạng ảo trải rộng nhiều host, dùng cho Docker Swarm | Cụm nhiều node cần container giao tiếp xuyên host |
| `macvlan` | Gán MAC/IP riêng cho container như một thiết bị vật lý trên mạng LAN | Container cần xuất hiện như thiết bị thật trên mạng công ty |

### 3.2. Default bridge vs User-defined bridge

| Đặc điểm | Default bridge (`bridge`) | User-defined bridge |
|---|---|---|
| Tạo tự động khi cài Docker | Có | Không, phải `docker network create` |
| DNS tự động giữa container | Không — phải dùng `--link` (deprecated) hoặc IP | Có — gọi nhau bằng tên container |
| Cô lập với network khác | Không rõ ràng | Có, mỗi network riêng biệt |
| Khuyến nghị dùng | Không nên dùng cho ứng dụng thật | Nên dùng mặc định cho mọi dự án |

**Ghi nhớ cốt lõi:** luôn tạo user-defined bridge network riêng cho từng dự án/stack thay vì dùng default bridge — vừa có DNS, vừa cô lập tốt hơn.

### 3.3. Publish port — `-p` hoạt động thế nào

`-p <host_port>:<container_port>` tạo một rule NAT trên host, chuyển tiếp traffic từ port host vào container. Container vẫn có IP nội bộ riêng; `-p` chỉ mở đường cho traffic từ bên ngoài host đi vào.

### 3.4. Container-to-container communication

- Cùng một user-defined network → gọi nhau bằng **tên container** (Docker có DNS server nội bộ ở `127.0.0.11`).
- Khác network → mặc định không thấy nhau, phải nối cả hai container vào chung 1 network bằng `docker network connect`.

## 4. Sơ đồ minh hoạ

```
                        HOST
   ┌─────────────────────────────────────────────┐
   │  Network: app-net (user-defined bridge)      │
   │                                               │
   │   ┌───────────┐        ┌───────────┐         │
   │   │  web      │──DNS──▶│   db      │         │
   │   │ (nginx)   │        │ (postgres)│         │
   │   └─────┬─────┘        └───────────┘         │
   │         │                                     │
   └─────────┼─────────────────────────────────────┘
             │ -p 8080:80
             ▼
        http://localhost:8080  (từ máy thật)
```

## 5. Các bước thực hành

### Bước 1 — Kiểm tra network mặc định

```bash
docker network ls
docker network inspect bridge
```

Ghi nhận: loại driver, subnet, và danh sách container đang dùng network `bridge`.

### Bước 2 — Thử default bridge KHÔNG có DNS

```bash
docker run -d --name c1 alpine sleep 3600
docker run -d --name c2 alpine sleep 3600
docker exec c1 ping -c 2 c2
```

Quan sát: lệnh `ping c2` **thất bại** vì default bridge không có DNS resolve theo tên container.

### Bước 3 — Tạo user-defined bridge network

```bash
docker network create app-net
docker network ls
```

### Bước 4 — Chạy container trong network mới và thử DNS

```bash
docker run -d --name web --network app-net nginx
docker run -d --name db --network app-net -e POSTGRES_PASSWORD=demo123 postgres:16-alpine

```

Quan sát: lần này `ping db` **thành công** — vì cùng user-defined network nên có DNS nội bộ.

### Bước 5 — Publish port ra ngoài host

```bash
docker run -d --name web2 --network app-net -p 8080:80 nginx
curl http://localhost:8080
```

Kiểm tra: truy cập được từ host qua cổng 8080, dù container vẫn chạy port 80 bên trong.

### Bước 6 — Cô lập network

```bash
docker network create isolated-net
docker run -d --name c3 --network isolated-net alpine sleep 3600
docker exec c3 ping -c 2 web
```

Quan sát: `c3` **không ping được** `web` vì khác network — chứng minh network có tính cô lập.

### Bước 7 — Kết nối một container vào nhiều network

```bash
docker network connect app-net c3
docker exec c3 ping -c 2 web
```

Quan sát: sau khi `connect`, `c3` ping `web` thành công — 1 container có thể thuộc nhiều network cùng lúc.

## 6. Bảng ghi nhận kết quả

| Bước | Lệnh kiểm tra | Kết quả (Thành công / Thất bại) | Giải thích |
|---|---|---|---|
| 2 | `docker exec c1 ping -c 2 c2` | | |
| 4 | `docker exec web ping -c 2 db` | | |
| 6 | `docker exec c3 ping -c 2 web` | | |
| 7 | `docker exec c3 ping -c 2 web` (sau connect) | | |

## 7. Troubleshooting

| Hiện tượng | Nguyên nhân thường gặp | Cách xử lý |
|---|---|---|
| Container không ping được nhau dù cùng `docker-compose` | Compose tự tạo network riêng theo project, container không cùng service/network khai báo | Kiểm tra `docker network ls` và `docker inspect <container>` phần `Networks` |
| `curl localhost:PORT` không phản hồi dù container đang chạy | Quên `-p` khi `docker run`, hoặc port bên trong container khác với port khai báo | Kiểm tra `docker port <container>` để xem mapping thực tế |
| Container ping được bằng IP nhưng không được bằng tên | Đang dùng default bridge, không phải user-defined network | Tạo user-defined bridge và chạy lại container trong đó |
| `docker network create` báo trùng subnet | Đã có network khác dùng chung dải IP | Chỉ định subnet riêng: `docker network create --subnet 172.30.0.0/16 app-net` |
| Container mất kết nối internet sau khi đổi network | Network `internal: true` (Compose) hoặc `--internal` chặn traffic ra ngoài | Bỏ cờ `internal` nếu container cần ra internet |

## 8. Checklist hoàn thành lab

- [ ] Kiểm tra được danh sách network mặc định bằng `docker network ls`
- [ ] Tái hiện được lỗi DNS trên default bridge (bước 2)
- [ ] Tạo thành công user-defined bridge network
- [ ] Xác nhận DNS hoạt động giữa 2 container cùng network (bước 4)
- [ ] Publish port thành công và truy cập được từ host (bước 5)
- [ ] Chứng minh được tính cô lập giữa hai network khác nhau (bước 6)
- [ ] Kết nối container vào nhiều network và xác nhận lại kết nối (bước 7)
- [ ] Điền đầy đủ bảng ghi nhận kết quả ở mục 6

## 9. Câu hỏi củng cố

- Vì sao không nên dùng default bridge cho ứng dụng nhiều container trong thực tế?
- Nếu hai container ở hai network khác nhau nhưng cùng publish port ra host, chúng có thể giao tiếp qua `localhost` của host được không? Vì sao?
- `docker network connect` có ảnh hưởng gì đến IP hiện tại của container hay không?
- Trong network driver `host`, việc `-p` để publish port còn cần thiết không? Vì sao?

## 10. Dọn dẹp môi trường sau lab

```bash
docker rm -f c1 c2 c3 web web2 db
docker network rm app-net isolated-net
```
