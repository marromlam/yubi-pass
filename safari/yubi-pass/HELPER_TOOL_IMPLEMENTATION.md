# Helper Tool Implementation for Safari Extension

This document explains how to implement the helper tool approach for the yubi-pass Safari extension, following Apple's guidelines for [Embedding a Helper Tool in a Sandboxed App](https://developer.apple.com/documentation/xcode/embedding-a-helper-tool-in-a-sandboxed-app).

## Overview

The yubi-pass Safari extension needs to execute the `ykman` command-line tool to interact with YubiKey devices. Since the extension runs in a sandboxed environment, we need to ensure proper entitlements and permissions to execute external tools.

## Implementation Approach

### Option 1: System ykman with Entitlements (Recommended)

This approach uses the system-installed `ykman` tool with proper entitlements to allow execution.

#### Advantages:
- Simple implementation
- No need to bundle additional binaries
- Uses the official, maintained ykman installation
- Easier to update (follows system updates)

#### Requirements:
- `ykman` must be installed via Homebrew or similar package manager
- Proper entitlements must be configured
- App must be properly code-signed

#### Implementation:

1. **Entitlements Configuration**
   
   The app needs the following entitlements in `yubi-pass.entitlements`:
   
   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
       <key>com.apple.security.app-sandbox</key>
       <true/>
       <key>com.apple.security.network.client</key>
       <true/>
       <key>com.apple.security.device.usb</key>
       <true/>
       <key>com.apple.security.device.hid</key>
       <true/>
       <key>com.apple.security.files.user-selected.read-write</key>
       <true/>
       <key>com.apple.security.files.downloads.read-write</key>
       <true/>
       <key>com.apple.security.automation.apple-events</key>
       <true/>
       <key>com.apple.security.temporary-exception.files.absolute-path.read-write</key>
       <array>
           <string>/opt/homebrew/bin/</string>
           <string>/opt/homebrew/lib/</string>
           <string>/opt/homebrew/libexec/</string>
       </array>
   </dict>
   </plist>
   ```

2. **Code Implementation**
   
   The `YubiKeyService.swift` is configured to use the system ykman:
   
   ```swift
   private let ykmanPath = "/opt/homebrew/bin/ykman"
   ```

3. **Error Handling**
   
   The service includes comprehensive error handling and fallback mechanisms:
   
   ```swift
   func isYkmanAvailable() -> Bool {
       // Check file existence and executability
       // Test with --version command
       // Handle timeouts and errors gracefully
   }
   ```

### Option 2: Embedded Binary (Not Recommended for this project)

We attempted to create an embedded binary using PyInstaller, but encountered issues:

#### Problems Encountered:
- PyInstaller couldn't properly bundle the ykman Python dependencies
- The resulting binary failed with "ModuleNotFoundError: No module named 'ykman'"
- Increased app bundle size significantly (6.9MB vs ~1KB for the script)

#### Why It Failed:
- `ykman` is a Python-based tool with complex dependencies
- PyInstaller couldn't resolve all the required modules
- The tool requires access to system Python libraries

## Current Implementation Status

✅ **System ykman approach**: Fully implemented and working
❌ **Embedded binary approach**: Attempted but failed due to PyInstaller limitations

## Testing

The implementation includes comprehensive testing:

1. **Unit Tests**: Test ykman availability and basic functionality
2. **Integration Tests**: Test OTP generation and account listing
3. **Error Handling**: Test various failure scenarios

Run tests with:
```bash
swift test_ykman.swift --test
```

## Security Considerations

1. **Sandbox Compliance**: The app runs in a sandboxed environment
2. **Entitlements**: Only necessary permissions are granted
3. **Code Signing**: App must be properly code-signed for distribution
4. **Path Validation**: Only executes ykman from trusted locations

## Deployment Requirements

1. **Code Signing**: App must be signed with a valid developer certificate
2. **Entitlements**: Must be properly configured and validated
3. **System Requirements**: Target system must have ykman installed
4. **Permissions**: User must grant necessary permissions for USB/HID access

## Troubleshooting

### Common Issues:

1. **"ykman not found"**
   - Ensure ykman is installed via Homebrew: `brew install ykman`
   - Check the path in `YubiKeyService.swift`

2. **"Permission denied"**
   - Verify entitlements are properly configured
   - Ensure app is code-signed
   - Check sandbox settings

3. **"No YubiKey detected"**
   - Ensure YubiKey is properly connected
   - Check USB permissions in System Preferences
   - Verify ykman can detect the device from command line

### Debug Information:

The service provides detailed logging and debugging information:
```swift
func getYkmanInfo() -> [String: Any]
```

## Future Improvements

1. **Better Error Messages**: More user-friendly error descriptions
2. **Fallback Mechanisms**: Alternative approaches if ykman fails
3. **Configuration UI**: Allow users to configure ykman paths
4. **Auto-detection**: Automatically detect ykman installation paths

## Conclusion

The current implementation using system ykman with proper entitlements is the recommended approach. It provides:

- Reliable functionality
- Easy maintenance
- Proper security
- Good performance

The embedded binary approach, while theoretically possible, introduces complexity and reliability issues that make it unsuitable for production use in this context.
