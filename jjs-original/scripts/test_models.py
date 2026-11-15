#!/usr/bin/env python3
import http.server
import os
import pathlib
import subprocess
import tempfile
import threading

root = pathlib.Path(__file__).resolve().parents[1]
os.chdir(root)
pathlib.Path("build/tests").mkdir(parents=True, exist_ok=True)
subprocess.run([
    "swiftc", "-swift-version", "5", "Sources/CoreTypes.swift",
    "Sources/ModelRepository.swift", "Tests/ModelRepositoryTests.swift",
    "-o", "build/tests/ModelRepositoryTests",
], check=True)

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/model.gguf":
            body, code = b"GGUF" + bytes([42]) * 8192, 200
        elif self.path == "/bad.gguf":
            body, code = b"<html>not a model</html>", 200
        else:
            body, code = b"not found", 404
        self.send_response(code)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass

server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
try:
    subprocess.run(["build/tests/ModelRepositoryTests"], check=True, env={
        **os.environ, "JJS_TEST_SERVER": f"http://127.0.0.1:{server.server_port}",
    })
finally:
    server.shutdown()
    server.server_close()
