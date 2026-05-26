//
//  ShareViewController_iOS.swift
//  YubiPass Share Extension
//
//  Share extension for iOS/iPadOS to inject OTP
//

#if os(iOS)
import UIKit
import Social
import YubiKit

@available(iOS 15.0, *)
class ShareViewController_iOS: UIViewController {
    
    var hostURL: String?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Get the URL being shared
        extractURL()
        
        // Show OTP generation UI
        showOTPGenerator()
    }
    
    func extractURL() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let itemProvider = extensionItem.attachments?.first else {
            return
        }
        
        // Try to get URL from shared content
        if itemProvider.hasItemConformingToTypeIdentifier("public.url") {
            itemProvider.loadItem(forTypeIdentifier: "public.url", options: nil) { [weak self] (url, error) in
                if let shareURL = url as? URL {
                    self?.hostURL = shareURL.host
                }
            }
        }
    }
    
    func showOTPGenerator() {
        let alertController = UIAlertController(
            title: "Generate OTP",
            message: hostURL != nil ? "For: \(hostURL!)" : "Select account",
            preferredStyle: .actionSheet
        )
        
        // Check if YubiKey is connected
        guard let connection = YubiKitManager.shared.accessoryConnection,
              connection.isConnected else {
            showError("YubiKey not connected. Please plug in your YubiKey 5C via USB-C.")
            return
        }
        
        // Load accounts from YubiKey
        Task {
            do {
                let session = try await YKFOATHSession(connection: connection)
                let credentials = try await session.listCredentials()
                let accounts = credentials.map { $0.key }
                
                await MainActor.run {
                    for account in accounts {
                        let action = UIAlertAction(title: account, style: .default) { [weak self] _ in
                            self?.generateAndCopyOTP(for: account, connection: connection)
                        }
                        alertController.addAction(action)
                    }
                    
                    alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
                        self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
                    })
                    
                    self.present(alertController, animated: true)
                }
            } catch {
                showError("Failed to load accounts: \(error.localizedDescription)")
            }
        }
    }
    
    func generateAndCopyOTP(for account: String, connection: YKFAccessoryConnection) {
        Task {
            do {
                let session = try await YKFOATHSession(connection: connection)
                let credential = try await session.calculateResponse(forKey: account, challenge: nil)
                
                guard let otpData = credential.value else {
                    throw YubiKeyError.noOTPGenerated
                }
                
                let otp = formatOTP(otpData)
                
                await MainActor.run {
                    // Copy to clipboard
                    UIPasteboard.general.string = otp
                    
                    // Show success and close
                    let successAlert = UIAlertController(
                        title: "✓ OTP Copied",
                        message: "\(otp)\n\nPaste it in the authentication field",
                        preferredStyle: .alert
                    )
                    
                    successAlert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
                        self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
                    })
                    
                    self.present(successAlert, animated: true)
                }
            } catch {
                showError("Failed to generate OTP: \(error.localizedDescription)")
            }
        }
    }
    
    func formatOTP(_ data: Data) -> String {
        let bytes = [UInt8](data)
        var otp: UInt32 = 0
        
        for i in 0..<min(4, bytes.count) {
            otp = (otp << 8) | UInt32(bytes[i])
        }
        
        otp = otp % 1000000
        return String(format: "%06d", otp)
    }
    
    func showError(_ message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        })
        present(alert, animated: true)
    }
}

enum YubiKeyError: Error {
    case notConnected
    case noOTPGenerated
    
    var localizedDescription: String {
        switch self {
        case .notConnected:
            return "YubiKey not connected via USB-C"
        case .noOTPGenerated:
            return "Failed to generate OTP"
        }
    }
}

#endif
