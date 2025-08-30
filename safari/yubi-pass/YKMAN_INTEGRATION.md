# YubiKey Manager (ykman) Integration

This Safari app now uses `ykman` to generate real OTP codes from your YubiKey instead of placeholder codes.

## Prerequisites

1. **YubiKey**: A YubiKey with OATH-TOTP accounts configured
2. **ykman**: YubiKey Manager command-line tool installed

## Installation

### Install ykman

```bash
# Using Homebrew (recommended)
brew install yubikey-manager

# Or download from Yubico's website
# https://developers.yubico.com/yubikey-manager/
```

### Verify Installation

Run the test script to verify everything is working:

```bash
cd safari/yubi-pass
swift test_ykman.swift
```

You should see output like:
```
✓ ykman found at: /opt/homebrew/bin/ykman
✓ ykman version: 5.2.1
✓ Found 3 OATH accounts:
  - github.com
  - google.com
  - microsoft.com
✓ Generated OTP: 123456
```

## How It Works

1. **Safari Extension**: When you right-click in a password field and select "Generate OTP", the extension sends a request to the main app
2. **Main App**: The main app receives the request and uses `ykman` to generate a real OTP from your YubiKey
3. **Domain Mapping**: The app intelligently maps website domains to YubiKey account names
4. **OTP Injection**: The generated OTP is automatically inserted into the focused password field

## Domain Mapping

The app uses intelligent domain mapping to find the right YubiKey account:

1. **Exact Match**: If you have an account named exactly "github.com", it will use that
2. **Partial Match**: If you have an account named "GitHub" and visit "github.com", it will match them
3. **Pattern Matching**: Common patterns like "github.com" → "GitHub", "google.com" → "Google"
4. **Fuzzy Matching**: Word-based matching for complex domain names
5. **Fallback**: If no match is found, uses the first available account

## Troubleshooting

### ykman Not Found

If you get an error that `ykman` is not found:

1. Verify `ykman` is installed: `which ykman`
2. Check if it's in your PATH: `echo $PATH`
3. Try installing with Homebrew: `brew install yubikey-manager`

### No OATH Accounts Found

If no OATH accounts are found:

1. Make sure your YubiKey is connected
2. Verify you have OATH-TOTP accounts configured
3. Check if `ykman oath accounts list` works from terminal

### Permission Denied

If you get permission errors:

1. Make sure the app has the necessary entitlements
2. Check if the YubiKey is accessible (not locked by another app)
3. Try running `ykman oath accounts list` from terminal first

### OTP Generation Fails

If OTP generation fails:

1. Check the app's console output for error messages
2. Verify the account name exists on your YubiKey
3. Try generating the OTP manually: `ykman oath accounts code ACCOUNT_NAME`

## Security Notes

- The app only executes `ykman` commands, never stores your OTP secrets
- All communication between extension and main app uses App Groups (sandboxed)
- The app requires explicit entitlements to execute external processes
- OTP codes are generated on-demand and not cached

## Development

To modify the domain mapping logic, edit the `findAccountForDomain` function in `AppDelegate.swift`.

To add new domain patterns, update the `commonPatterns` dictionary in the same function.

## Testing

The test script (`test_ykman.swift`) can be used to verify:
- ykman installation and version
- YubiKey connectivity
- Account listing
- OTP generation

Run it whenever you encounter issues or want to verify the setup.
