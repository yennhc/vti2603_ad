# Lab CI/CD: GitHub → Jenkins Docker → ứng dụng trên AWS EC2

**Author: Yên Nguyễn**  
**Ngày biên soạn: 23/09/2026**  
**Môi trường:** Ubuntu Server 24.04 LTS trên AWS EC2; Jenkins chạy Docker; GitHub.com.  
**Thời lượng dự kiến:** 2–3 giờ, chưa tính thời gian tạo tài khoản và tải image.  
**Đối tượng:** Người mới học CI/CD, đã biết thao tác terminal, Git cơ bản và SSH.

> Kiểm tra khi biên soạn: đã kiểm tra cú pháp JavaScript, JSON và shell. Chưa chạy end-to-end trên EC2/Jenkins; môi trường biên soạn chặn mở cổng local nên chưa thực thi được bộ test HTTP.

> Tài liệu hướng dẫn triển khai, không phải biên bản xác nhận đã triển khai trên tài khoản AWS của bạn. Các lệnh phải chạy đúng nơi được ghi. EC2, EBS và địa chỉ IPv4 công cộng có thể phát sinh chi phí; kiểm tra giá theo Region của bạn.

## Mục lục

1. [Mục tiêu và kiến trúc](#1-mục-tiêu-và-kiến-trúc)
2. [Chuẩn bị và quy ước](#2-chuẩn-bị-và-quy-ước)
3. [Tạo EC2 và Security Group](#3-tạo-ec2-và-security-group)
4. [Cài Docker trên EC2](#4-cài-docker-trên-ec2)
5. [Triển khai Jenkins trong Docker](#5-triển-khai-jenkins-trong-docker)
6. [Tạo ứng dụng Node.js](#6-tạo-ứng-dụng-nodejs)
7. [Dockerfile và build thử](#7-dockerfile-và-build-thử)
8. [Jenkinsfile đầy đủ](#8-jenkinsfile-đầy-đủ)
9. [Tạo GitHub repository và credentials](#9-tạo-github-repository-và-credentials)
10. [Tạo Pipeline Jenkins](#10-tạo-pipeline-jenkins)
11. [Cấu hình và kiểm tra GitHub Webhook](#11-cấu-hình-và-kiểm-tra-github-webhook)
12. [Push code và nghiệm thu CI/CD](#12-push-code-và-nghiệm-thu-cicd)
13. [Rollback cơ bản](#13-rollback-cơ-bản)
14. [Troubleshooting](#14-troubleshooting)
15. [Tăng dung lượng EBS](#15-tăng-dung-lượng-ebs)
16. [Bảo mật và vận hành](#16-bảo-mật-và-vận-hành)
17. [Checklist hoàn thành và dọn lab](#17-checklist-hoàn-thành-và-dọn-lab)
18. [Tài liệu tham khảo](#18-tài-liệu-tham-khảo)

## 1. Mục tiêu và kiến trúc

Sau bài lab, khi developer push commit mới lên nhánh `main`, Jenkins tự checkout code, chạy `npm ci`, chạy test thật, build image gắn với commit và build number, rồi thay container ứng dụng trên cùng EC2. Nếu test hoặc build lỗi, ứng dụng đang chạy không bị thay thế. Nếu phiên bản vừa deploy không healthy, pipeline thử khởi động lại container cũ.

```text
Máy developer
    │ git push main
    ▼
GitHub repository
    │ HTTP POST /github-webhook/ (push event)
    ▼
AWS EC2 Ubuntu 24.04
┌─────────────────────────────────────────────────────────┐
│ Docker Engine trên EC2                                  │
│                                                         │
│ Jenkins container :8080                                 │
│  ├─ /var/jenkins_home ← volume jenkins_home               │
│  ├─ Docker CLI + Buildx                                 │
│  └─ /var/run/docker.sock → Docker Engine của EC2         │
│       │                                                 │
│       ├─ Checkout → Install → Test → Build → Deploy      │
│       └─ sample-ci-app container, EC2 :3000 → app :3000   │
│                                                         │
│ sample-ci-app-previous: container cũ đã stop để rollback  │
└─────────────────────────────────────────────────────────┘
    ▲                                  ▲
    │ SSH tunnel để quản trị Jenkins    │ GET :3000
Máy người học                       Trình duyệt
```

**Điểm cần hiểu:** Docker daemon chạy trên EC2. Docker CLI trong Jenkins gửi lệnh qua socket. Container ứng dụng được tạo trên EC2, là container cùng cấp với Jenkins. Đây là mô hình dùng socket host, không phải chạy một Docker daemon riêng bên trong Jenkins.

**Phạm vi:** một EC2, một job, một ứng dụng, một nhánh deploy. Có gián đoạn ngắn khi thay container. Chưa có registry, load balancer, autoscaling, database migration hay triển khai nhiều máy. Một push có thể chứa nhiều commit; Jenkins có thể gộp các thay đổi khi xử lý hàng đợi, không bảo đảm một build riêng cho từng commit.

**Push/submit có nghĩa gì?** Commit cục bộ chưa trigger. `git push origin main` hoặc merge pull request vào `main` tạo thay đổi trên nhánh được theo dõi và có thể trigger. Mở pull request từ nhánh feature không tự deploy trong lab này.

## 2. Chuẩn bị và quy ước

- [ ] Tài khoản AWS có quyền tạo EC2, Security Group, EBS và snapshot khi cần.
- [ ] Tài khoản GitHub có quyền tạo repo và quản lý webhook.
- [ ] Máy cá nhân có Git, SSH và trình soạn thảo.
- [ ] EC2 được ra Internet để tải apt packages, Jenkins plugins, GitHub source và Docker images.
- [ ] Repo dùng cho lab chỉ có code tin cậy; không chứa dữ liệu hoặc secrets thật.

Khuyến nghị thực hành: EC2 `t3.medium` (2 vCPU, 4 GiB RAM), Ubuntu 24.04 **x86_64**, EBS gp3 **30 GiB trở lên**, mã hóa EBS. Đây là cấu hình đề xuất cho lab, không phải mức tối thiểu chính thức. Máy nhỏ hơn dễ chậm hoặc hết RAM khi Jenkins và build chạy chung.

| Giá trị | Ví dụ / cách dùng |
|---|---|
| `EC2_PUBLIC_IP` | Thay bằng public IPv4 thật của EC2 |
| `MY_PUBLIC_IP/32` | Public IPv4 của mạng máy cá nhân, không phải `192.168.x.x` |
| `GITHUB_OWNER` | Username hoặc tổ chức GitHub |
| Repository | `sample-ci-pipeline` |
| Nhánh | `main` |
| Jenkins job | `sample-ci-main` |
| Jenkins image tự build | `jenkins-docker:lts` |
| App đang chạy | `sample-ci-app` |
| Container rollback | `sample-ci-app-previous` |

Các code block không có dấu nhắc `$` để dễ copy. Thay placeholder trước khi chạy. Không nhập dấu `< >` quanh IP. Shell trên EC2 là Bash; Git Bash/WSL phù hợp nếu dùng Windows.

Node.js dùng nhánh 24 LTS. Các tag `node:24-alpine` và `jenkins/jenkins:lts-jdk21` có thể thay đổi theo cập nhật; sau khi lab chạy ổn nên ghi lại image digest để tái lập môi trường. Xem [lịch phát hành Node.js](https://github.com/nodejs/Release).

## 3. Tạo EC2 và Security Group

### 3.1. Tạo EC2

Trong AWS Console → EC2 → **Launch instance**:

1. Name: `lab-jenkins-cicd`.
2. AMI: Ubuntu Server 24.04 LTS, kiến trúc x86_64.
3. Instance type: `t3.medium`.
4. Tạo/chọn key pair; lưu file `.pem` trên máy cá nhân, không commit Git.
5. Chọn subnet có route Internet Gateway và bật public IPv4.
6. EBS root volume: gp3, 30 GiB hoặc lớn hơn, bật encryption.
7. Gắn Security Group ở bước tiếp theo và Launch.
8. Chờ status checks thành công; ghi lại public IPv4.

Public IP có thể đổi khi stop/start; có thể dùng Elastic IP để ổn định endpoint nhưng cần kiểm tra chi phí. Nếu IP đổi, sửa webhook và thông tin truy cập.

### 3.2. Security Group inbound

| Port TCP | Source | Mục đích |
|---|---|---|
| 22 | `MY_PUBLIC_IP/32` | SSH và tunnel quản trị |
| 3000 | `MY_PUBLIC_IP/32` | Xem ứng dụng lab |
| 8080 | Các CIDR trong trường `hooks` của GitHub Meta API | GitHub gọi webhook |

Không mở cổng 50000: lab không dùng inbound Jenkins agents. Không mở Docker TCP 2375/2376. Outbound mặc định cho phép Internet giúp lab đơn giản; môi trường hạn chế egress cần DNS, HTTPS và đường tới các registry/update site tương ứng.

Lấy CIDR webhook hiện tại từ máy có Internet, hoặc trên EC2 sau khi cài curl/python3:

```bash
curl -fsSL https://api.github.com/meta | python3 -c 'import json,sys; print("\n".join(json.load(sys.stdin)["hooks"]))'
```

Thêm từng IPv4 CIDR vào inbound TCP 8080. Nếu triển khai IPv6, thêm các CIDR IPv6 phù hợp và cấu hình mạng IPv6 tương ứng. Danh sách có thể đổi; không chép IP cố định từ tài liệu cũ. Nếu gặp giới hạn số rule, kiểm tra quota hoặc dùng thiết kế reverse proxy/firewall thích hợp. Tham khảo [GitHub IP addresses](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/about-githubs-ip-addresses).

**Lựa chọn mạng trong lab:** webhook HTTP chỉ dành cho repo mẫu không có thông tin nhạy cảm; quản trị Jenkins qua SSH tunnel. HTTP không mã hóa payload. Với repo private thật, dùng HTTPS với chứng chỉ hợp lệ và cấu hình xác thực webhook trước khi đưa vào sử dụng; xem mục 16. Không cần mở 8080 cho toàn Internet để làm lab.

### 3.3. SSH và mở tunnel

**Chạy trên máy cá nhân:**

```bash
chmod 400 lab-jenkins.pem
ssh -i lab-jenkins.pem ubuntu@EC2_PUBLIC_IP
```

Ở terminal thứ hai trên máy cá nhân, tạo tunnel và giữ terminal này mở:

```bash
ssh -i lab-jenkins.pem -N -L 18080:127.0.0.1:8080 ubuntu@EC2_PUBLIC_IP
```

Sau khi Jenkins chạy, truy cập `http://localhost:18080`. Cổng 18080 là cổng máy cá nhân; 8080 là cổng EC2. GitHub không thể sử dụng `localhost:18080` của bạn.

## 4. Cài Docker trên EC2

**Chạy trong SSH trên EC2 Ubuntu mới.** Nếu máy đã có Docker đang phục vụ hệ thống khác, kiểm kê trước, không gỡ cài đặt tùy tiện.

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl git jq python3
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

. /etc/os-release
printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu %s stable\n' \
  "$(dpkg --print-architecture)" "$VERSION_CODENAME" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo docker run --rm hello-world
sudo usermod -aG docker ubuntu
```

Thoát SSH rồi đăng nhập lại để cập nhật group. Sau đó:

```bash
docker version
docker compose version
docker buildx version
id
systemctl is-active docker
```

`docker version` phải có cả Client và Server. Quyền group `docker` rất mạnh, gần tương đương root trên host. Hướng dẫn cài đặt và lưu ý firewall: [Docker Engine trên Ubuntu](https://docs.docker.com/engine/install/ubuntu/).

## 5. Triển khai Jenkins trong Docker

### 5.1. Tạo image Jenkins có Docker CLI và Buildx

**Chạy trên EC2:**

```bash
mkdir -p ~/jenkins-lab
cd ~/jenkins-lab
cat > Dockerfile.jenkins <<'DOCKERFILE'
FROM jenkins/jenkins:lts-jdk21
USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl git \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && . /etc/os-release \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian ${VERSION_CODENAME} stable" > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends docker-ce-cli docker-buildx-plugin \
    && rm -rf /var/lib/apt/lists/*
USER jenkins
RUN jenkins-plugin-cli --plugins workflow-aggregator git github credentials-binding timestamper
DOCKERFILE

docker build --progress=plain -t jenkins-docker:lts -f Dockerfile.jenkins .
```

Image Jenkins dùng Debian nên repository apt bên trong image là **Debian**, dù EC2 host là Ubuntu. Chỉ cài CLI và Buildx bên trong Jenkins, không cài/chạy daemon thứ hai. Pipeline dùng lệnh `sh` gọi Docker CLI, không yêu cầu plugin Docker Pipeline.

### 5.2. Persistent volume và quyền socket theo GID

```bash
cd ~/jenkins-lab
printf 'DOCKER_GID=%s\n' "$(stat -c '%g' /var/run/docker.sock)" > .env
cat > compose.yaml <<'YAML'
services:
  jenkins:
    image: jenkins-docker:lts
    container_name: jenkins
    restart: unless-stopped
    init: true
    ports:
      - "8080:8080"
    environment:
      JAVA_OPTS: "-Xms256m -Xmx1536m"
    group_add:
      - "${DOCKER_GID}"
    volumes:
      - jenkins_home:/var/jenkins_home
      - /var/run/docker.sock:/var/run/docker.sock
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
volumes:
  jenkins_home:
    name: jenkins_home
YAML

docker compose up -d
docker compose ps
docker logs --tail 100 jenkins
docker exec jenkins id
docker exec jenkins docker version
docker exec jenkins docker buildx version
```

`group_add` dùng GID thật của socket host, không đoán là 999. User Jenkins vẫn không phải root nhưng có thể điều khiển Docker daemon. Mount socket đồng nghĩa Jenkins/job có quyền rất lớn trên EC2; không dùng cho code không tin cậy.

Volume `jenkins_home` lưu jobs, plugins, credentials và workspace qua các lần recreate container. Không chạy `docker compose down -v` nếu muốn giữ Jenkins. Xem nền tảng chạy container Jenkins tại [Jenkins Docker installation](https://www.jenkins.io/doc/book/installing/docker/); mẫu socket ở đây là lựa chọn riêng cho lab.

### 5.3. Mở khóa và cấu hình Jenkins

```bash
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

1. Mở tunnel ở mục 3.3, vào `http://localhost:18080`.
2. Nhập mật khẩu khởi tạo, cài **Suggested plugins** nếu wizard yêu cầu.
3. Tạo tài khoản admin riêng, lưu mật khẩu an toàn.
4. Manage Jenkins → Plugins: kiểm tra Pipeline, Git, GitHub, Credentials Binding, Timestamper.
5. Manage Jenkins → System → Jenkins Location: đặt Jenkins URL theo endpoint thực tế, ví dụ `http://EC2_PUBLIC_IP:8080/` cho lab HTTP. Việc trình duyệt đang dùng tunnel có thể làm một số link tuyệt đối cần đổi về `localhost:18080`; webhook luôn dùng địa chỉ GitHub truy cập được.
6. Manage Jenkins → Nodes → Built-In Node → Configure: đặt **1 executor** cho lab.
7. Không bật anonymous administrative access, giữ CSRF protection.

Lab chạy build trên built-in node để dễ học. Production nên đặt controller executor bằng 0 và dùng agent riêng.

**Checkpoint:**

- [ ] Đăng nhập được Jenkins qua tunnel.
- [ ] `docker exec jenkins docker ps` thành công.
- [ ] Jenkins volume tồn tại: `docker volume inspect jenkins_home`.

## 6. Tạo ứng dụng Node.js

Để người học chỉ cần Git/SSH, các bước tạo source dưới đây chạy trong **SSH trên EC2, user ubuntu**, ngoài Jenkins. Thư mục này đóng vai trò working copy của developer. Nếu máy cá nhân đã có Node.js 24 hoặc Docker, có thể thực hiện ở máy cá nhân thay thế.

```bash
mkdir -p ~/sample-ci-pipeline/test
cd ~/sample-ci-pipeline
```

Tạo từng file bằng editor (`nano app.js`, rồi dán nội dung, lưu). Tất cả file bên dưới phải nằm đúng vị trí:

```text
sample-ci-pipeline/
├── app.js
├── package.json
├── package-lock.json     # Sinh bằng npm, phải commit
├── test/
│   └── app.test.js
├── Dockerfile
├── .dockerignore
├── .gitignore
└── Jenkinsfile
```

### 6.1. File `app.js`

Ứng dụng dùng HTTP server và test runner có sẵn trong Node.js để lab không phụ thuộc framework. Vẫn giữ `npm ci` như ứng dụng thực tế; khi thêm dependencies sau này phải cập nhật lockfile.

```javascript
'use strict';
const http = require('node:http');

function createServer() {
  return http.createServer((req, res) => {
    if (req.method === 'GET' && req.url === '/health') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ status: 'ok' }));
      return;
    }
    if (req.method === 'GET' && req.url === '/') {
      res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end('Hello from Jenkins CI/CD on AWS EC2!\n');
      return;
    }
    res.writeHead(404, { 'Content-Type': 'text/plain' });
    res.end('Not found\n');
  });
}

if (require.main === module) {
  const port = Number(process.env.PORT || 3000);
  const server = createServer();
  server.listen(port, '0.0.0.0', () => console.log(`Listening on ${port}`));
  process.on('SIGTERM', () => server.close(() => process.exit(0)));
}

module.exports = { createServer };
```

### 6.2. File `package.json`

```json
{
  "name": "sample-ci-pipeline",
  "version": "1.0.0",
  "private": true,
  "description": "CI/CD lab with GitHub, Jenkins and EC2",
  "scripts": {
    "start": "node app.js",
    "test": "node --test"
  },
  "engines": {
    "node": ">=24 <25"
  }
}
```

### 6.3. File `test/app.test.js`

Test khởi động server trên cổng ngẫu nhiên để tránh đụng cổng 3000, gửi HTTP request thật rồi đóng server.

```javascript
'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');
const { createServer } = require('../app');

async function request(t, path) {
  const server = createServer();
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(() => new Promise((resolve, reject) => {
    server.close(error => error ? reject(error) : resolve());
    server.closeAllConnections();
  }));
  const response = await fetch(`http://127.0.0.1:${server.address().port}${path}`);
  return { status: response.status, text: await response.text() };
}

test('GET / returns the welcome message', async t => {
  const response = await request(t, '/');
  assert.equal(response.status, 200);
  assert.match(response.text, /Hello from Jenkins/);
});

test('GET /health returns ok', async t => {
  const response = await request(t, '/health');
  assert.equal(response.status, 200);
  assert.deepEqual(JSON.parse(response.text), { status: 'ok' });
});

test('Unknown route returns 404', async t => {
  const response = await request(t, '/missing');
  assert.equal(response.status, 404);
});
```

### 6.4. File `.gitignore`

```gitignore
node_modules/
coverage/
*.log
.env
.env.*
*.pem
.DS_Store
```

### 6.5. Sinh lockfile và test local

**Chạy trên EC2, trong `~/sample-ci-pipeline`:**

```bash
docker run --rm --user "$(id -u):$(id -g)" \
  -e npm_config_cache=/tmp/npm-cache \
  -v "$PWD:/app" -w /app node:24-alpine \
  npm install --package-lock-only --ignore-scripts

docker run --rm --user "$(id -u):$(id -g)" \
  -e npm_config_cache=/tmp/npm-cache \
  -v "$PWD:/app" -w /app node:24-alpine \
  sh -c 'npm ci && npm test'

ls -l package.json package-lock.json test/app.test.js
```

Kỳ vọng: **3 tests passed**, exit code 0. Không dùng `echo "Test passed"` thay test thật. Lockfile phải được tạo trước khi build Docker và được commit. `npm ci` không tự sửa lockfile khi lệch `package.json`.

**Lưu ý đường dẫn:** bind mount `$PWD:/app` ở đây hợp lệ vì CLI chạy trực tiếp trên EC2. Không bê nguyên lệnh này vào Jenkins container; Docker host có thể không có đường dẫn workspace mà Jenkins nhìn thấy. Pipeline ở phần sau gửi build context qua Docker CLI để tránh vấn đề này.

## 7. Dockerfile và build thử

### 7.1. File `Dockerfile`

```dockerfile
FROM node:24-alpine AS dependencies
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci

FROM dependencies AS test
COPY app.js ./
COPY test/ ./test/
RUN npm test

FROM node:24-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production
ENV PORT=3000
COPY --from=test --chown=node:node /app/app.js ./app.js
USER node
EXPOSE 3000
HEALTHCHECK --interval=5s --timeout=3s --start-period=10s --retries=5 \
  CMD node -e "fetch('http://127.0.0.1:3000/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["node", "app.js"]
```

Runtime cố ý chỉ copy `app.js` vì mẫu dùng thư viện built-in. Nếu thêm Express hoặc dependencies khác, cần thêm bước cài/copy production dependencies vào runtime; không chỉ sửa `package.json` rồi giữ nguyên Dockerfile này.

Target `runtime` phụ thuộc target `test`, nên build final image vẫn có ràng buộc test. Jenkins gọi từng target để thấy rõ Install/Test/Build; Docker có thể dùng cache của bước đã thành công. Test `CACHED` là tái sử dụng kết quả trên input không đổi, không phải chạy lại test lần đó.

### 7.2. File `.dockerignore`

```dockerignore
.git
node_modules
coverage
*.log
.env
.env.*
*.pem
.DS_Store
Jenkinsfile
README.md
```

File này phải ở gốc build context. Không loại `package.json`, `package-lock.json`, `app.js` hoặc `test/`. Chỉ `COPY` vài file trong Dockerfile chưa thay thế vai trò kiểm soát context của `.dockerignore`.

### 7.3. Build và chạy thử

**Trên EC2, thư mục source:**

```bash
cd ~/sample-ci-pipeline
docker build --progress=plain --target runtime -t sample-ci-app:local .
docker run -d --name sample-ci-local -p 127.0.0.1:3001:3000 sample-ci-app:local
curl -fsS http://127.0.0.1:3001/
curl -fsS http://127.0.0.1:3001/health
docker inspect --format '{{.State.Health.Status}}' sample-ci-local
docker logs --tail 50 sample-ci-local
docker rm -f sample-ci-local
```

Nếu health đang `starting`, đợi vài giây rồi kiểm tra lại. Kỳ vọng `/health` trả `{"status":"ok"}`. Bước này dùng 3001 chỉ ở loopback, không chiếm 3000 mà pipeline sẽ deploy.

## 8. Jenkinsfile đầy đủ

Tạo file **`Jenkinsfile`** đúng chữ hoa/thường, ngay gốc repository. Pipeline chỉ được dùng cho một job `main` với tên container dành riêng cho lab này. Không tạo nhiều job cùng deploy vào tên container dưới đây.

```groovy
pipeline {
    agent any

    options {
        skipDefaultCheckout(true)
        disableConcurrentBuilds()
        timestamps()
        timeout(time: 30, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '20'))
    }

    triggers {
        githubPush()
    }

    environment {
        IMAGE_NAME = 'sample-ci-app'
        APP_NAME = 'sample-ci-app'
        PREVIOUS_NAME = 'sample-ci-app-previous'
        APP_PORT = '3000'
    }

    stages {
        stage('Checkout') {
            steps {
                deleteDir()
                checkout scm
                script {
                    def sha = sh(script: 'git rev-parse --short=12 HEAD',
                                 returnStdout: true).trim()
                    env.IMAGE_TAG = "${env.BUILD_NUMBER}-${sha}"
                }
                sh '''
                    set -eu
                    pwd
                    ls -la
                    test -f package.json
                    test -f package-lock.json
                    test -f Dockerfile
                    test -f test/app.test.js
                    docker version
                    docker buildx version
                '''
            }
        }

        stage('Install') {
            steps {
                sh '''
                    set -eu
                    docker build --progress=plain --target dependencies \
                      -t "$IMAGE_NAME:deps-$IMAGE_TAG" .
                '''
            }
        }

        stage('Test') {
            steps {
                sh '''
                    set -eu
                    docker build --progress=plain --target test \
                      -t "$IMAGE_NAME:test-$IMAGE_TAG" .
                '''
            }
        }

        stage('Build') {
            steps {
                sh '''
                    set -eu
                    docker build --progress=plain --target runtime \
                      --label "org.opencontainers.image.revision=$(git rev-parse HEAD)" \
                      -t "$IMAGE_NAME:$IMAGE_TAG" .
                '''
            }
        }

        stage('Deploy') {
            steps {
                sh '''
                    set -eu
                    had_previous=0
                    deploy_started=0
                    success=0

                    wait_healthy() {
                        name="$1"
                        count=0
                        while [ "$count" -lt 30 ]; do
                            status=$(docker inspect --format '{{.State.Health.Status}}' "$name" 2>/dev/null || echo missing)
                            case "$status" in
                                healthy) return 0 ;;
                                unhealthy|missing) return 1 ;;
                            esac
                            count=$((count + 1))
                            sleep 2
                        done
                        return 1
                    }

                    recover() {
                        rc=$?
                        trap - EXIT HUP INT TERM
                        if [ "$success" -ne 1 ] && [ "$deploy_started" -eq 1 ]; then
                            docker logs --tail 100 "$APP_NAME" || true
                            docker rm -f "$APP_NAME" || true
                            if [ "$had_previous" -eq 1 ]; then
                                echo 'Deploy failed; restoring previous container'
                                if docker rename "$PREVIOUS_NAME" "$APP_NAME" && docker start "$APP_NAME"; then
                                    if wait_healthy "$APP_NAME"; then
                                        echo 'Previous version is healthy again'
                                    else
                                        echo 'WARNING: restored container is not healthy; investigate now'
                                    fi
                                else
                                    echo 'WARNING: automatic restore failed; inspect containers manually'
                                fi
                            fi
                        fi
                        exit "$rc"
                    }
                    trap recover EXIT
                    trap 'exit 130' INT
                    trap 'exit 143' HUP TERM

                    if docker container inspect "$APP_NAME" >/dev/null 2>&1; then
                        # Keep only one previous container. Stop on cleanup errors.
                        if docker container inspect "$PREVIOUS_NAME" >/dev/null 2>&1; then
                            docker rm -f "$PREVIOUS_NAME"
                        fi
                        docker stop "$APP_NAME"
                        docker rename "$APP_NAME" "$PREVIOUS_NAME"
                        had_previous=1
                    fi
                    deploy_started=1

                    docker run -d --name "$APP_NAME" \
                      --restart unless-stopped \
                      --log-opt max-size=10m --log-opt max-file=3 \
                      -p "$APP_PORT:3000" \
                      "$IMAGE_NAME:$IMAGE_TAG"

                    if ! wait_healthy "$APP_NAME"; then
                        echo 'New container did not become healthy'
                        exit 1
                    fi

                    docker exec "$APP_NAME" node -e "fetch('http://127.0.0.1:3000/').then(async r=>{if(!r.ok) throw Error(r.status); console.log(await r.text())}).catch(e=>{console.error(e);process.exit(1)})"
                    success=1
                    echo "Deployed $IMAGE_NAME:$IMAGE_TAG"
                '''
            }
        }
    }

    post {
        always {
            sh '''
                docker ps -a --filter name=sample-ci-app || true
                if [ -n "${IMAGE_TAG:-}" ]; then
                    docker image rm "$IMAGE_NAME:deps-$IMAGE_TAG" "$IMAGE_NAME:test-$IMAGE_TAG" || true
                fi
            '''
        }
        success {
            echo "Deploy successful: ${env.IMAGE_NAME}:${env.IMAGE_TAG}"
        }
        failure {
            echo 'Build failed. Read the first failing stage; check current app health.'
        }
    }
}
```

**Giải thích:**

| Stage / cấu hình | Ý nghĩa |
|---|---|
| Checkout | Xóa workspace cũ, lấy source nhánh cấu hình trong job, kiểm tra file bắt buộc |
| Install | Build target `dependencies`, chạy `npm ci` trong Node container |
| Test | Chạy 3 test HTTP; lỗi làm pipeline dừng trước deploy |
| Build | Tạo runtime image với tag `buildNumber-commitSHA` và label full SHA |
| Deploy | Stop/đổi tên app cũ, chạy app mới, chờ Docker healthcheck, thử request |
| `disableConcurrentBuilds()` | Xếp hàng build cùng job, tránh 2 lần deploy đồng thời |
| `timeout` | Giới hạn thời gian toàn pipeline, giúp phát hiện treo |
| `post` | In trạng thái và bỏ tag trung gian; không tự xóa image rollback |

Healthcheck bên trong container xác nhận tiến trình ứng dụng. Nó chưa chứng minh Security Group hoặc port publish hoạt động; cần kiểm tra từ EC2 và máy cá nhân ở mục 12.

Rollback tự động là **best effort**: Jenkins/EC2 bị tắt, kill cưỡng bức, daemon lỗi hoặc lệnh stop/rename lỗi giữa chừng vẫn cần xử lý thủ công. Một lần chạy thành công đầu tiên chưa có bản cũ để khôi phục. Pipeline không rollback dữ liệu ngoài container.

## 9. Tạo GitHub repository và credentials

### 9.1. Tạo repo

GitHub → New repository → tên `sample-ci-pipeline` → Public hoặc Private → **không tạo sẵn README/.gitignore/license** vì source đã có sẵn. Nếu dùng HTTP webhook, chỉ đưa source mẫu vào repo.

**Chạy trong thư mục source trên EC2 (hoặc máy developer):**

```bash
cd ~/sample-ci-pipeline
git init -b main
git config user.name "YOUR_NAME"
git config user.email "YOUR_GIT_EMAIL"
git add app.js package.json package-lock.json test/app.test.js Dockerfile .dockerignore .gitignore Jenkinsfile
git status
git commit -m "Initial working CI/CD lab"
git remote add origin https://github.com/GITHUB_OWNER/sample-ci-pipeline.git
git push -u origin main
```

Khi HTTPS yêu cầu password, dùng Personal Access Token có quyền push repo thay cho mật khẩu tài khoản, hoặc sử dụng SSH/Git credential manager đã cấu hình. Không đặt token vào URL, Jenkinsfile hoặc lệnh được ghi log. Token developer để push cần quyền ghi; credential Jenkins checkout chỉ cần đọc.

### 9.2. Repo private: tạo credential checkout

1. GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens.
2. Chọn resource owner đúng, chọn duy nhất repo lab, thời hạn phù hợp.
3. Repository permissions: **Contents: Read-only**; Metadata read là quyền đi kèm. Organization có thể yêu cầu approval/SSO và chính sách riêng.
4. Trong Jenkins → Manage Jenkins → Credentials → System → Global credentials → Add Credentials.
5. Kind: **Username with password**.
6. Username: username GitHub; Password: token; ID: **`github-readonly`**.
7. Chọn credential này trong phần Git SCM của job ở mục 10.

Repo public có thể checkout không cần credentials. Không dùng credential loại Secret text cho ô credential HTTPS Git checkout. Token webhook/API và token Git checkout có mục đích khác nhau. Lab tạo webhook thủ công trên GitHub nên Jenkins không cần quyền quản trị webhook của repo.

Tham khảo [Jenkins Git plugin — credentials](https://plugins.jenkins.io/git/) và [GitHub personal access tokens](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens).

## 10. Tạo Pipeline Jenkins

1. Dashboard → **New Item** → `sample-ci-main` → **Pipeline** → OK.
2. Có thể chọn GitHub project và nhập URL repository.
3. Build Triggers → chọn **GitHub hook trigger for GITScm polling**. Jenkinsfile cũng khai báo `githubPush()` để lưu cấu hình trigger cùng source.
4. Pipeline → Definition: **Pipeline script from SCM**.
5. SCM: **Git**.
6. Repository URL: `https://github.com/GITHUB_OWNER/sample-ci-pipeline.git`.
7. Credentials: `github-readonly` nếu private; none nếu public.
8. Branch Specifier: **`*/main`**.
9. Script Path: **`Jenkinsfile`**; chú ý chữ hoa và không thêm tên repo vào trước.
10. Save → **Build Now** một lần để bootstrap, kiểm tra SCM và đăng ký cấu hình từ Jenkinsfile.

Vào Build → Console Output, xác nhận đủ 5 stage và kết quả SUCCESS. Nếu lỗi trước Checkout, thường do Jenkins chưa đọc được Jenkinsfile từ SCM: kiểm tra URL, credentials, branch và Script Path.

Build thủ công đầu tiên chưa chứng minh webhook hoạt động. Phải thực hiện push mới ở mục 12.

**Checkpoint trên EC2:**

```bash
docker ps --filter name=sample-ci-app
docker inspect --format '{{.Config.Image}} {{.State.Health.Status}}' sample-ci-app
curl -fsS http://127.0.0.1:3000/health
```

## 11. Cấu hình và kiểm tra GitHub Webhook

### 11.1. Tạo webhook

GitHub repo → Settings → Webhooks → Add webhook:

| Trường | Giá trị |
|---|---|
| Payload URL | `http://EC2_PUBLIC_IP:8080/github-webhook/` |
| Content type | `application/json` |
| Secret | Để trống **chỉ trong lab HTTP với source mẫu**, hoặc cấu hình cùng secret và xác minh ở Jenkins/reverse proxy |
| Events | **Just the push event** |
| Active | Bật |

Endpoint cần dấu `/` cuối. Không dùng `/job/sample-ci-main/build`, private IP EC2 hay `localhost`. HTTPS thì giữ SSL verification bật và dùng chứng chỉ hợp lệ. Hướng dẫn tích hợp: [Jenkins GitHub plugin](https://plugins.jenkins.io/github/).

GitHub sẽ gửi ping sau khi thêm hook. Trong **Recent Deliveries**, mở delivery và xem:

- Request URL và headers: sự kiện `ping` hoặc `push`.
- Response status: thường 2xx khi endpoint chấp nhận.
- Nếu lỗi, xem response body và đối chiếu mục 14.4.

Ping thành công chỉ chứng minh endpoint nhận request; ping không phải push và không chứng minh job được build. Push được nhận 2xx cũng chưa đảm bảo SCM có thay đổi trên nhánh `main`.

### 11.2. Kiểm tra đường đi của request

**Trên EC2:**

```bash
docker logs --since 10m jenkins
curl -I http://127.0.0.1:8080/login
sudo ss -lntp | grep -E ':8080|:3000'
```

Log Jenkins mặc định có thể không ghi từng webhook. Nếu cần: Manage Jenkins → System Log → Add new log recorder → thêm logger `org.jenkinsci.plugins.github` mức FINE và `com.cloudbees.jenkins.GitHubPushTrigger` mức FINE trong thời gian chẩn đoán, sau đó giảm mức log.

`curl -I` trên `/login` chỉ kiểm tra Jenkins HTTP. Gửi GET tới `/github-webhook/` không tương đương GitHub POST với payload thật; không dùng kết quả đó làm bằng chứng trigger.

Có thể dùng **Redeliver** trong Recent Deliveries để thử lại sau khi sửa mạng. Nếu commit đã build, Jenkins có thể không tạo build mới. Cách thử chắc chắn là push commit mới. Tham khảo [Testing webhooks](https://docs.github.com/en/webhooks/testing-and-troubleshooting-webhooks/testing-webhooks).

## 12. Push code và nghiệm thu CI/CD

### 12.1. Trigger một thay đổi thật

Trong working copy developer, sửa dòng lời chào `app.js` thành:

```javascript
res.end('Hello from Jenkins CI/CD on AWS EC2 - version 2!\n');
```

Giữ nguyên các phần khác. Test vẫn hợp lệ vì kiểm tra cụm `Hello from Jenkins`.

```bash
git diff
git add app.js
git commit -m "Update welcome message to version 2"
git push origin main
```

Không bấm Build Now. Quan sát GitHub delivery `push` và Jenkins tự xuất hiện build. Console Output thường ghi nguồn khởi tạo là GitHub push; stage Checkout phải trỏ đến commit vừa push.

### 12.2. Kiểm tra sau deploy

**Trên EC2:**

```bash
docker ps -a --filter name=sample-ci-app
docker inspect --format '{{.Config.Image}}' sample-ci-app
docker inspect --format '{{json .State.Health}}' sample-ci-app
docker inspect --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' sample-ci-app
docker logs --tail 100 sample-ci-app
curl -fsS http://127.0.0.1:3000/
curl -fsS http://127.0.0.1:3000/health
```

**Trên máy cá nhân:** mở `http://EC2_PUBLIC_IP:3000/` hoặc chạy:

```bash
curl -fsS http://EC2_PUBLIC_IP:3000/
```

Kỳ vọng lời chào có `version 2`, Docker health là `healthy`, image tag và revision khớp build. Sau lần deploy thứ hai có `sample-ci-app-previous` ở trạng thái stopped/Exited, sẵn sàng rollback.

### 12.3. Chứng minh test bảo vệ deploy

1. Ghi lại image hiện tại: `docker inspect --format '{{.Config.Image}}' sample-ci-app`.
2. Trong `test/app.test.js`, tạm đổi expected status của test `/health` từ `200` thành `500`.
3. Commit/push. Jenkins phải đỏ ở **Test**, stage Build/Deploy bị bỏ qua.
4. Kiểm tra app vẫn trả lời, image đang chạy vẫn như bước 1.
5. Nếu đây là commit mới nhất, hoàn tác bằng `git revert HEAD`, rồi `git push origin main`; build mới phải xanh.

Đây là bài kiểm tra chủ động, không giữ test sai trong repo sau khi hoàn thành.

## 13. Rollback cơ bản

### 13.1. Rollback khi deploy mới thất bại

Jenkinsfile giữ một container cũ cùng cấu hình port/restart, rồi thử khôi phục nếu app mới không healthy. Build vẫn được đánh dấu **FAILURE** để người vận hành biết đã có lỗi. Luôn kiểm tra app và log sau rollback, không suy ra dịch vụ đã phục hồi chỉ từ dòng “restoring”.

### 13.2. Rollback thủ công sang container trước đó

Trong Jenkins, tạm Disable job (nếu UI có mục này) hoặc bỏ trigger, **đợi build đang chạy kết thúc**, kiểm tra không còn deploy. Điều này tránh pipeline tranh chấp tên container khi thao tác thủ công.

**Trên EC2:**

```bash
docker ps -a --filter name=sample-ci-app
docker inspect --format '{{.Config.Image}}' sample-ci-app-previous
```

Nếu không có previous, dừng tại đây và dùng mục 13.3. Nếu có, chạy lần lượt, chỉ tiếp tục khi lệnh trước thành công:

```bash
docker stop sample-ci-app
docker rename sample-ci-app "sample-ci-app-failed-$(date +%s)"
docker rename sample-ci-app-previous sample-ci-app
docker start sample-ci-app
curl -fsS http://127.0.0.1:3000/health
docker inspect --format '{{.State.Health.Status}}' sample-ci-app
```

Đợi vài giây nếu `starting`. Container lỗi được giữ lại để xem log; ghi lại tên trước khi xóa nó. Nếu rename/start lỗi, kiểm tra `docker ps -a` và phục hồi đúng tên; không xóa hàng loạt.

### 13.3. Rollback theo image tag

```bash
docker image ls sample-ci-app
```

Chọn tag runtime đã biết hoạt động, ví dụ `7-a1b2c3d4e5f6` (ví dụ, phải thay bằng tag thật). Dừng/đổi tên app hiện tại như mục 13.2 rồi:

```bash
docker run -d --name sample-ci-app --restart unless-stopped \
  --log-opt max-size=10m --log-opt max-file=3 \
  -p 3000:3000 sample-ci-app:TAG_THAT_WORKED
curl -fsS http://127.0.0.1:3000/health
```

Sau khi ổn định, sửa hoặc `git revert COMMIT_BAD` trên source và push. Nếu bật lại job mà source vẫn lỗi, lần build tiếp theo có thể deploy lỗi lần nữa. Bật lại trigger sau khi đã quyết định cách đồng bộ source với phiên bản mong muốn.

Rollback image/container không đảo ngược thay đổi database. Image chỉ lưu trên EC2 có thể mất khi ổ đĩa bị xóa; triển khai thực tế nên dùng registry và chính sách giữ phiên bản.

## 14. Troubleshooting

### 14.1. `package.json not found`, `ENOENT` hoặc `COPY ... not found`

**Phân biệt:** lỗi `npm` là không thấy file trong working directory của npm; lỗi `COPY` là file không có trong build context hoặc bị ignore.

Trong Jenkins Console, xem `pwd`, `ls -la` của stage Checkout. Có thể thêm tạm:

```groovy
sh '''
    pwd
    find . -maxdepth 3 -name package.json -print
    git rev-parse HEAD
    git ls-files
'''
```

| Nguyên nhân | Cách sửa |
|---|---|
| Chưa commit/push file | `git status`, `git add package.json package-lock.json`, commit/push |
| Job checkout sai branch/repo | Kiểm tra SCM URL, `*/main`, SHA trong Console |
| Source nằm trong `backend/` | Dùng context `backend` ở cả ba lệnh build, ví dụ `docker build --target test -f backend/Dockerfile backend` và sửa các bước kiểm tra file |
| Dockerfile có `WORKDIR` sai | Đặt `/app`, copy manifests trước `RUN npm ci` |
| `.dockerignore` loại nhầm | Xóa rule làm mất manifest, lockfile hoặc test |
| Dùng `docker build .` từ thư mục cha | `cd` đúng root repo hoặc truyền context đúng |
| Jenkinsfile nằm sai chỗ | Sửa Script Path hoặc chuyển file về gốc |
| `package-lock.json` thiếu/không khớp | Chạy `npm install --package-lock-only` trong môi trường Node đúng rồi commit cả hai manifests |

Không tạo `package.json` giả trong workspace Jenkins để chữa tạm; lần checkout sau sẽ mất. Sửa source trong Git.

### 14.2. Jenkins treo ở `docker build` / `LOADING build context`

**Bước 1 — Xác định dòng thực sự đang chờ.** Luôn dùng `--progress=plain` như lab. `load build context` khác `load metadata for node:24-alpine`, `RUN npm ci`, hay `exporting layers`.

**Bước 2 — Kiểm tra dung lượng context tại đúng thư mục build.** Trong source hoặc Jenkins workspace qua stage `sh`:

```bash
pwd
du -sh . .git node_modules 2>/dev/null || true
find . -type f -size +100M -print
cat .dockerignore
```

Context cho mẫu này nên rất nhỏ. Nếu hàng trăm MB/GB, thường build nhầm `/`, home, Jenkins home, hoặc kéo theo `.git`, `node_modules`, backups, logs, archives. Đặt `.dockerignore` ở root context và chuyển các dữ liệu không thuộc source ra ngoài. Không build context là toàn bộ `/var/jenkins_home`.

**Bước 3 — Kiểm tra EC2 và daemon:**

```bash
df -hT
df -i
free -h
docker stats --no-stream
docker system df -v
docker info
sudo journalctl -u docker --since '20 minutes ago' --no-pager
sudo dmesg -T | grep -Ei 'oom|out of memory|killed process|I/O error' || true
```

CPU/RAM nhỏ, EBS gần đầy, inode hết hoặc I/O thấp đều có thể làm build trông như treo. Nếu OOM, tăng tài nguyên hoặc giảm executor; restart Jenkins chưa giải quyết nguyên nhân. Quan sát EC2 Monitoring và EBS metrics nếu chậm kéo dài.

**Bước 4 — Nếu chờ tải image/network:**

```bash
docker pull node:24-alpine
curl -I https://registry-1.docker.io/v2/
docker run --rm node:24-alpine node -e "require('node:dns').lookup('registry.npmjs.org',console.log)"
```

Registry trả `401 Unauthorized` cho request không xác thực có thể là kết quả bình thường: đường mạng/TLS đã tới registry, chưa chứng minh pull được. Kiểm tra DNS, egress, proxy, NAT/route, rate limit và Docker daemon logs. Mẫu không có npm dependencies ngoài nhưng Node image vẫn cần tải.

**Bước 5 — Build độc lập trên EC2 từ cùng commit:**

```bash
cd ~/sample-ci-pipeline
git fetch origin
git rev-parse HEAD
git rev-parse origin/main
docker build --progress=plain --target test -t sample-ci-app:debug .
```

Bảo đảm working copy sạch và cùng SHA với Jenkins trước khi so sánh; không `reset --hard` lên thay đổi chưa lưu. Nếu host build được nhưng Jenkins không, kiểm tra socket, GID, Docker CLI/Buildx và workspace. Nếu cả hai lỗi, ưu tiên source/daemon/network/storage.

Chỉ dùng `--no-cache` sau khi có lý do nghi cache lỗi; nó có thể tăng thời gian và dung lượng. Không restart daemon hoặc prune trong lúc pipeline khác đang hoạt động. Nếu build timeout, kiểm tra Docker vẫn còn công việc/container nào trước khi chạy lại.

### 14.3. `permission denied` với `/var/run/docker.sock`

**Chạy trên EC2:**

```bash
stat -c '%A %U %G %g %n' /var/run/docker.sock
docker exec jenkins id
docker exec jenkins ls -ln /var/run/docker.sock
docker inspect --format '{{json .HostConfig.GroupAdd}}' jenkins
docker exec jenkins docker version
```

GID socket phải có trong supplementary groups của Jenkins. `usermod -aG docker ubuntu` chỉ cấp quyền user host, không cấp quyền cho user Jenkins trong container.

Sửa cấu hình, trong thời gian không có build chạy:

```bash
cd ~/jenkins-lab
printf 'DOCKER_GID=%s\n' "$(stat -c '%g' /var/run/docker.sock)" > .env
docker compose up -d --force-recreate
docker exec jenkins docker ps
```

Không dùng `chmod 666 /var/run/docker.sock` để mở quyền cho mọi user. Không chỉ thêm group tên `docker` bên trong image rồi giả định GID sẽ đúng. Nếu thông báo **Cannot connect to Docker daemon**, kiểm tra daemon chạy, socket mount tồn tại và biến `DOCKER_HOST`; đó không nhất thiết là lỗi quyền.

```bash
sudo systemctl status docker --no-pager
docker inspect --format '{{json .Mounts}}' jenkins
docker exec jenkins sh -c 'echo "${DOCKER_HOST:-default-unix-socket}"'
```

### 14.4. Webhook không trigger

Đi theo thứ tự **GitHub delivery → mạng → Jenkins endpoint → SCM/job → commit mới**.

| Hiện tượng | Kiểm tra / xử lý |
|---|---|
| Không có push delivery | Hook Active, đúng repo, chọn push event, thực sự đã push chưa |
| Connection timeout | IP hiện tại, public subnet/route, SG 8080 có GitHub hooks CIDR, NACL và firewall |
| Connection refused | Jenkins có chạy và publish 8080 không, `docker ps`, `docker logs jenkins` |
| 404 | Sai endpoint; phải `/github-webhook/`; có context prefix/reverse proxy thì kiểm tra rewrite |
| 301/302 hoặc HTML login | Hook trỏ sai URL hoặc proxy/auth đang redirect; dùng endpoint cuối cùng trực tiếp |
| 403 / signature error | Secret không khớp, proxy chặn request, xác minh chữ ký sai; đọc response/log |
| SSL error | DNS/cert chain/hostname; không tắt verify làm cách sửa lâu dài |
| 2xx nhưng không build | Bật trigger, job không disabled, đã Build Now bootstrap, URL SCM khớp, branch `main` có thay đổi mới |
| Job nằm trong Queue | Executor bằng 0, node offline hoặc build trước đang chạy do chống concurrent |
| Build chạy nhưng checkout lỗi | PAT hết hạn/thiếu quyền, organization approval, repo/branch sai |
| Public IP đổi | Sửa Payload URL/Jenkins URL hoặc dùng địa chỉ ổn định |

Giữ CSRF protection bật; endpoint GitHub plugin xử lý webhook riêng. Không tắt toàn bộ bảo vệ Jenkins để sửa 403. SG chỉ giới hạn theo IP/port, không lọc được URL `/github-webhook/`.

Trong repo developer, có thể tạo commit rỗng để kiểm tra luồng mà không đổi ứng dụng:

```bash
git commit --allow-empty -m "Verify GitHub webhook trigger"
git push origin main
```

### 14.5. EC2 đầy disk: `no space left on device`

Đầu tiên tạm dừng trigger và đợi build kết thúc. Xác định filesystem nào đầy, kể cả inode:

```bash
df -hT
df -i
lsblk -f
docker info --format '{{.DockerRootDir}}'
docker system df -v
sudo du -xhd1 /var/lib /var/log /home 2>/dev/null
sudo journalctl --disk-usage
docker ps -a --size
```

DockerRootDir và image storage có thể khác theo cấu hình/version. Không mặc định mọi dữ liệu nằm ở `/var/lib/docker`; kiểm tra thêm `/var/lib/containerd` nếu hệ thống sử dụng image store tương ứng. Không xóa trực tiếp thư mục layer, containerd hoặc volume để “giải phóng nhanh”.

**Dọn có chọn lọc, sau khi xem dữ liệu sẽ mất:**

```bash
# Xóa cache build không sử dụng; sẽ phải build lại các layer tương ứng.
docker builder prune --filter 'until=168h'

# Chỉ image dangling, vẫn xem prompt trước khi đồng ý.
docker image prune

# Ví dụ giảm journal cũ nếu không cần giữ để điều tra.
sudo journalctl --vacuum-time=7d
```

- Giữ container `sample-ci-app-previous` và image rollback.
- Không dùng `docker container prune` vô tội vạ: nó có thể xóa previous đang stopped.
- Không dùng `docker system prune -a --volumes` hoặc `docker volume prune` khi chưa kiểm kê/backup: có thể mất dữ liệu cần giữ hoặc khả năng rollback.
- Build Discarder chỉ giới hạn lịch sử Jenkins, **không tự dọn Docker images/cache**.
- Với image runtime cũ, kiểm tra tag và container đang tham chiếu trước khi `docker image rm sample-ci-app:TAG_CU`.
- Nếu không đủ chỗ làm việc hoặc cần giữ dữ liệu, tăng EBS ở mục 15 thay vì xóa bừa.

### 14.6. Các lỗi khác thường gặp

| Lỗi | Cách xử lý |
|---|---|
| `docker: not found` trong Jenkins | Phải chạy image `jenkins-docker:lts` đã cài CLI, không image Jenkins nguyên bản |
| Buildx missing / broken | Kiểm tra `docker exec jenkins docker buildx version`, cài Buildx trong image và recreate |
| Docker client/server API mismatch | Đối chiếu `docker version`; cập nhật CLI/daemon có kế hoạch, không đặt API version ngẫu nhiên |
| `npm ci` yêu cầu lockfile | Sinh và commit `package-lock.json` bằng phiên bản Node/npm phù hợp |
| npm báo engine mismatch | Dùng Node 24 nhất quán local và Docker |
| Container exited / health unhealthy | `docker logs`, `docker inspect ...State.Health`, kiểm tra app bind `0.0.0.0` |
| Port 3000 already allocated | `docker ps`, `sudo ss -lntp`; xác định chủ sở hữu trước khi dừng process/container |
| App chạy nhưng ngoài máy không vào | Kiểm tra publish port, SG 3000 với IP cá nhân hiện tại, public IP và route |
| Không checkout private repo | Chọn Username/password PAT đúng repo và read permission; không dùng password GitHub |
| Jenkins quên jobs sau recreate | Kiểm tra đang mount cùng named volume `jenkins_home`, tránh đổi tên volume/project |
| Workspace bị root-owned | Tránh bind-run bằng root; lab dùng Docker build để không ghi root-owned file vào workspace |

## 15. Tăng dung lượng EBS

**Tình huống:** root volume 30 GiB đầy; cần tăng lên 60 GiB. Thực hiện trên đúng EC2/volume, không đoán device name. Các bước dưới dành cho phân vùng Linux thông thường; nếu `lsblk` cho thấy LVM, RAID hoặc LUKS, cần mở rộng các lớp tương ứng trước filesystem.

### 15.1. Snapshot và tăng volume trong AWS

1. Đợi build kết thúc và dừng các tác vụ ghi dữ liệu quan trọng nếu muốn backup nhất quán; cân nhắc dừng Jenkins trước snapshot.
2. EC2 → Instance → Storage: ghi lại EBS Volume ID của root disk.
3. EBS → Volumes → chọn đúng volume → Create snapshot, chờ snapshot sẵn sàng theo yêu cầu backup.
4. Actions → Modify volume → tăng Size, ví dụ 30 → 60 GiB → xác nhận.
5. Chờ modification ở trạng thái cho phép mở rộng, thường `optimizing` hoặc `completed`; kiểm tra OS đã thấy kích thước mới.

Tăng EBS không tự bảo đảm partition và filesystem đã tăng. Tham khảo [AWS: Extend filesystem after resizing](https://docs.aws.amazon.com/ebs/latest/userguide/recognize-expanded-volume-linux.html).

### 15.2. Xác định layout trên EC2

```bash
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS
findmnt -no SOURCE,FSTYPE /
df -hT /
```

Ví dụ disk `/dev/nvme0n1` đã là 60G nhưng partition root `/dev/nvme0n1p1` vẫn 30G, filesystem ext4. Thiết bị thật có thể khác, kể cả khi AWS console ghi `/dev/sda1`.

### 15.3. Mở rộng partition

```bash
sudo apt-get update
sudo apt-get install -y cloud-guest-utils

# CHỈ chạy nếu root partition thực sự là /dev/nvme0n1p1.
sudo growpart /dev/nvme0n1 1
```

Nếu layout thật là `/dev/xvda1`, dùng `sudo growpart /dev/xvda 1`. Có dấu cách giữa disk và partition number. Nếu filesystem nằm trực tiếp trên toàn disk, không có partition, bỏ qua growpart. `NOCHANGE` có thể là partition đã full disk hoặc OS chưa thấy disk lớn hơn; xem lại `lsblk`.

### 15.4. Mở rộng filesystem đúng loại

**Nếu ext4 trên `/dev/nvme0n1p1`:**

```bash
sudo resize2fs /dev/nvme0n1p1
```

**Nếu XFS và mountpoint là `/`:**

```bash
sudo xfs_growfs /
```

Chỉ chọn lệnh tương ứng filesystem thật, không chạy cả hai. Với device/mountpoint khác, thay chính xác. Không format, không `mkfs`, không xóa/tạo lại partition để mở rộng theo hướng dẫn này.

Nếu growpart báo không tạo được thư mục tạm vì disk đầy, giải phóng một ít log/cache đã xác định an toàn hoặc dùng vùng tạm khác đủ chỗ; sau đó chạy lại. Không cố ghi thêm log/build khi ổ đang hết dung lượng.

### 15.5. Xác nhận

```bash
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS
df -hT /
docker system df
```

Root filesystem phải hiển thị dung lượng tăng và có chỗ trống. Nếu Docker data ở EBS khác, mở rộng đúng volume/partition/mountpoint đó. Bật lại Jenkins/trigger nếu đã tạm dừng, rồi chạy một build kiểm tra.

## 16. Bảo mật và vận hành

### 16.1. Mức bảo mật của mô hình lab

Socket Docker cho phép job điều khiển host: kể cả Jenkins chạy user không-root, job vẫn có thể tạo container mount filesystem EC2. Chỉ dùng repo tin cậy, hạn chế quyền sửa Jenkinsfile, bật branch protection/review cho `main`. Không chạy pull request từ fork không tin cậy trên controller này.

Không dùng EC2 instance role quyền Administrator cho máy build. Mẫu không cần AWS credentials bên trong Jenkins để build/deploy trên chính EC2. Dùng IAM least privilege, IMDSv2 và hạn chế đường truy cập metadata từ workload theo thiết kế thực tế.

Không commit `.env`, `.pem`, PAT, password hoặc backup Jenkins vào repo. Credentials Jenkins được bảo vệ trong Jenkins home nhưng backup chứa cả dữ liệu nhạy cảm và khóa giải mã; cần hạn chế người đọc, mã hóa và quản lý quyền backup.

### 16.2. Nâng webhook lên HTTPS

Khi chuyển khỏi lab HTTP:

1. Chuẩn bị DNS trỏ tới endpoint ổn định và chứng chỉ TLS hợp lệ.
2. Dùng reverse proxy/ALB terminate TLS; forward tới Jenkins 8080 qua đường riêng phù hợp.
3. Nếu reverse proxy ở ngay host, đổi publish Jenkins thành `127.0.0.1:8080:8080`. Nếu proxy chạy container, dùng Docker network và upstream `jenkins:8080`, không dùng localhost của proxy container.
4. Chỉ public endpoint webhook cần thiết; quản trị qua VPN/tunnel hoặc đường truy cập đã kiểm soát. ALB khác máy cần rule 8080 chỉ từ SG của ALB, không bind loopback như proxy local.
5. Đổi Payload URL thành `https://TEN_MIEN/github-webhook/`, giữ SSL verification bật.
6. Cấu hình cùng webhook secret ở GitHub và tính năng xác minh secret của phiên bản GitHub plugin đang cài hoặc gateway có xác minh chữ ký. Tên trường UI tùy phiên bản; không giả định chỉ nhập Secret ở GitHub là Jenkins đã kiểm tra.
7. Kiểm thử secret đúng được nhận và secret sai bị từ chối, kiểm tra log, sau đó khôi phục secret đúng.
8. Gỡ rule public 8080 không còn cần; cập nhật IP allowlist theo GitHub Meta API.

HTTPS bảo vệ nội dung trên đường truyền; secret/signature giúp xác minh nguồn request. Hai chức năng khác nhau. Xem [GitHub webhook best practices](https://docs.github.com/en/webhooks/using-webhooks/best-practices-for-using-webhooks).

### 16.3. Backup Jenkins cơ bản

Persistent volume không thay thế backup. Ví dụ sao lưu nhất quán khi **không có build đang chạy**, trên EC2:

```bash
mkdir -p ~/jenkins-backups
chmod 700 ~/jenkins-backups
docker stop jenkins
docker run --rm \
  -v jenkins_home:/data:ro \
  -v "$HOME/jenkins-backups:/backup" \
  alpine:3 sh -c 'tar czf /backup/jenkins-home.tgz -C /data .'
docker start jenkins
sudo chown "$(id -u):$(id -g)" ~/jenkins-backups/jenkins-home.tgz
chmod 600 ~/jenkins-backups/jenkins-home.tgz
```

Tên backup trên sẽ ghi đè bản cũ; đổi tên theo ngày trước khi sử dụng định kỳ. Kiểm tra exit code và kích thước backup, đưa bản sao mã hóa ra ngoài EC2, thử restore ở môi trường tách biệt. Sao lưu cả `~/jenkins-lab` để giữ Dockerfile/Compose. Nếu lệnh backup thất bại, vẫn khởi động lại Jenkins và xử lý nguyên nhân.

**Hướng nâng cấp sau lab:** controller riêng, agent build riêng, registry (ECR/GHCR), image scan, pin digest, quản lý secrets, giới hạn resource, HTTPS cho ứng dụng, deploy có kiểm soát và giám sát. Không cần triển khai toàn bộ các thành phần này để hoàn thành bài lab hiện tại.

## 17. Checklist hoàn thành và dọn lab

### 17.1. Nghiệm thu

- [ ] EC2 có Docker Engine; Jenkins là container với volume `jenkins_home`.
- [ ] Docker CLI + Buildx hoạt động bên trong Jenkins, không lỗi socket permission.
- [ ] Source có đầy đủ app, manifest, lockfile, test, Dockerfile, `.dockerignore`, Jenkinsfile.
- [ ] Repo private checkout bằng credential chỉ đọc nếu dùng private repo.
- [ ] Build thủ công đầu tiên chạy xanh.
- [ ] Push commit mới lên `main` tự tạo build, không bấm Build Now.
- [ ] GitHub Recent Deliveries ghi nhận push endpoint nhận thành công.
- [ ] Các stage Checkout → Install → Test → Build → Deploy hoàn tất.
- [ ] App trả version mới từ máy cá nhân và `/health` trả ok.
- [ ] Commit làm test sai không thay image đang chạy; sau đó đã revert test sai.
- [ ] Đã có ít nhất hai lần deploy thành công và thực hành rollback.
- [ ] Hiểu cách xem disk/inodes, dọn cache có chọn lọc và tăng EBS.
- [ ] Không còn secrets trong Git hoặc cổng quản trị mở cho mọi IP.

**Bằng chứng nên lưu khi nộp bài:** SHA commit, build number/image tag, ảnh hoặc log stage thành công, push delivery status, kết quả curl, trạng thái container và kết quả bài test fail. Che tokens/password và dữ liệu nhạy cảm trước khi chia sẻ.

### 17.2. Bộ lệnh kiểm tra nhanh — chạy trên EC2

```bash
docker ps -a
docker logs --tail 100 jenkins
docker exec jenkins docker version
docker logs --tail 100 sample-ci-app
docker inspect --format '{{.Config.Image}} {{.State.Health.Status}}' sample-ci-app
curl -fsS http://127.0.0.1:3000/health
df -hT
df -i
free -h
docker system df
lsblk -f
```

### 17.3. Dọn sau khi học

1. Disable/xóa GitHub webhook và thu hồi token chỉ dùng cho lab.
2. Lưu source trên GitHub, sao lưu Jenkins nếu cần.
3. Nếu chỉ tạm dừng, stop EC2 hoặc stop containers; EBS và các tài nguyên giữ lại vẫn có thể phát sinh phí.
4. Nếu kết thúc hoàn toàn, terminate EC2 sau khi kiểm tra backup và chính sách Delete on termination của volume.
5. Kiểm tra và xóa riêng các EBS, snapshots, Elastic IP và tài nguyên lab còn lại nếu không cần; kiểm tra AWS Billing.

Không chạy `docker compose down -v` trừ khi chủ động xóa toàn bộ dữ liệu Jenkins của lab. Thao tác này khác với dừng container thông thường.

## 18. Tài liệu tham khảo

Các nguồn chính thức được đối chiếu khi biên soạn; giao diện và phiên bản có thể thay đổi:

- [Docker Engine — Ubuntu installation](https://docs.docker.com/engine/install/ubuntu/)
- [Jenkins — Installing with Docker](https://www.jenkins.io/doc/book/installing/docker/)
- [Jenkins — Pipeline syntax](https://www.jenkins.io/doc/book/pipeline/syntax/)
- [Jenkins — GitHub plugin](https://plugins.jenkins.io/github/)
- [Jenkins — Git plugin](https://plugins.jenkins.io/git/)
- [GitHub — Testing webhooks](https://docs.github.com/en/webhooks/testing-and-troubleshooting-webhooks/testing-webhooks)
- [GitHub — Webhook best practices](https://docs.github.com/en/webhooks/using-webhooks/best-practices-for-using-webhooks)
- [GitHub — IP addresses](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/about-githubs-ip-addresses)
- [GitHub — Managing personal access tokens](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens)
- [AWS — Extending filesystem after EBS resizing](https://docs.aws.amazon.com/ebs/latest/userguide/recognize-expanded-volume-linux.html)
- [Node.js — Release schedule](https://github.com/nodejs/Release)

---

**Yên Nguyễn All Rights Reserved.**
