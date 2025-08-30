import SafariServices
import Foundation

class SafariExtensionHandler: SFSafariExtensionHandler {

    override func messageReceived(withName messageName: String, from page: SFSafariPage, userInfo: [String : Any]?) {
        // Handle messages from the content script
        if messageName == "generateOTP" {
            handleGenerateOTPRequest(from: page, userInfo: userInfo)
        }
    }

    override func validateContextMenuItem(withCommand command: String, in page: SFSafariPage, userInfo: [String : Any]?, validationHandler: @escaping ((Bool, String) -> Void)) {
        // Validate context menu items
        if command == "generateOTP" {
            // Always show for editable elements
            validationHandler(true, "Generate OTP")
        } else {
            validationHandler(false, "")
        }
    }

    override func contextMenuItemSelected(withCommand command: String, in page: SFSafariPage, userInfo: [String : Any]?) {
        if command == "generateOTP" {
            // Send a message to the content script to generate OTP
            page.dispatchMessageToScript(withName: "contextMenuGenerateOTP", userInfo: nil)
        }
    }

    private func handleGenerateOTPRequest(from page: SFSafariPage, userInfo: [String : Any]?) {
        guard let domain = userInfo?["domain"] as? String else {
            sendErrorResponse(to: page, error: "No domain provided")
            return
        }

        print("SafariExtensionHandler: Requesting OTP for domain: \(domain)")

        // Send request to main app via App Groups UserDefaults
        requestOTPFromMainApp(for: domain, page: page)
    }

    private func requestOTPFromMainApp(for domain: String, page: SFSafariPage) {
        guard let userDefaults = UserDefaults(suiteName: "group.com.yubipass.extension") else {
            sendErrorResponse(to: page, error: "Failed to access App Groups")
            return
        }

        // Send request to main app
        userDefaults.set(domain, forKey: "requestedDomain")
        userDefaults.set(Date(), forKey: "requestTimestamp")
        userDefaults.set(domain, forKey: "requestingPage")

        print("SafariExtensionHandler: Request sent to main app for domain: \(domain)")

        // Start polling for response
        pollForResponse(from: page, userDefaults: userDefaults)
    }

    private func pollForResponse(from page: SFSafariPage, userDefaults: UserDefaults) {
        var attempts = 0
        let maxAttempts = 20 // 10 seconds max wait time
        
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            attempts += 1
            
            if let responseTimestamp = userDefaults.object(forKey: "responseTimestamp") as? Date,
               let requestTimestamp = userDefaults.object(forKey: "requestTimestamp") as? Date,
               responseTimestamp > requestTimestamp {
                
                // Response received
                timer.invalidate()
                
                if userDefaults.bool(forKey: "responseSuccess") {
                    if let otp = userDefaults.string(forKey: "responseOTP") {   
                        self.sendSuccessResponse(to: page, otp: otp)
                        print("SafariExtensionHandler: OTP received from main app: \(otp)")
                    } else {
                        self.sendErrorResponse(to: page, error: "No OTP received from main app")
                    }
                } else {
                    let error = userDefaults.string(forKey: "responseError") ?? "Unknown error"
                    self.sendErrorResponse(to: page, error: error)
                }
                
                // Clear response data
                userDefaults.removeObject(forKey: "responseOTP")
                userDefaults.removeObject(forKey: "responseTimestamp")
                userDefaults.removeObject(forKey: "responseSuccess")
                userDefaults.removeObject(forKey: "responseError")
                
            } else if attempts >= maxAttempts {
                // Timeout
                timer.invalidate()
                self.sendErrorResponse(to: page, error: "Timeout waiting for OTP from main app")
                print("SafariExtensionHandler: Timeout waiting for OTP response")
            }
        }
    }

    private func sendSuccessResponse(to page: SFSafariPage, otp: String) {
        page.dispatchMessageToScript(withName: "otpGenerated", userInfo: ["otp": otp, "success": true])
    }

    private func sendErrorResponse(to page: SFSafariPage, error: String) {
        page.dispatchMessageToScript(withName: "otpGenerated", userInfo: ["error": error, "success": false])
    }
}
