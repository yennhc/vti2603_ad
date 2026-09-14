Được. Với Dockerfile của bạn, có thể tạo một ứng dụng Python HTTP server đơn giản chạy trên port 8000, phù hợp để thực hành Docker image layers, COPY, RUN, ENV, EXPOSE và CMD.

app.py

import os
from http.server import BaseHTTPRequestHandler, HTTPServer
APP_ENV = os.getenv("APP_ENV", "development")
HOST = "0.0.0.0"
PORT = 8000
class RequestHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        response = f"""
        <!DOCTYPE html>
        <html>
        <head>
            <title>Docker Layer Lab</title>
        </head>
        <body>
            <h1>Docker Layer Lab</h1>
            <p>Application is running successfully!</p>
            <p><strong>Environment:</strong> {APP_ENV}</p>
            <p><strong>Python:</strong> 3.11</p>
            <p><strong>Port:</strong> {PORT}</p>
        </body>
        </html>
        """
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(response.encode())))
        self.end_headers()
        self.wfile.write(response.encode())
    def log_message(self, format, *args):
        print(f"[HTTP] {self.address_string()} - {format % args}")
if __name__ == "__main__":
    server = HTTPServer((HOST, PORT), RequestHandler)
    print("=" * 50)
    print("Docker Layer Lab")
    print(f"Environment : {APP_ENV}")
    print(f"Server      : http://{HOST}:{PORT}")
    print("=" * 50)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nServer stopped.")
    finally:
        server.server_close()

requirements.txt

Vì app.py chỉ sử dụng Python Standard Library (http.server, os), không cần cài thêm package nào.

Do Dockerfile của bạn vẫn có:

RUN pip install --no-cache-dir -r requirements.txt

nên requirements.txt có thể để một comment:

# No external Python dependencies required.
# This application uses Python Standard Library only.

Tạo trực tiếp bằng command

Bạn có thể copy/paste nguyên block này:

mkdir -p ~/docker-layer-lab
cd ~/docker-layer-lab
cat > app.py <<'EOF'
import os
from http.server import BaseHTTPRequestHandler, HTTPServer
APP_ENV = os.getenv("APP_ENV", "development")
HOST = "0.0.0.0"
PORT = 8000
class RequestHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        response = f"""
        <!DOCTYPE html>
        <html>
        <head>
            <title>Docker Layer Lab</title>
        </head>
        <body>
            <h1>Docker Layer Lab</h1>
            <p>Application is running successfully!</p>
            <p><strong>Environment:</strong> {APP_ENV}</p>
            <p><strong>Python:</strong> 3.11</p>
            <p><strong>Port:</strong> {PORT}</p>
        </body>
        </html>
        """
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(response.encode())))
        self.end_headers()
        self.wfile.write(response.encode())
    def log_message(self, format, *args):
        print(f"[HTTP] {self.address_string()} - {format % args}")
if __name__ == "__main__":
    server = HTTPServer((HOST, PORT), RequestHandler)
    print("=" * 50)
    print("Docker Layer Lab")
    print(f"Environment : {APP_ENV}")
    print(f"Server      : http://{HOST}:{PORT}")
    print("=" * 50)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nServer stopped.")
    finally:
        server.server_close()
EOF
cat > requirements.txt <<'EOF'
# No external Python dependencies required.
# This application uses Python Standard Library only.
EOF

Sau đó kiểm tra:

cd ~/docker-layer-lab
ls -l
cat app.py
cat requirements.txt

Thư mục cuối cùng sẽ là:

docker-layer-lab/
├── Dockerfile
├── app.py
└── requirements.txt

Và bạn có thể build/test:

docker build -t docker-layer-lab:1.0 .
docker run -d \
  --name docker-layer-lab \
  -p 8000:8000 \
  docker-layer-lab:1.0

Test:

curl http://localhost:8000

Hoặc mở:

http://localhost:8000

Điểm hay cho bài thực hành Docker Layer: requirements.txt cố ý không có dependency bên ngoài, nhưng RUN pip install... vẫn tạo một layer. Như vậy sinh viên có thể quan sát rõ layer được tạo bởi từng instruction trong Dockerfile.