//
//  ContentView_iOS.swift
//  YubiPass iOS
//
//  USB-C only support for iPhone 15+ and iPad Pro
//

#if os(iOS)
import SwiftUI
import YubiKit

@available(iOS 15.0, *)
struct ContentView_iOS: View {
    @State private var isYubiKeyConnected = false
    @State private var accounts: [String] = []
    @State private var selectedAccount: String?
    @State private var generatedOTP: String?
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isGenerating = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // YubiKey connection status
                HStack {
                    Image(systemName: isYubiKeyConnected ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(isYubiKeyConnected ? .green : .red)
                    Text(isYubiKeyConnected ? "YubiKey Connected" : "Not Connected")
                        .font(.headline)
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(10)
                
                if !isYubiKeyConnected {
                    VStack(spacing: 15) {
                        Image(systemName: "cable.connector")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)
                        
                        Text("Connect your YubiKey")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Plug in your YubiKey 5C or 5C Nano via USB-C")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        
                        Text("Compatible with:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top)
                        
                        VStack(alignment: .leading, spacing: 5) {
                            Label("iPhone 15 / 15 Pro series", systemImage: "iphone")
                            Label("iPad Pro (USB-C models)", systemImage: "ipad")
                            Label("iPad Air (USB-C models)", systemImage: "ipad")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        
                        Button(action: refreshConnection) {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text("Check Connection")
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .padding(.horizontal)
                        .padding(.top)
                    }
                    .padding()
                } else {
                    // Accounts list
                    if accounts.isEmpty {
                        VStack(spacing: 15) {
                            Image(systemName: "key.slash")
                                .font(.system(size: 50))
                                .foregroundColor(.secondary)
                            
                            Text("No TOTP accounts found")
                                .font(.headline)
                            
                            Text("Configure TOTP accounts on your YubiKey first")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                    } else {
                        List {
                            ForEach(accounts, id: \.self) { account in
                                Button(action: {
                                    selectedAccount = account
                                    generateOTP(for: account)
                                }) {
                                    HStack {
                                        Image(systemName: "key.fill")
                                            .foregroundColor(.blue)
                                        VStack(alignment: .leading) {
                                            Text(account)
                                                .font(.body)
                                            if let parts = parseAccount(account) {
                                                Text(parts.issuer)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        Spacer()
                                        if isGenerating && selectedAccount == account {
                                            ProgressView()
                                        } else {
                                            Image(systemName: "arrow.right.circle")
                                                .foregroundColor(.blue)
                                        }
                                    }
                                    .padding(.vertical, 8)
                                }
                            }
                        }
                    }
                    
                    if let otp = generatedOTP {
                        VStack(spacing: 15) {
                            Text("Generated OTP")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            Text(otp)
                                .font(.system(size: 48, weight: .bold, design: .monospaced))
                                .padding()
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(10)
                            
                            HStack(spacing: 15) {
                                Button(action: {
                                    UIPasteboard.general.string = otp
                                }) {
                                    HStack {
                                        Image(systemName: "doc.on.doc")
                                        Text("Copy")
                                    }
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                                }
                                
                                Button(action: {
                                    generatedOTP = nil
                                }) {
                                    HStack {
                                        Image(systemName: "xmark.circle")
                                        Text("Clear")
                                    }
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(Color.secondary)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                                }
                            }
                            .padding(.horizontal)
                            
                            Text("Valid for 30 seconds")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(15)
                        .padding()
                    }
                }
                
                Spacer()
            }
            .navigationTitle("YubiPass")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: refreshAccounts) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(!isYubiKeyConnected || isGenerating)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
        .onAppear {
            setupYubiKit()
            checkYubiKeyConnection()
        }
    }
    
    func setupYubiKit() {
        // Initialize YubiKit for USB-C connections
        YubiKitManager.shared.startAccessoryConnection()
        
        // Listen for connection changes
        NotificationCenter.default.addObserver(
            forName: .YKFAccessoryDidConnect,
            object: nil,
            queue: .main
        ) { _ in
            checkYubiKeyConnection()
        }
        
        NotificationCenter.default.addObserver(
            forName: .YKFAccessoryDidDisconnect,
            object: nil,
            queue: .main
        ) { _ in
            isYubiKeyConnected = false
            accounts = []
            generatedOTP = nil
        }
    }
    
    func checkYubiKeyConnection() {
        if let connection = YubiKitManager.shared.accessoryConnection {
            isYubiKeyConnected = connection.isConnected
            if isYubiKeyConnected {
                refreshAccounts()
            }
        }
    }
    
    func refreshConnection() {
        checkYubiKeyConnection()
    }
    
    func refreshAccounts() {
        Task {
            do {
                guard let connection = YubiKitManager.shared.accessoryConnection,
                      connection.isConnected else {
                    throw YubiKeyError.notConnected
                }
                
                let session = try await YKFOATHSession(connection: connection)
                let credentials = try await session.listCredentials()
                
                await MainActor.run {
                    accounts = credentials.map { $0.key }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to load accounts: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }
    
    func generateOTP(for account: String) {
        Task {
            await MainActor.run {
                isGenerating = true
            }
            
            do {
                guard let connection = YubiKitManager.shared.accessoryConnection,
                      connection.isConnected else {
                    throw YubiKeyError.notConnected
                }
                
                let session = try await YKFOATHSession(connection: connection)
                let credential = try await session.calculateResponse(forKey: account, challenge: nil)
                
                guard let otpData = credential.value else {
                    throw YubiKeyError.noOTPGenerated
                }
                
                let otp = formatOTP(otpData)
                
                await MainActor.run {
                    generatedOTP = otp
                    isGenerating = false
                }
                
                // Auto-clear after 30 seconds
                Task {
                    try await Task.sleep(nanoseconds: 30_000_000_000)
                    await MainActor.run {
                        if generatedOTP == otp {
                            generatedOTP = nil
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to generate OTP: \(error.localizedDescription)"
                    showError = true
                    isGenerating = false
                }
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
    
    func parseAccount(_ account: String) -> (issuer: String, name: String)? {
        let parts = account.split(separator: ":")
        if parts.count == 2 {
            return (String(parts[0]), String(parts[1]))
        }
        return nil
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

#Preview {
    if #available(iOS 15.0, *) {
        ContentView_iOS()
    }
}

#endif
