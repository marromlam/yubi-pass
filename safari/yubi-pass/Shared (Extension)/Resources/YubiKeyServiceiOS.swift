//
//  YubiKeyServiceiOS.swift
//  YubiPass
//
//  Cross-platform YubiKey service using YubiKit for iOS/iPadOS
//

import Foundation

#if os(iOS)
import YubiKit

@available(iOS 15.0, *)
class YubiKeyServiceiOS {
    static let shared = YubiKeyServiceiOS()
    
    private init() {
        setupYubiKit()
    }
    
    private func setupYubiKit() {
        // Start YubiKit session
        YubiKitManager.shared.startAccessoryConnection()
    }
    
    /// Generate TOTP from YubiKey connected via Lightning/USB-C
    func generateOTP(for account: String) async throws -> String {
        // Check if YubiKey is connected
        guard let connection = YubiKitManager.shared.accessoryConnection,
              connection.isConnected else {
            throw YubiKeyError.notConnected
        }
        
        // Get OATH session
        let session = try await YKFOATHSession(connection: connection)
        
        // Calculate TOTP
        let credential = try await session.calculateResponse(forKey: account, challenge: nil)
        
        guard let otpValue = credential.value else {
            throw YubiKeyError.noOTPGenerated
        }
        
        return formatOTP(otpValue)
    }
    
    /// Generate TOTP from YubiKey via NFC (iPhone only)
    @available(iOS 13.0, *)
    func generateOTPviaNFC(for account: String) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            YubiKitManager.shared.startNFCConnection { connection, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let connection = connection else {
                    continuation.resume(throwing: YubiKeyError.noConnection)
                    return
                }
                
                Task {
                    do {
                        let session = try await YKFOATHSession(connection: connection)
                        let credential = try await session.calculateResponse(forKey: account, challenge: nil)
                        
                        guard let otpValue = credential.value else {
                            throw YubiKeyError.noOTPGenerated
                        }
                        
                        continuation.resume(returning: self.formatOTP(otpValue))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    /// List all OATH accounts on the YubiKey
    func listAccounts() async throws -> [String] {
        guard let connection = YubiKitManager.shared.accessoryConnection,
              connection.isConnected else {
            throw YubiKeyError.notConnected
        }
        
        let session = try await YKFOATHSession(connection: connection)
        let credentials = try await session.listCredentials()
        
        return credentials.map { $0.key }
    }
    
    private func formatOTP(_ data: Data) -> String {
        // Convert OTP data to string
        let otp = data.map { String(format: "%02x", $0) }.joined()
        // Return last 6 digits
        return String(otp.suffix(6))
    }
}

enum YubiKeyError: Error {
    case notConnected
    case noConnection
    case noOTPGenerated
    case accountNotFound
}

#endif
