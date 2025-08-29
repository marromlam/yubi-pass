#!/usr/bin/env python3

import json
import os
import subprocess
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
import threading
import time

# Configuration
CONFIG_FILE = "/Users/marcos/.config/ykman/config.json"
CONFIG = {}
if os.path.exists(CONFIG_FILE):
    CONFIG = json.load(open(CONFIG_FILE, "r"))

KEYMAP = CONFIG.get("key_mapping", {})
YKMAN_BIN = CONFIG.get("bin", "/opt/homebrew/bin/ykman")

class YubiPassHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        """Handle GET requests for OTP generation"""
        try:
            # Parse URL and query parameters
            parsed_url = urlparse(self.path)
            query_params = parse_qs(parsed_url.query)
            
            # Get parameters
            key_name = query_params.get('key', [None])[0]
            domain = query_params.get('domain', [None])[0]
            
            # Generate OTP
            otp = self.generate_otp(key_name, domain)
            
            # Send response
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
            self.send_header('Access-Control-Allow-Headers', 'Content-Type')
            self.end_headers()
            
            response = {
                "success": True,
                "otp": otp,
                "key_name": key_name,
                "domain": domain
            }
            
            self.wfile.write(json.dumps(response).encode())
            
        except Exception as e:
            self.send_error(500, str(e))
    
    def do_OPTIONS(self):
        """Handle CORS preflight requests"""
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()
    
    def generate_otp(self, key_name, domain):
        """Generate OTP using ykman"""
        try:
            # Try key_name first, then fall back to domain mapping
            key = key_name
            if not key and domain:
                key = KEYMAP.get(domain)
            
            if not key:
                return "NO_KEY_FOUND"
            
            # Run ykman command
            result = subprocess.run(
                [YKMAN_BIN, 'oath', 'accounts', 'code', key],
                capture_output=True,
                text=True,
                timeout=10
            )
            print(result)
            
            if result.returncode == 0:
                # Extract the OTP code from the output
                output = result.stdout.strip()
                # ykman output format: "123456 (expires in 23s)"
                otp = output.split(" ")[-1]
                return otp
            else:
                print(f"ykman error: {result.stderr}")
                return "YKMAN_ERROR"
                
        except subprocess.TimeoutExpired:
            return "TIMEOUT"
        except Exception as e:
            print(f"Error generating OTP: {e}")
            return "ERROR"
    
    def log_message(self, format, *args):
        """Custom logging to avoid cluttering console"""
        print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {format % args}")

def run_server(port=8080):
    """Run the HTTP server"""
    server_address = ('localhost', port)
    httpd = HTTPServer(server_address, YubiPassHandler)
    print(f"YubiPass HTTP server running on http://localhost:{port}")
    print(f"YKMAN binary: {YKMAN_BIN}")
    print(f"Key mappings: {KEYMAP}")
    print("Press Ctrl+C to stop the server")
    
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down server...")
        httpd.shutdown()

if __name__ == "__main__":
    run_server()
