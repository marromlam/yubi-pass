//
//  CredentialProviderViewController_iOS.swift
//  YubiPass AutoFill Extension
//
//  AutoFill extension for iOS/iPadOS password fields
//

#if os(iOS)
import AuthenticationServices
import YubiKit

@available(iOS 15.0, *)
class CredentialProviderViewController: ASCredentialProviderViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Initialize YubiKit for USB-C connection
        YubiKitManager.shared.startAccessoryConnection()
    }
    
    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        // Show list of available OTP accounts
        checkYubiKeyAndShowAccounts(for: serviceIdentifiers)
    }
    
    override func provideCredentialWithoutUserInteraction(for credentialIdentity: ASPasswordCredentialIdentity) {
        // Generate OTP without user interaction (if possible)
        generateOTPQuickly(for: credentialIdentity)
    }
    
    override func prepareInterfaceToProvideCredential(for credentialIdentity: ASPasswordCredentialIdentity) {
        // Show UI to generate OTP
        generateOTPWithUI(for: credentialIdentity)
    }
    
    func checkYubiKeyAndShowAccounts(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        guard let connection = YubiKitManager.shared.accessoryConnection,
              connection.isConnected else {
            let error = NSError(
                domain: ASExtensionErrorDomain,
                code: ASExtensionError.userInteractionRequired.rawValue,
                userInfo: [NSLocalizedDescriptionKey: "YubiKey not connected"]
            )
            extensionContext.cancelRequest(withError: error)
            return
        }
        
        Task {
            do {
                let session = try await YKFOATHSession(connection: connection)
                let credentials = try await session.listCredentials()
                
                // Filter accounts based on service identifier
                let domain = serviceIdentifiers.first?.identifier
                let matchingAccounts = credentials.filter { credential in
                    if let domain = domain {
                        return credential.key.lowercased().contains(domain.lowercased())
                    }
                    return true
                }
                
                await MainActor.run {
                    if matchingAccounts.isEmpty {
                        showNoAccountsFound()
                    } else {
                        showAccountSelection(matchingAccounts, connection: connection)
                    }
                }
            } catch {
                let nsError = NSError(
                    domain: ASExtensionErrorDomain,
                    code: ASExtensionError.failed.rawValue,
                    userInfo: [NSLocalizedDescriptionKey: error.localizedDescription]
                )
                extensionContext.cancelRequest(withError: nsError)
            }
        }
    }
    
    func showAccountSelection(_ accounts: [YKFOATHCredential], connection: YKFAccessoryConnection) {
        let alert = UIAlertController(
            title: "Select Account",
            message: "Choose an account to generate OTP",
            preferredStyle: .actionSheet
        )
        
        for account in accounts {
            let action = UIAlertAction(title: account.key, style: .default) { [weak self] _ in
                self?.generateOTP(for: account.key, connection: connection)
            }
            alert.addAction(action)
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            let error = NSError(
                domain: ASExtensionErrorDomain,
                code: ASExtensionError.userCanceled.rawValue,
                userInfo: nil
            )
            self?.extensionContext.cancelRequest(withError: error)
        })
        
        present(alert, animated: true)
    }
    
    func generateOTPQuickly(for credentialIdentity: ASPasswordCredentialIdentity) {
        guard let connection = YubiKitManager.shared.accessoryConnection,
              connection.isConnected else {
            let error = NSError(
                domain: ASExtensionErrorDomain,
                code: ASExtensionError.failed.rawValue,
                userInfo: [NSLocalizedDescriptionKey: "YubiKey not connected"]
            )
            extensionContext.cancelRequest(withError: error)
            return
        }
        
        Task {
            do {
                let session = try await YKFOATHSession(connection: connection)
                
                // Find matching account
                let credentials = try await session.listCredentials()
                guard let matchingCredential = credentials.first(where: { 
                    $0.key.contains(credentialIdentity.serviceIdentifier.identifier)
                }) else {
                    throw YubiKeyError.noMatchingAccount
                }
                
                let credential = try await session.calculateResponse(forKey: matchingCredential.key, challenge: nil)
                
                guard let otpData = credential.value else {
                    throw YubiKeyError.noOTPGenerated
                }
                
                let otp = formatOTP(otpData)
                
                // Return OTP as password
                let passwordCredential = ASPasswordCredential(
                    user: credentialIdentity.user,
                    password: otp
                )
                
                await MainActor.run {
                    extensionContext.completeRequest(withSelectedCredential: passwordCredential, completionHandler: nil)
                }
            } catch {
                let nsError = NSError(
                    domain: ASExtensionErrorDomain,
                    code: ASExtensionError.failed.rawValue,
                    userInfo: [NSLocalizedDescriptionKey: error.localizedDescription]
                )
                extensionContext.cancelRequest(withError: nsError)
            }
        }
    }
    
    func generateOTPWithUI(for credentialIdentity: ASPasswordCredentialIdentity) {
        // Same as generateOTPQuickly but can show UI
        generateOTPQuickly(for: credentialIdentity)
    }
    
    func generateOTP(for accountKey: String, connection: YKFAccessoryConnection) {
        Task {
            do {
                let session = try await YKFOATHSession(connection: connection)
                let credential = try await session.calculateResponse(forKey: accountKey, challenge: nil)
                
                guard let otpData = credential.value else {
                    throw YubiKeyError.noOTPGenerated
                }
                
                let otp = formatOTP(otpData)
                
                // Create credential with OTP as password
                let passwordCredential = ASPasswordCredential(
                    user: accountKey,
                    password: otp
                )
                
                await MainActor.run {
                    extensionContext.completeRequest(withSelectedCredential: passwordCredential, completionHandler: nil)
                }
            } catch {
                let nsError = NSError(
                    domain: ASExtensionErrorDomain,
                    code: ASExtensionError.failed.rawValue,
                    userInfo: [NSLocalizedDescriptionKey: error.localizedDescription]
                )
                extensionContext.cancelRequest(withError: nsError)
            }
        }
    }
    
    func showNoAccountsFound() {
        let alert = UIAlertController(
            title: "No Accounts",
            message: "No TOTP accounts found on YubiKey",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            let error = NSError(
                domain: ASExtensionErrorDomain,
                code: ASExtensionError.failed.rawValue,
                userInfo: [NSLocalizedDescriptionKey: "No accounts found"]
            )
            self?.extensionContext.cancelRequest(withError: error)
        })
        
        present(alert, animated: true)
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
}

enum YubiKeyError: Error {
    case notConnected
    case noOTPGenerated
    case noMatchingAccount
    
    var localizedDescription: String {
        switch self {
        case .notConnected:
            return "YubiKey not connected via USB-C"
        case .noOTPGenerated:
            return "Failed to generate OTP"
        case .noMatchingAccount:
            return "No matching TOTP account found"
        }
    }
}

#endif
