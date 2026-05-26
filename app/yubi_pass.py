#!/usr/bin/env python3

import struct
import os
import json
import sys

CONFIG_FILE = os.path.expanduser("~/.config/ykman/config.json")
CONFIG = {}
if os.path.exists(CONFIG_FILE):
    with open(CONFIG_FILE, "r") as f:
        CONFIG = json.load(f)

KEYMAP = CONFIG.get("key_mapping", {})
# Resolve ykman: prefer config value, then common Homebrew path, then PATH
_default_ykman = "/opt/homebrew/bin/ykman" if os.path.isfile("/opt/homebrew/bin/ykman") else "ykman"
YKMAN_BIN = CONFIG.get("bin", _default_ykman)


def getMessage():
    rawLength = sys.stdin.buffer.read(4)
    if len(rawLength) == 0:
        sys.exit(0)
    messageLength = struct.unpack("@I", rawLength)[0]
    message = sys.stdin.buffer.read(messageLength).decode("utf-8")
    return json.loads(message)


def encodeMessage(messageContent):
    encodedContent = json.dumps(messageContent).encode("utf-8")
    encodedLength = struct.pack("@I", len(encodedContent))
    return {"length": encodedLength, "content": encodedContent}


def sendMessage(encodedMessage):
    sys.stdout.buffer.write(encodedMessage["length"])
    sys.stdout.buffer.write(encodedMessage["content"])
    sys.stdout.buffer.flush()


def getOtpCode(key):
    result = run(f'{YKMAN_BIN} oath accounts code "{key}"')
    return result.strip().split(" ")[-1]


def handleGenerateOtpMessage(receivedMessage):
    key = receivedMessage.get("keyName") or None
    if not key:
        page_url = receivedMessage.get("pageUrl")
        key = KEYMAP.get(page_url) if page_url else None
    responseMessage = {
        "type": "otpResponse",
        "target": receivedMessage["target"],
        "otp": getOtpCode(key) if key else "NOT_FOUND",
    }
    sendMessage(encodeMessage(responseMessage))


def run(command: str) -> str:
    return os.popen(command).read()


while True:
    receivedMessage = getMessage()
    isGenerateOtp = receivedMessage.get("type") == "generateOtp"
    if isGenerateOtp:
        handleGenerateOtpMessage(receivedMessage)
