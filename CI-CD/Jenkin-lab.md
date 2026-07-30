## LAB CI với Jenkins bằng Docker

Mục tiêu: cài Jenkins bằng Docker, sau đó tạo pipeline tự động build và deploy một ứng dụng web Node.js.

### 1. Chuẩn bị

Cài sẵn:

- Docker Desktop
- Git
- Trình duyệt web

Tạo cấu trúc thư mục:

```text
jenkins-ci-lab/
├── docker-compose.yml
└── sample-app/
    ├── app.js
    ├── package.json
    ├── Dockerfile
    └── Jenkinsfile
```

---

### 2. Cài Jenkins bằng Docker

Tạo file `docker-compose.yml`:

```yaml
services:
  jenkins:
    image: jenkins/jenkins:lts-jdk17
    container_name: jenkins
    user: root
    ports:
      - "8080:8080"
      - "50000:50000"
    volumes:
      - jenkins_home:/var/jenkins_home
      - /var/run/docker.sock:/var/run/docker.sock
    restart: unless-stopped

volumes:
  jenkins_home:
```

Khởi động Jenkins:

```bash
docker compose up -d
```

Lấy mật khẩu khởi tạo:

```bash
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

Mở Jenkins tại: `http://localhost:8080`

Thực hiện các bước trên giao diện:

1. Dán mật khẩu khởi tạo.
2. Chọn **Install suggested plugins**.
3. Tạo tài khoản quản trị.
4. Vào **Manage Jenkins → Plugins** và đảm bảo đã có plugin:
   - Pipeline
   - Git
   - Docker Pipeline

Cài Docker CLI trong container Jenkins:

```bash
docker exec -u root jenkins bash -c "apt-get update && apt-get install -y docker.io"
```

---

### 3. Tạo ứng dụng mẫu

Tạo `sample-app/package.json`:

```json
{
  "name": "sample-ci-app",
  "version": "1.0.0",
  "scripts": {
    "start": "node app.js",
    "test": "node -e \"console.log('Tests passed')\""
  },
  "dependencies": {
    "express": "^4.18.2"
  }
}
```

Tạo `sample-app/app.js`:

```js
const express = require("express");

const app = express();
const port = process.env.PORT || 3000;

app.get("/", (req, res) => {
  res.send("CI/CD deployment successful!");
});

app.listen(port, () => {
  console.log(`Application running at port ${port}`);
});
```

Tạo `sample-app/Dockerfile`:

```dockerfile
FROM node:20-alpine

WORKDIR /app

COPY package*.json ./
RUN npm install --omit=dev

COPY . .

EXPOSE 3000

CMD ["npm", "start"]
```

---

### 4. Tạo Jenkins Pipeline

Tạo file `sample-app/Jenkinsfile`:

```groovy
pipeline {
    agent any

    environment {
        IMAGE_NAME = "sample-ci-app"
        CONTAINER_NAME = "sample-ci-app"
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Install dependencies') {
            steps {
                sh 'docker run --rm -v "$WORKSPACE":/app -w /app node:20-alpine npm install'
            }
        }

        stage('Test') {
            steps {
                sh 'docker run --rm -v "$WORKSPACE":/app -w /app node:20-alpine npm test'
            }
        }

        stage('Build Docker image') {
            steps {
                sh 'docker build -t $IMAGE_NAME:$BUILD_NUMBER .'
            }
        }

        stage('Deploy') {
            steps {
                sh '''
                    docker rm -f $CONTAINER_NAME || true
                    docker run -d \
                      --name $CONTAINER_NAME \
                      -p 3000:3000 \
                      --restart unless-stopped \
                      $IMAGE_NAME:$BUILD_NUMBER
                '''
            }
        }
    }

    post {
        success {
            echo 'Build and deployment completed successfully.'
        }
        failure {
            echo 'Pipeline failed. Review the console output.'
        }
    }
}
```

---

### 5. Đưa mã nguồn lên Git

Trong thư mục `sample-app`:

```bash
git init
git add .
git commit -m "Initial CI application"
```

Tạo một repository GitHub/GitLab, sau đó:

```bash
git branch -M main
git remote add origin <repository-url>
git push -u origin main
```

---

### 6. Tạo Jenkins Job

1. Chọn **New Item**.
2. Nhập tên: `sample-ci-pipeline`.
3. Chọn **Pipeline**.
4. Ở mục **Pipeline**, chọn **Pipeline script from SCM**.
5. SCM: **Git**.
6. Nhập URL repository.
7. Branch: `*/main`.
8. Script Path: `Jenkinsfile`.
9. Chọn **Save** → **Build Now**.

Sau khi pipeline chạy thành công, truy cập:

```text
http://localhost:3000
```

Kết quả mong đợi:

```text
CI/CD deployment successful!
```

---

### Luồng CI/CD đã tạo

```text
Git push
  → Jenkins lấy mã nguồn
  → cài dependencies
  → chạy test
  → build Docker image
  → xóa container phiên bản cũ
  → chạy container phiên bản mới
```

Bài mở rộng: cấu hình webhook từ GitHub/GitLab để Jenkins tự chạy pipeline mỗi khi có `git push`, thay vì bấm **Build Now** thủ công.