//
//  AppDelegate.swift
//  macOS (App)
//
//  Created by Marcos Romero on 29/8/25.
//

import Cocoa
import Foundation

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    
    private var requestMonitorTimer: Timer?
    private let requestDirectory = "/tmp/yubi-pass-requests"
    private let responseDirectory = "/tmp/yubi-pass-responses"
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        print("🔐 YubiPass: macOS app launched")
        
        // Create communication directories
        createCommunicationDirectories()
        
        // Check if ykman is available
        if YubiKeyService.shared.isYkmanAvailable() {
            print("🔐 YubiPass: ykman is available")
            if let version = YubiKeyService.shared.getYkmanVersion() {
                print("🔐 YubiPass: ykman version: \(version)")
            }
            
            // List available accounts
            switch YubiKeyService.shared.getAccounts() {
            case .success(let accounts):
                print("🔐 YubiPass: Available YubiKey accounts: \(accounts)")
            case .failure(let error):
                print("🔐 YubiPass: Error getting accounts: \(error.localizedDescription)")
            }
            
            // Test the generateOTP function with a known domain
            testGenerateOTPFunction()
            
        } else {
            print("🔐 YubiPass: ykman is not available")
        }
        
        // Start monitoring for Safari extension requests
        startMonitoringSafariExtensionRequests()
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        print("🔐 YubiPass: macOS app terminating")
        
        // Stop monitoring
        stopMonitoringSafariExtensionRequests()
    }
    
    // MARK: - Safari Extension Communication
    
    private func createCommunicationDirectories() {
        let fileManager = FileManager.default
        
        // Create request directory
        if !fileManager.fileExists(atPath: requestDirectory) {
            try? fileManager.createDirectory(atPath: requestDirectory, withIntermediateDirectories: true)
        }
        
        // Create response directory
        if !fileManager.fileExists(atPath: responseDirectory) {
            try? fileManager.createDirectory(atPath: responseDirectory, withIntermediateDirectories: true)
        }
        
        print("🔐 YubiPass: Communication directories created")
    }
    
    private func startMonitoringSafariExtensionRequests() {
        print("🔐 YubiPass: Starting to monitor Safari extension requests")
        
        requestMonitorTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkForSafariExtensionRequests()
        }
    }
    
    private func stopMonitoringSafariExtensionRequests() {
        requestMonitorTimer?.invalidate()
        requestMonitorTimer = nil
        print("🔐 YubiPass: Stopped monitoring Safari extension requests")
    }
    
    private func checkForSafariExtensionRequests() {
        let fileManager = FileManager.default
        
        do {
            let requestFiles = try fileManager.contentsOfDirectory(atPath: requestDirectory)
            
            for requestFile in requestFiles {
                let requestPath = "\(requestDirectory)/\(requestFile)"
                
                // Read the request
                if let requestData = try? Data(contentsOf: URL(fileURLWithPath: requestPath)),
                   let request = try? JSONSerialization.jsonObject(with: requestData) as? [String: Any],
                   let action = request["action"] as? String,
                   action == "generateOTP",
                   let domain = request["domain"] as? String {
                    
                    print("🔐 YubiPass: Received OTP request for domain: \(domain)")
                    
                    // Generate real OTP using YubiKeyService
                    let result = YubiKeyService.shared.generateOTP(for: domain)
                    
                    // Create response
                    var response: [String: Any] = [:]
                    
                    switch result {
                    case .success(let otpData):
                        response["success"] = true
                        response["otp"] = otpData.otp
                        response["account"] = otpData.account
                        print("🔐 YubiPass: Generated real OTP: \(otpData.otp) for account: \(otpData.account)")
                        
                    case .failure(let error):
                        response["success"] = false
                        response["error"] = error.localizedDescription
                        print("🔐 YubiPass: Failed to generate OTP: \(error.localizedDescription)")
                    }
                    
                    // Send response
                    sendResponseToSafariExtension(response: response, requestId: requestFile)
                    
                    // Remove the processed request file
                    try? fileManager.removeItem(atPath: requestPath)
                }
            }
        } catch {
            // Ignore errors for directory reading
        }
    }
    
    private func sendResponseToSafariExtension(response: [String: Any], requestId: String) {
        let responsePath = "\(responseDirectory)/\(requestId)"
        
        do {
            let responseData = try JSONSerialization.data(withJSONObject: response)
            try responseData.write(to: URL(fileURLWithPath: responsePath))
            print("🔐 YubiPass: Sent response to Safari extension: \(response)")
        } catch {
            print("🔐 YubiPass: Failed to send response: \(error)")
        }
    }
    
    // MARK: - Testing
    
    private func testGenerateOTPFunction() {
        print("\n🔐 YubiPass: ===== TESTING generateOTP FUNCTION =====")
        
        let testDomains = [
            "propylon-staging-ccms.auth.us-east-1.amazoncognito.com",
        ]
        
        for domain in testDomains {
            print("\n🔐 YubiPass: Testing domain: \(domain)")
            
            let result = YubiKeyService.shared.generateOTP(for: domain)
            
            switch result {
            case .success(let otpData):
                print("✅ SUCCESS: Generated OTP: \(otpData.otp) for account: \(otpData.account)")
            case .failure(let error):
                print("❌ FAILED: \(error.localizedDescription)")
            }
        }
        
        print("\n🔐 YubiPass: ===== TEST COMPLETED =====")
    }
}
