#!/usr/bin/env python3

import struct
import os
import json
import sys


# TODO: Change this path to your ykman config file
CONFIG_FILE = "/Users/marcos/.config/ykman/config.json"
KEYMAP = {}
if os.path.exists(CONFIG_FILE):
    KEYMAP = json.load(open(CONFIG_FILE, "r"))
YKMAN_PATH = os.environ.get("YKMAN_PATH", "ykman")


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
    result = run(f'{YKMAN_PATH} oath accounts code "{key}"')
    return result.strip().split(" ")[-1]


def handleGenerateOtpMessage(receivedMessage):
    key = KEYMAP.get(receivedMessage["pageUrl"])
    responseMessage = {
        "type": "otpResponse",
        "target": receivedMessage["target"],
        "otp": getOtpCode(key) if key else "NOTFOUND",
    }
    sendMessage(encodeMessage(responseMessage))


def run(command: str) -> str:
    return os.popen(command).read()


while True:
    receivedMessage = getMessage()
    isGenerateOtp = receivedMessage.get("type") == "generateOtp"
    if isGenerateOtp:
        handleGenerateOtpMessage(receivedMessage)
