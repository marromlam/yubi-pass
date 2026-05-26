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

        if let messageDict = message as? [String: Any],
           let action = messageDict["action"] as? String {

            switch action {
            case "generateOTP":
                handleGenerateOTPRequest(messageDict: messageDict, context: context)
                return
            case "syncCodes":
                handleSyncCodesRequest(messageDict: messageDict, context: context)
                return
            case "getAccounts":
                handleGetAccountsRequest(messageDict: messageDict, context: context)
                return
            case "getMappings":
                handleGetMappingsRequest(context: context)
                return
            default:
                break
            }
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
        
        #if os(macOS)
        // macOS: Use ykman with file-based communication
        if let result = getRealOTPFromMainApp(for: domain) {
            if result.hasPrefix("ERROR:") {
                let msg = String(result.dropFirst(6))
                os_log(.error, "🔐 YubiPass: App returned error: %@", msg)
                sendErrorResponse(msg, context: context)
            } else {
                os_log(.default, "🔐 YubiPass: Successfully got real OTP from main app: %@", result)
                sendSuccessResponse(result, context: context)
            }
        } else {
            os_log(.error, "🔐 YubiPass: Failed to get OTP from main app for domain: %@", domain)
            sendErrorResponse("Could not generate OTP. Make sure the YubiPass app is running and your YubiKey is connected.", context: context)
        }
        #elseif os(iOS)
        // iOS: Use YubiKit for physical YubiKey access
        Task {
            do {
                if #available(iOS 15.0, *) {
                    let otp = try await YubiKeyServiceiOS.shared.generateOTP(for: domain)
                    sendSuccessResponse(otp, context: context)
                } else {
                    sendErrorResponse("iOS 15.0 or later required", context: context)
                }
            } catch {
                os_log(.error, "🔐 YubiPass iOS: Failed to generate OTP: %@", error.localizedDescription)
                sendErrorResponse("Failed to generate OTP. Please connect your YubiKey or tap it to your device.", context: context)
            }
        }
        #endif
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
    
    private func handleGetMappingsRequest(context: NSExtensionContext) {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.marromlam.yubi-pass"
        ) else {
            sendMappingsResponse([], context: context)
            return
        }

        let storageFile = containerURL.appendingPathComponent("codes.json")
        guard let data = try? Data(contentsOf: storageFile),
              let codes = try? JSONSerialization.jsonObject(with: data) else {
            sendMappingsResponse([], context: context)
            return
        }

        sendMappingsResponse(codes, context: context)
    }

    private func sendMappingsResponse(_ codes: Any, context: NSExtensionContext) {
        let responseItem = NSExtensionItem()
        if #available(iOS 15.0, macOS 11.0, *) {
            responseItem.userInfo = [SFExtensionMessageKey: ["success": true, "codes": codes]]
        } else {
            responseItem.userInfo = ["message": ["success": true, "codes": codes]]
        }
        context.completeRequest(returningItems: [responseItem], completionHandler: nil)
    }

    private func handleSyncCodesRequest(messageDict: [String: Any], context: NSExtensionContext) {
        guard let codes = messageDict["codes"] else {
            sendErrorResponse("No codes provided", context: context)
            return
        }

        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.marromlam.yubi-pass"
        ) else {
            os_log(.error, "🔐 YubiPass: App group container unavailable, cannot sync codes")
            sendErrorResponse("App group container unavailable", context: context)
            return
        }

        let storageFile = containerURL.appendingPathComponent("codes.json")
        do {
            let data = try JSONSerialization.data(withJSONObject: codes)
            try data.write(to: storageFile, options: .atomic)
            os_log(.default, "🔐 YubiPass: Synced codes to %@", storageFile.path)
            sendSuccessResponse("synced", context: context)
        } catch {
            os_log(.error, "🔐 YubiPass: Failed to write codes.json: %@", error.localizedDescription)
            sendErrorResponse(error.localizedDescription, context: context)
        }
    }

    private func handleGetAccountsRequest(messageDict: [String: Any], context: NSExtensionContext) {
        let requestId = UUID().uuidString

        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.marromlam.yubi-pass"
        ) else {
            sendErrorResponse("App group container unavailable", context: context)
            return
        }

        let requestDirectory = containerURL.appendingPathComponent("requests").path
        let responseDirectory = containerURL.appendingPathComponent("responses").path
        let request: [String: Any] = [
            "action": "getAccounts",
            "requestId": requestId,
            "timestamp": Date().timeIntervalSince1970
        ]
        let requestPath = "\(requestDirectory)/\(requestId)"

        guard let requestData = try? JSONSerialization.data(withJSONObject: request),
              (try? requestData.write(to: URL(fileURLWithPath: requestPath))) != nil else {
            sendErrorResponse("Could not create getAccounts request", context: context)
            return
        }

        let startTime = Date()
        let fileManager = FileManager.default
        while Date().timeIntervalSince(startTime) < 5.0 {
            let responsePath = "\(responseDirectory)/\(requestId)"
            if fileManager.fileExists(atPath: responsePath),
               let data = try? Data(contentsOf: URL(fileURLWithPath: responsePath)),
               let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                try? fileManager.removeItem(atPath: responsePath)
                if let success = response["success"] as? Bool, success {
                    let accounts = response["accounts"] as? [String] ?? []
                    sendAccountsResponse(accounts, context: context)
                } else {
                    let error = response["error"] as? String ?? "Could not load accounts"
                    sendErrorResponse(error, context: context)
                }
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        sendErrorResponse("The YubiPass app is not running or did not respond in time", context: context)
    }

    private func sendAccountsResponse(_ accounts: [String], context: NSExtensionContext) {
        let responseItem = NSExtensionItem()
        if #available(iOS 15.0, macOS 11.0, *) {
            responseItem.userInfo = [SFExtensionMessageKey: ["success": true, "accounts": accounts]]
        } else {
            responseItem.userInfo = ["message": ["success": true, "accounts": accounts]]
        }
        context.completeRequest(returningItems: [responseItem], completionHandler: nil)
    }

    private func getRealOTPFromMainApp(for domain: String) -> String? {
        os_log(.default, "🔐 YubiPass: Requesting real OTP from main app for domain: %@", domain)
        
        // Safari web extensions cannot execute external processes like ykman due to sandbox restrictions
        // We'll use file-based communication with the main app via app group container
        // The main app will execute ykman and return the real OTP
        
        let requestId = UUID().uuidString
        
        // Use app group container for communication
        let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.marromlam.yubi-pass")
        let requestDirectory = containerURL?.appendingPathComponent("requests").path ?? "/tmp/yubi-pass-requests"
        let responseDirectory = containerURL?.appendingPathComponent("responses").path ?? "/tmp/yubi-pass-responses"
        
        os_log(.default, "🔐 YubiPass: Using request directory: %@", requestDirectory)
        os_log(.default, "🔐 YubiPass: Using response directory: %@", responseDirectory)
        
        // Check if directories exist
        let fileManager = FileManager.default
        let requestDirExists = fileManager.fileExists(atPath: requestDirectory)
        let responseDirExists = fileManager.fileExists(atPath: responseDirectory)
        
        os_log(.default, "🔐 YubiPass: Request directory exists: %@", requestDirExists ? "YES" : "NO")
        os_log(.default, "🔐 YubiPass: Response directory exists: %@", responseDirExists ? "YES" : "NO")
        
        // Create request
        let request: [String: Any] = [
            "action": "generateOTP",
            "domain": domain,
            "requestId": requestId,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        os_log(.default, "🔐 YubiPass: Created request: %@", String(describing: request))
        
        // Write request to file
        let requestPath = "\(requestDirectory)/\(requestId)"
        do {
            let requestData = try JSONSerialization.data(withJSONObject: request)
            try requestData.write(to: URL(fileURLWithPath: requestPath))
            os_log(.default, "🔐 YubiPass: Successfully wrote request to: %@", requestPath)
        } catch {
            os_log(.error, "🔐 YubiPass: Failed to write request to main app: %@", error.localizedDescription)
            os_log(.error, "🔐 YubiPass: Error details: %@", String(describing: error))
            return nil
        }
        
        // Wait for response (with timeout)
        let startTime = Date()
        let timeout: TimeInterval = 5.0 // 5 seconds timeout
        
        os_log(.default, "🔐 YubiPass: Waiting for response from main app...")
        
        while Date().timeIntervalSince(startTime) < timeout {
            let responsePath = "\(responseDirectory)/\(requestId)"
            
            if fileManager.fileExists(atPath: responsePath) {
                os_log(.default, "🔐 YubiPass: Found response file at: %@", responsePath)
                
                // Read response
                do {
                    let responseData = try Data(contentsOf: URL(fileURLWithPath: responsePath))
                    if let response = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] {
                        
                        os_log(.default, "🔐 YubiPass: Parsed response: %@", String(describing: response))
                        
                        // Clean up response file
                        try? fileManager.removeItem(atPath: responsePath)
                        
                        if let success = response["success"] as? Bool, success {
                            if let otp = response["otp"] as? String {
                                let account = response["account"] as? String ?? "Unknown"
                                os_log(.default, "🔐 YubiPass: Received real OTP: %@ for account: %@", otp, account)
                                return otp
                            }
                        } else {
                            let error = response["error"] as? String ?? "Unknown error"
                            os_log(.error, "🔐 YubiPass: Main app returned error: %@", error)
                            // Return error string prefixed so caller can surface it
                            return "ERROR:\(error)"
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
    
}
