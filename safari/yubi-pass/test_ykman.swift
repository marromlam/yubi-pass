#!/usr/bin/env swift

import Foundation

// Test script for YubiKey integration
// This can be run from the command line to test ykman functionality

func testYkmanIntegration() {
    print("🔐 YubiPass: Testing ykman integration...")
    
    // Test system ykman
    testSystemYkman()
    
    // Test embedded ykman if available
    testEmbeddedYkman()
    
    print("🔐 YubiPass: Testing complete!")
}

func testSystemYkman() {
    print("\n📋 Testing system ykman...")
    
    let systemPath = "/opt/homebrew/bin/ykman"
    let fileManager = FileManager.default
    
    // Check if file exists
    if fileManager.fileExists(atPath: systemPath) {
        print("✅ System ykman file exists")
        
        // Check if executable
        if fileManager.isExecutableFile(atPath: systemPath) {
            print("✅ System ykman is executable")
            
            // Test version command
            testYkmanCommand(path: systemPath, description: "System ykman")
        } else {
            print("❌ System ykman is not executable")
        }
    } else {
        print("❌ System ykman file does not exist")
    }
}

func testEmbeddedYkman() {
    print("\n📋 Testing embedded ykman...")
    
    // Check if we can find the embedded binary
    let currentDirectory = FileManager.default.currentDirectoryPath
    let embeddedPath = "\(currentDirectory)/ykman_embedded"
    let fileManager = FileManager.default
    
    if fileManager.fileExists(atPath: embeddedPath) {
        print("✅ Embedded ykman file exists")
        
        if fileManager.isExecutableFile(atPath: embeddedPath) {
            print("✅ Embedded ykman is executable")
            
            // Test version command
            testYkmanCommand(path: embeddedPath, description: "Embedded ykman")
        } else {
            print("❌ Embedded ykman is not executable")
        }
    } else {
        print("❌ Embedded ykman file does not exist")
    }
}

func testYkmanCommand(path: String, description: String) {
    print("🔍 Testing \(description) with --version command...")
    
    let task = Process()
    task.executableURL = URL(fileURLWithPath: path)
    task.arguments = ["--version"]
    
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe
    
    do {
        try task.run()
        task.waitUntilExit()
        
        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
        
        if let output = String(data: outputData, encoding: .utf8) {
            print("✅ \(description) output: \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        
        if let error = String(data: errorData, encoding: .utf8), !error.isEmpty {
            print("⚠️  \(description) error: \(error.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        
        print("✅ \(description) --version completed with exit code: \(task.terminationStatus)")
        
    } catch {
        print("❌ \(description) failed to run: \(error)")
    }
}

func testYkmanOathAccounts(path: String, description: String) {
    print("🔍 Testing \(description) with oath accounts list command...")
    
    let task = Process()
    task.executableURL = URL(fileURLWithPath: path)
    task.arguments = ["oath", "accounts", "list"]
    
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe
    
    do {
        try task.run()
        task.waitUntilExit()
        
        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
        
        if let output = String(data: outputData, encoding: .utf8) {
            let accounts = output.components(separatedBy: .newlines)
                .filter { !$0.isEmpty }
                .map { $0.trimmingCharacters(in: .whitespaces) }
            
            if accounts.isEmpty {
                print("⚠️  \(description) no OATH accounts found")
            } else {
                print("✅ \(description) found \(accounts.count) OATH accounts:")
                for account in accounts {
                    print("   - \(account)")
                }
            }
        }
        
        if let error = String(data: errorData, encoding: .utf8), !error.isEmpty {
            print("⚠️  \(description) error: \(error.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        
        print("✅ \(description) oath accounts list completed with exit code: \(task.terminationStatus)")
        
    } catch {
        print("❌ \(description) failed to run: \(error)")
    }
}

func testYkmanOathCode(path: String, description: String, account: String) {
    print("🔍 Testing \(description) with oath code generation for account: \(account)...")
    
    let task = Process()
    task.executableURL = URL(fileURLWithPath: path)
    task.arguments = ["oath", "accounts", "code", account]
    
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe
    
    do {
        try task.run()
        task.waitUntilExit()
        
        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
        
        if let output = String(data: outputData, encoding: .utf8) {
            let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
            print("✅ \(description) OTP output: '\(trimmedOutput)'")
            
            // Try to extract OTP code
            let components = trimmedOutput.components(separatedBy: .whitespaces)
            if let lastComponent = components.last, !lastComponent.isEmpty {
                if lastComponent.count == 6 && lastComponent.allSatisfy({ $0.isNumber }) {
                    print("✅ \(description) extracted OTP: \(lastComponent)")
                } else {
                    print("⚠️  \(description) last component is not a 6-digit OTP: '\(lastComponent)'")
                }
            }
        }
        
        if let error = String(data: errorData, encoding: .utf8), !error.isEmpty {
            print("⚠️  \(description) error: \(error.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        
        print("✅ \(description) oath code generation completed with exit code: \(task.terminationStatus)")
        
    } catch {
        print("❌ \(description) failed to run: \(error)")
    }
}

// Main execution
if CommandLine.arguments.contains("--test") {
    testYkmanIntegration()
} else {
    print("🔐 YubiPass: ykman test script")
    print("Usage: swift test_ykman.swift --test")
    print("This will test both system and embedded ykman installations")
}
