//
//  SafariWebExtensionHandler.swift
//  Shared (Extension)
//
//  Created by Marcos Romero on 29/8/25.
//

import SafariServices
import os.log

class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {

    func beginRequest(with context: NSExtensionContext) {
        let request = context.inputItems.first as? NSExtensionItem

        let profile: UUID?
        if #available(iOS 17.0, macOS 14.0, *) {
            profile = request?.userInfo?[SFExtensionProfileKey] as? UUID
        } else {
            profile = request?.userInfo?["profile"] as? UUID
        }

        let message: Any?
        if #available(iOS 15.0, macOS 11.0, *) {
            message = request?.userInfo?[SFExtensionMessageKey]
        } else {
            message = request?.userInfo?["message"]
        }

        os_log(.default, "Received message from browser.runtime.sendNativeMessage: %@ (profile: %@)", String(describing: message), profile?.uuidString ?? "none")

        // Handle OTP generation request
        if let messageDict = message as? [String: Any],
           let action = messageDict["action"] as? String,
           action == "generateOTP" {
            
            handleGenerateOTPRequest(messageDict: messageDict, context: context)
            return
        }

        // Default response for other messages
        let response = NSExtensionItem()
        if #available(iOS 15.0, macOS 11.0, *) {
            response.userInfo = [ SFExtensionMessageKey: [ "echo": message ] ]
        } else {
            response.userInfo = [ "message": [ "echo": message ] ]
        }

        context.completeRequest(returningItems: [ response ], completionHandler: nil)
    }
    
    private func handleGenerateOTPRequest(messageDict: [String: Any], context: NSExtensionContext) {
        guard let domain = messageDict["domain"] as? String else {
            sendErrorResponse("Domain not provided", context: context)
            return
        }
        os_log(.default, "🔐 YubiPass: Handling OTP generation request for domain: %@", domain)
        
        // Try to get real OTP from main app via file-based communication
        if let otp = getRealOTPFromMainApp(for: domain) {
            os_log(.default, "🔐 YubiPass: Successfully got real OTP from main app: %@", otp)
            sendSuccessResponse(otp, context: context)
        } else {
            os_log(.default, "🔐 YubiPass: Failed to get OTP from main app, falling back to placeholder")
            // Fallback to placeholder OTP for testing
            let placeholderOTP = "000000"
            sendSuccessResponse(placeholderOTP, context: context)
        }
    }
    
    // MARK: - OTP Generation
    
    private func generatePlaceholderOTP(for domain: String) -> String {
        // Generate a 6-digit placeholder OTP based on domain
        let hash = abs(domain.hashValue)
        let otp = String(format: "%06d", hash % 1000000)
        os_log(.default, "🔐 YubiPass: Generated placeholder OTP: %@ for domain: %@", otp, domain)
        return otp
    }
    
    private func sendSuccessResponse(_ otp: String, context: NSExtensionContext) {
        os_log(.default, "Sending OTP success response: %@", otp)
        
        let responseItem = NSExtensionItem()
        if #available(iOS 15.0, macOS 11.0, *) {
            responseItem.userInfo = [ SFExtensionMessageKey: [
                "success": true,
                "otp": otp
            ]]
        } else {
            responseItem.userInfo = [ "message": [
                "success": true,
                "otp": otp
            ]]
        }
        
        context.completeRequest(returningItems: [responseItem], completionHandler: nil)
    }
    
    private func sendErrorResponse(_ error: String, context: NSExtensionContext) {
        os_log(.error, "Sending error response: %@", error)
        
        let responseItem = NSExtensionItem()
        if #available(iOS 15.0, macOS 11.0, *) {
            responseItem.userInfo = [ SFExtensionMessageKey: [
                "success": false,
                "error": error
            ]]
        } else {
            responseItem.userInfo = [ "message": [
                "success": false,
                "error": error
            ]]
        }
        
        context.completeRequest(returningItems: [responseItem], completionHandler: nil)
    }
    
    private func getRealOTPFromMainApp(for domain: String) -> String? {
        os_log(.default, "🔐 YubiPass: Requesting real OTP from main app for domain: %@", domain)
        
        // Safari web extensions cannot execute external processes like ykman due to sandbox restrictions
        // We'll use file-based communication with the main app
        // The main app will execute ykman and return the real OTP
        
        let requestId = UUID().uuidString
        let requestDirectory = "/tmp/yubi-pass-requests"
        let responseDirectory = "/tmp/yubi-pass-responses"
        
        // Create request
        let request: [String: Any] = [
            "action": "generateOTP",
            "domain": domain,
            "requestId": requestId,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        // Write request to file
        let requestPath = "\(requestDirectory)/\(requestId)"
        do {
            let requestData = try JSONSerialization.data(withJSONObject: request)
            try requestData.write(to: URL(fileURLWithPath: requestPath))
            os_log(.default, "🔐 YubiPass: Sent request to main app: %@", request)
        } catch {
            os_log(.error, "🔐 YubiPass: Failed to send request to main app: %@", error.localizedDescription)
            return nil
        }
        
        // Wait for response (with timeout)
        let startTime = Date()
        let timeout: TimeInterval = 5.0 // 5 seconds timeout
        
        while Date().timeIntervalSince(startTime) < timeout {
            let responsePath = "\(responseDirectory)/\(requestId)"
            
            if FileManager.default.fileExists(atPath: responsePath) {
                // Read response
                do {
                    let responseData = try Data(contentsOf: URL(fileURLWithPath: responsePath))
                    if let response = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] {
                        
                        // Clean up response file
                        try? FileManager.default.removeItem(atPath: responsePath)
                        
                        if let success = response["success"] as? Bool, success {
                            if let otp = response["otp"] as? String {
                                let account = response["account"] as? String ?? "Unknown"
                                os_log(.default, "🔐 YubiPass: Received real OTP: %@ for account: %@", otp, account)
                                return otp
                            }
                        } else {
                            let error = response["error"] as? String ?? "Unknown error"
                            os_log(.error, "🔐 YubiPass: Main app returned error: %@", error)
                        }
                    }
                } catch {
                    os_log(.error, "🔐 YubiPass: Failed to read response: %@", error.localizedDescription)
                }
                break
            }
            
            // Wait a bit before checking again
            Thread.sleep(forTimeInterval: 0.1)
        }
        
        os_log(.error, "🔐 YubiPass: Timeout waiting for response from main app")
        return nil
    }
    
    // MARK: - Helper Methods
    
    private func generateFallbackOTP(for domain: String) -> String {
        // Generate a placeholder OTP for testing purposes
        // In production, this should be replaced with real OTP generation via native messaging
        let timestamp = Int(Date().timeIntervalSince1970)
        let otp = String(format: "%06d", timestamp % 1000000)
        os_log(.default, "🔐 YubiPass: Generated fallback OTP: %@ for domain: %@", otp, domain)
        return otp
    }

}
