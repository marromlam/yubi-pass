# Yubi Pass Safari Extension

This Safari extension provides TOTP (Time-based One-Time Password) functionality for web forms.

## Features

- **Context Menu Integration**: Right-click on any input field and select "Generate OTP" to generate a TOTP code
- **TOTP Code Management**: Add, remove, and manage TOTP codes for different domains
- **Automatic Form Filling**: Automatically fills the selected input field with the generated OTP
- **Domain-based Code Mapping**: Associate TOTP codes with specific websites

## How to Use

1. **Install the Extension**: Load the extension in Safari's Develop menu
2. **Configure TOTP Codes**: 
   - Click the extension icon in the toolbar
   - Click "Manage Codes" to open the options page
   - Add your TOTP codes with domain mappings
3. **Generate OTP**: 
   - Navigate to a website with a login form
   - Right-click on the password/OTP input field
   - Select "Generate OTP" from the context menu
   - The OTP will be automatically filled into the field

## Configuration

### Adding TOTP Codes

1. Open the extension options page
2. Enter the domain (e.g., `example.com`)
3. Enter a name for your TOTP code
4. Click "Add TOTP Code"

### Domain Mapping

The extension automatically maps domains to TOTP codes. For example:
- If you're on `https://example.com/login`, it will look for a TOTP code mapped to `example.com`
- The domain should match the hostname of the website

## Technical Notes

- **Current Implementation**: This version generates placeholder OTP codes for demonstration
- **Native Integration**: Full integration with YubiKey requires additional setup for native messaging
- **Safari Compatibility**: Uses Safari's context menu and scripting APIs

## Future Enhancements

- Integration with actual TOTP generation libraries
- Native app communication for YubiKey integration
- Enhanced security features
- Backup and sync capabilities

## Troubleshooting

- **Context menu not appearing**: Make sure you're right-clicking on an input field
- **OTP not filling**: Check that the field is focused and editable
- **Codes not saving**: Verify the extension has storage permissions
