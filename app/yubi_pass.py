#!/usr/bin/env python3

import struct
import os
import json
import sys


# TODO: Change this path to your ykman config file
CONFIG_FILE = "/Users/marcos/.config/ykman/config.json"
CONFIG = {}
if os.path.exists(CONFIG_FILE):
    CONFIG = json.load(open(CONFIG_FILE, "r"))

KEYMAP = CONFIG.get("key_mapping", None)
YKMAN_BIN = CONFIG.get("bin", "ykman")
YKMAN_BIN = "/opt/homebrew/bin/ykman"


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
    key = receivedMessage.get("keyName", None)
    if not key:
        key = KEYMAP.get(receivedMessage.get("pageUrl", None), None)
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
