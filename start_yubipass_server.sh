#!/bin/bash

echo "Starting YubiPass HTTP Server..."
echo "This server will handle OTP generation requests from the Safari extension."
echo ""

# Check if Python 3 is available
if ! command -v python3 &> /dev/null; then
    echo "Error: Python 3 is not installed or not in PATH"
    exit 1
fi

# Check if the YubiPass HTTP script exists
if [ ! -f "app/yubi_pass_http.py" ]; then
    echo "Error: yubi_pass_http.py not found in app/ directory"
    exit 1
fi

# Make the script executable
chmod +x app/yubi_pass_http.py

# Check if ykman is available
if ! command -v ykman &> /dev/null; then
    echo "Warning: ykman command not found. Make sure YubiKey Manager is installed."
    echo "You can install it with: brew install yubikey-manager"
    echo ""
fi

echo "Starting server on http://localhost:8080"
echo "Press Ctrl+C to stop the server"
echo ""

# Start the server
cd app && python3 yubi_pass_http.py
