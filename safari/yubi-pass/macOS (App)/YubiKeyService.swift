import Foundation

class YubiKeyService {
    static let shared = YubiKeyService();
    
    

    
    
    // Use only the bundled ykman binary from the app bundle
    private var ykmanPath: String {
        guard let localPath = Bundle.main.url(forResource: "ykman/ykman", withExtension: nil)?.path else {
            fatalError("🔐 YubiPass: Bundled ykman binary not found in app bundle")
        }
        
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: localPath) && fileManager.isExecutableFile(atPath: localPath) else {
            fatalError("🔐 YubiPass: Bundled ykman binary is not executable at: \(localPath)")
        }
        
        print("🔐 YubiPass: Using bundled ykman binary at: \(localPath)")
        return localPath
    }
    
    private var accountCache: [String: String] = [:]
    private var lastCacheUpdate: Date?
    private let cacheTimeout: TimeInterval = 300 // 5 minutes
    
    // Key mapping configuration (similar to Python config)
    private let keyMapping: [String: String] = [
        "propylon-staging-ccms.auth.us-east-1.amazoncognito.com": "Propylon Staging CCMS",
        "FIDO2": "FIDO"
        // Add more mappings as needed
    ]
    
    private init() {}
    
    // MARK: - OTP Generation
    
    func generateOTP(for domain: String) -> Result<(otp: String, account: String), YubiKeyError> {
        // First, try to find a key mapping for the domain
        let keyName = findKeyForDomain(domain)
        
        if let keyName = keyName {
            let result = generateOTP(forKey: keyName)
            switch result {
            case .success(let otp):
                return .success((otp: otp, account: keyName))
            case .failure(let error):
                return .failure(error)
            }
        } else {
            return .failure(.noKeyFound(domain: domain))
        }
    }
    
    private func generateOTP(forKey keyName: String) -> Result<String, YubiKeyError> {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: ykmanPath)
        task.arguments = ["oath", "accounts", "code", keyName]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            if task.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    // Use the same logic as Python: take the last space-separated part
                    let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    let components = trimmedOutput.components(separatedBy: .whitespaces)
                    
                    if let lastComponent = components.last, !lastComponent.isEmpty {
                        // The last component should be the OTP code
                        if lastComponent.count == 6 && lastComponent.allSatisfy({ $0.isNumber }) {
                            print("🔐 YubiPass: Generated OTP: \(lastComponent) for account: \(keyName)")
                            return .success(lastComponent)
                        } else {
                            print("🔐 YubiPass: Last component is not a 6-digit OTP: '\(lastComponent)'")
                            print("🔐 YubiPass: Full ykman output: '\(trimmedOutput)'")
                        }
                    }
                }
                return .failure(.invalidOTPFormat)
            } else {
                let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
                let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                return .failure(.ykmanError(message: errorMessage))
            }
        } catch {
            return .failure(.executionError(error: error))
        }
    }
    
    // MARK: - Account Management
    
    func getAccounts() -> Result<[String], YubiKeyError> {
        // Check cache first
        if let lastUpdate = lastCacheUpdate,
           Date().timeIntervalSince(lastUpdate) < cacheTimeout {
            return .success(Array(accountCache.keys))
        }
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: ykmanPath)
        task.arguments = ["oath", "accounts", "list"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            if task.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    let accounts = output.components(separatedBy: .newlines)
                        .filter { !$0.isEmpty }
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                    
                    // Update cache
                    accountCache.removeAll()
                    for account in accounts {
                        accountCache[account] = account
                    }
                    lastCacheUpdate = Date()
                    
                    return .success(accounts)
                }
            }
            
            return .failure(.noAccountsFound)
        } catch {
            return .failure(.executionError(error: error))
        }
    }
    
    // MARK: - Domain Mapping
    
    private func findKeyForDomain(_ domain: String) -> String? {
        print("🔐 YubiPass: Looking for key mapping for domain: \(domain)")
        
        // First, try exact key mapping from configuration
        if let mappedKey = keyMapping[domain] {
            print("🔐 YubiPass: Found exact key mapping: \(domain) -> \(mappedKey)")
            return mappedKey
        }
        
        // Try partial key mapping (domain contains key or vice versa)
        for (mappedDomain, mappedKey) in keyMapping {
            if domain.contains(mappedDomain) || mappedDomain.contains(domain) {
                print("🔐 YubiPass: Found partial key mapping: \(domain) -> \(mappedKey)")
                return mappedKey
            }
        }
        
        // Then try exact domain match in account cache
        if let account = accountCache[domain] {
            print("🔐 YubiPass: Found exact account match: \(domain) -> \(account)")
            return account
        }
        
        // Try to find accounts that contain the domain
        for (accountName, _) in accountCache {
            if accountName.lowercased().contains(domain.lowercased()) ||
               domain.lowercased().contains(accountName.lowercased()) {
                print("🔐 YubiPass: Found partial account match: \(domain) -> \(accountName)")
                return accountName
            }
        }
        
        // Try common patterns
        let commonPatterns = [
            "github.com": "github",
            "google.com": "google",
            "microsoft.com": "microsoft",
            "apple.com": "apple",
            "amazon.com": "amazon"
        ]
        
        for (pattern, key) in commonPatterns {
            if domain.contains(pattern) {
                print("🔐 YubiPass: Found common pattern match: \(domain) -> \(key)")
                return key
            }
        }
        
        print("🔐 YubiPass: No key mapping found for domain: \(domain)")
        return nil
    }
    
    // MARK: - Utility Methods
    
    func isYkmanAvailable() -> Bool {
        print("🔐 YubiPass: Checking if bundled ykman is available...")
        
        
        
        
        func runYkmanCommand() {
            guard let ykmanURL = Bundle.main.url(forResource: "ykman/ykman", withExtension: nil) else {
                print("ykman not found in bundle")
                return
            }

            let process = Process()
            process.executableURL = ykmanURL
            process.arguments = ["list"] // Example command

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            do {
                try process.run()
                process.waitUntilExit()

                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()

                if let output = String(data: outData, encoding: .utf8),
                   !output.isEmpty {
                    print("Output:\n\(output)")
                }

                if let errorOutput = String(data: errData, encoding: .utf8),
                   !errorOutput.isEmpty {
                    print("Error:\n\(errorOutput)")
                }

            } catch {
                print("Failed to run ykman: \(error)")
            }
        }
        
        let aaa = runYkmanCommand()
        
        
        
        
        
        
        
        
        
        
        
        
        
        // Check if the bundled ykman exists and is executable
        let fileManager = FileManager.default
        guard let localPath = Bundle.main.url(forResource: "ykman/ykman", withExtension: nil)?.path else {
            print("🔐 YubiPass: Bundled ykman binary not found in app bundle")
            return false
        }
        
        if !fileManager.fileExists(atPath: localPath) {
            print("🔐 YubiPass: Bundled ykman file does not exist at: \(localPath)")
            return false
        }
        
        if !fileManager.isExecutableFile(atPath: localPath) {
            print("🔐 YubiPass: Bundled ykman file is not executable at: \(localPath)")
            return false
        }
        
        // Test the ykman command with a simple version check
        let process = Process()
        process.executableURL = URL(fileURLWithPath: localPath)
        process.arguments = ["--version"]
        
        var isAvailable = false
        let semaphore = DispatchSemaphore(value: 0)
        
        process.terminationHandler = { (process) in
            isAvailable = process.terminationStatus == 0
            print("🔐 YubiPass: Bundled ykman --version completed with exit code: \(process.terminationStatus)")
            semaphore.signal()
        }
        
        do {
            try process.run()
            print("🔐 YubiPass: Bundled ykman --version command started successfully")
            
            // Wait for completion with timeout
            let result = semaphore.wait(timeout: .now() + 5.0)
            if result == .timedOut {
                print("🔐 YubiPass: Bundled ykman --version command timed out")
                return false
            }
            
            print("🔐 YubiPass: Bundled ykman is available: \(isAvailable)")
            return isAvailable
        } catch {
            print("🔐 YubiPass: Error running bundled ykman --version: \(error)")
            print("🔐 YubiPass: Error details: \(error.localizedDescription)")
            return false
        }
    }
    
    func getYkmanVersion() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: ykmanPath)
        task.arguments = ["--version"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            if task.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            return nil
        }
        
        return nil
    }
    
    // MARK: - Helper Tool Management
    
    /// Returns the current ykman path being used
    func getCurrentYkmanPath() -> String {
        return ykmanPath
    }
    
    /// Returns information about the bundled ykman installation
    func getYkmanInfo() -> [String: Any] {
        var info: [String: Any] = [:]
        
        // Check bundled binary
        if let localPath = Bundle.main.url(forResource: "ykman/ykman", withExtension: nil)?.path {
            let fileManager = FileManager.default
            info["bundled_exists"] = fileManager.fileExists(atPath: localPath)
            info["bundled_executable"] = fileManager.isExecutableFile(atPath: localPath)
            info["bundled_path"] = localPath
            info["current_path"] = localPath
        }
        
        return info
    }
}

// MARK: - Error Types

enum YubiKeyError: Error, LocalizedError {
    case noKeyFound(domain: String)
    case noAccountsFound
    case invalidOTPFormat
    case ykmanError(message: String)
    case executionError(error: Error)
    case ykmanNotAvailable
    
    var errorDescription: String? {
        switch self {
        case .noKeyFound(let domain):
            return "No TOTP key found for domain: \(domain)"
        case .noAccountsFound:
            return "No OATH accounts found on YubiKey"
        case .invalidOTPFormat:
            return "Invalid OTP format received from YubiKey"
        case .ykmanError(let message):
            return "YubiKey Manager error: \(message)"
        case .executionError(let error):
            return "Execution error: \(error.localizedDescription)"
        case .ykmanNotAvailable:
            return "YubiKey Manager (ykman) is not installed or not in PATH"
        }
    }
}
