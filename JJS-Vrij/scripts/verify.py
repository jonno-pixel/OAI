#!/usr/bin/env python3
import http.server
import os
from pathlib import Path
import subprocess
import threading

root = Path(__file__).resolve().parents[1]
os.chdir(root)
Path('build').mkdir(exist_ok=True)
subprocess.run(['swiftc', '-swift-version', '5', 'Sources/Domain.swift',
                'Sources/LibraryVault.swift', 'Sources/ModelFiles.swift',
                'Tests/Verification.swift', '-o', 'build/Verification'], check=True)

class FixtureServer(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        code = 200
        if self.path == '/valid.gguf':
            body = b'GGUF' + bytes([73]) * 4096
        elif self.path == '/html.gguf':
            body = b'<html>not a GGUF model</html>'
        else:
            code, body = 404, b'not found'
        self.send_response(code)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *_):
        pass

server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), FixtureServer)
threading.Thread(target=server.serve_forever, daemon=True).start()
try:
    subprocess.run(['build/Verification'], check=True, env={
        **os.environ, 'VRIJ_TEST_SERVER': f'http://127.0.0.1:{server.server_port}'})
finally:
    server.shutdown()
    server.server_close()
