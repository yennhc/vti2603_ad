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