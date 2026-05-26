import Foundation

class YubiKeyService {
    static let shared = YubiKeyService()

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
    
    // Key mapping loaded from extension storage via app group container
    private var keyMapping: [String: String] = [:]

    private init() {
        loadKeyMappingFromStorage()
    }
    
    // MARK: - Storage

    /// Reloads domain→account mappings from the shared extension storage JSON file.
    /// The extension writes codes as [{domain, codeName}] under "codes" key.
    func loadKeyMappingFromStorage() {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.marromlam.yubi-pass"
        ) else {
            print("🔐 YubiPass: App group container unavailable, no key mappings loaded")
            return
        }

        let storageFile = containerURL.appendingPathComponent("codes.json")
        guard let data = try? Data(contentsOf: storageFile),
              let codes = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else {
            print("🔐 YubiPass: No codes.json found in app group container")
            return
        }

        keyMapping = Dictionary(uniqueKeysWithValues: codes.compactMap { entry -> (String, String)? in
            guard let domain = entry["domain"], let codeName = entry["codeName"] else { return nil }
            return (domain, codeName)
        })
        print("🔐 YubiPass: Loaded \(keyMapping.count) key mappings from storage")
    }

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

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if task.terminationStatus == 0 {
                let accounts = output.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }

                // Update cache
                accountCache.removeAll()
                for account in accounts {
                    accountCache[account] = account
                }
                lastCacheUpdate = Date()

                return .success(accounts)
            }

            if output.isEmpty {
                return .failure(.noAccountsFound)
            }

            return .failure(.ykmanError(message: output))
        } catch {
            return .failure(.executionError(error: error))
        }
    }
    
    // MARK: - Domain Mapping
    
    private func findKeyForDomain(_ domain: String) -> String? {
        print("🔐 YubiPass: Looking for key mapping for domain: \(domain)")
        
        let domainLower = domain.lowercased()

        // First, try exact key mapping from configuration (case-insensitive)
        for (mappedDomain, mappedKey) in keyMapping {
            if mappedDomain.lowercased() == domainLower {
                print("🔐 YubiPass: Found exact key mapping: \(domain) -> \(mappedKey)")
                return mappedKey
            }
        }

        // Try partial key mapping (case-insensitive)
        for (mappedDomain, mappedKey) in keyMapping {
            if domainLower.contains(mappedDomain.lowercased()) || mappedDomain.lowercased().contains(domainLower) {
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
        // Check if the bundled ykman exists and is executable
        let fileManager = FileManager.default
        guard let localPath = Bundle.main.url(forResource: "ykman/ykman", withExtension: nil)?.path else {
            return false
        }
        
        if !fileManager.fileExists(atPath: localPath) || !fileManager.isExecutableFile(atPath: localPath) {
            return false
        }
        
        // Test the ykman command with a simple version check
        let process = Process()
        process.executableURL = URL(fileURLWithPath: localPath)
        process.arguments = ["--version"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        var isAvailable = false
        let semaphore = DispatchSemaphore(value: 0)
        
        process.terminationHandler = { (process) in
            isAvailable = process.terminationStatus == 0
            semaphore.signal()
        }
        
        do {
            try process.run()
            
            // Wait for completion with longer timeout (10 seconds)
            let result = semaphore.wait(timeout: .now() + 10.0)
            if result == .timedOut {
                process.terminate()
                return false
            }
            
            return isAvailable
        } catch {
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
