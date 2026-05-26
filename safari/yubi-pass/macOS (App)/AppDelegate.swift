//
//  AppDelegate.swift
//  macOS (App)
//
//  Created by Marcos Romero on 29/8/25.
//

#if os(macOS)
import Cocoa
import Foundation
#endif

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    
    private var requestMonitorTimer: Timer?
    private var requestDirectory: String = "/tmp/yubi-pass-requests"
    private var responseDirectory: String = "/tmp/yubi-pass-responses"
    
    // MARK: - Application Lifecycle
    
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Set up communication directories using app group container
        setupCommunicationDirectories()
        
        // Check if ykman is available
        checkYkmanAvailability()
        
        // Start monitoring for Safari extension requests
        startMonitoringSafariExtensionRequests()
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        // Stop monitoring
        stopMonitoringSafariExtensionRequests()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    private func checkYkmanAvailability() {
        if YubiKeyService.shared.isYkmanAvailable() {
            if let version = YubiKeyService.shared.getYkmanVersion() {
                print("ykman version: \(version)")
            }
        }
    }
    
    // MARK: - Safari Extension Communication
    
    private func setupCommunicationDirectories() {
        let fileManager = FileManager.default
        
        // Try to use app group container first
        if let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.marromlam.yubi-pass") {
            requestDirectory = containerURL.appendingPathComponent("requests").path
            responseDirectory = containerURL.appendingPathComponent("responses").path
        }
        
        // Create directories if they don't exist
        try? fileManager.createDirectory(atPath: requestDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(atPath: responseDirectory, withIntermediateDirectories: true)
    }
    
    private func startMonitoringSafariExtensionRequests() {
        requestMonitorTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkForSafariExtensionRequests()
        }
    }
    
    private func stopMonitoringSafariExtensionRequests() {
        requestMonitorTimer?.invalidate()
        requestMonitorTimer = nil
    }
    
    private func checkForSafariExtensionRequests() {
        let fileManager = FileManager.default
        
        guard let requestFiles = try? fileManager.contentsOfDirectory(atPath: requestDirectory),
              !requestFiles.isEmpty else {
            return
        }
        
        for requestFile in requestFiles {
            let requestPath = "\(requestDirectory)/\(requestFile)"
            
            guard let requestData = try? Data(contentsOf: URL(fileURLWithPath: requestPath)),
                  let request = try? JSONSerialization.jsonObject(with: requestData) as? [String: Any],
                  let action = request["action"] as? String else {
                continue
            }
            
            switch action {
            case "generateOTP":
                handleGenerateOTP(request: request, requestId: requestFile)
            case "getAccounts":
                handleGetAccounts(requestId: requestFile)
            default:
                break
            }
            
            try? fileManager.removeItem(atPath: requestPath)
        }
    }
    
    private func handleGenerateOTP(request: [String: Any], requestId: String) {
        guard let domain = request["domain"] as? String else { return }
        
        YubiKeyService.shared.loadKeyMappingFromStorage()
        let result = YubiKeyService.shared.generateOTP(for: domain)
        
        var response: [String: Any]
        switch result {
        case .success(let otpData):
            response = ["success": true, "otp": otpData.otp, "account": otpData.account]
        case .failure(let error):
            response = ["success": false, "error": error.localizedDescription]
        }
        
        sendResponseToSafariExtension(response: response, requestId: requestId)
    }
    
    private func handleGetAccounts(requestId: String) {
        let result = YubiKeyService.shared.getAccounts()
        
        var response: [String: Any]
        switch result {
        case .success(let accounts):
            response = ["success": true, "accounts": accounts]
        case .failure(let error):
            response = ["success": false, "error": error.localizedDescription]
        }
        
        sendResponseToSafariExtension(response: response, requestId: requestId)
    }
    
    private func sendResponseToSafariExtension(response: [String: Any], requestId: String) {
        let responsePath = "\(responseDirectory)/\(requestId)"
        
        guard let responseData = try? JSONSerialization.data(withJSONObject: response) else {
            return
        }
        
        try? responseData.write(to: URL(fileURLWithPath: responsePath))
    }
}
