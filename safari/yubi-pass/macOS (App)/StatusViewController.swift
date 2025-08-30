import Cocoa

class StatusViewController: NSViewController {
    
    var statusLabel: NSTextField!
    var ykmanStatusLabel: NSTextField!
    var accountsLabel: NSTextField!
    var refreshButton: NSButton!
    var openSafariButton: NSButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        refreshStatus()
    }
    
    private func setupUI() {
        // Create UI elements programmatically since we don't have a storyboard
        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.spacing = 10
        stackView.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        
        // Status label
        statusLabel = NSTextField(labelWithString: "YubiPass Status")
        statusLabel.font = NSFont.boldSystemFont(ofSize: 16)
        stackView.addArrangedSubview(statusLabel)
        
        // ykman status
        ykmanStatusLabel = NSTextField(labelWithString: "Checking ykman...")
        ykmanStatusLabel.font = NSFont.systemFont(ofSize: 12)
        stackView.addArrangedSubview(ykmanStatusLabel)
        
        // Accounts info
        accountsLabel = NSTextField(labelWithString: "Loading accounts...")
        accountsLabel.font = NSFont.systemFont(ofSize: 12)
        stackView.addArrangedSubview(accountsLabel)
        
        // Buttons
        let buttonStack = NSStackView()
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 10
        
        refreshButton = NSButton(title: "Refresh", target: self, action: #selector(refreshStatus))
        refreshButton.bezelStyle = .rounded
        buttonStack.addArrangedSubview(refreshButton)
        
        openSafariButton = NSButton(title: "Open Safari", target: self, action: #selector(openSafari))
        openSafariButton.bezelStyle = .rounded
        buttonStack.addArrangedSubview(openSafariButton)
        
        stackView.addArrangedSubview(buttonStack)
        
        // Set the stack view as the main view
        view = stackView
        view.frame = NSRect(x: 0, y: 0, width: 300, height: 200)
    }
    
    @objc func refreshStatus() {
        checkYkmanStatus()
        loadAccounts()
    }
    
    @objc func openSafari() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.extensions")!)
    }
    
    private func checkYkmanStatus() {
        let task = Process()
        task.launchPath = "/usr/bin/which"
        task.arguments = ["ykman"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            DispatchQueue.main.async {
                if task.terminationStatus == 0 {
                    self.ykmanStatusLabel.stringValue = "✅ ykman is available"
                    self.ykmanStatusLabel.textColor = NSColor.systemGreen
                } else {
                    self.ykmanStatusLabel.stringValue = "❌ ykman not found"
                    self.ykmanStatusLabel.textColor = NSColor.systemRed
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.ykmanStatusLabel.stringValue = "❌ Error checking ykman"
                self.ykmanStatusLabel.textColor = NSColor.systemRed
            }
        }
    }
    
    private func loadAccounts() {
        // For now, just show a placeholder
        DispatchQueue.main.async {
            self.accountsLabel.stringValue = "📱 Checking accounts..."
            self.accountsLabel.textColor = NSColor.systemBlue
        }
        
        // Try to get accounts if ykman is available
        let task = Process()
        task.launchPath = "/opt/homebrew/bin/ykman"
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
                    let accounts = output.components(separatedBy: .newlines).filter { !$0.isEmpty }
                    DispatchQueue.main.async {
                        self.accountsLabel.stringValue = "📱 \(accounts.count) OATH accounts found"
                        self.accountsLabel.textColor = NSColor.systemGreen
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.accountsLabel.stringValue = "❌ No OATH accounts found"
                    self.accountsLabel.textColor = NSColor.systemOrange
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.accountsLabel.stringValue = "❌ Error loading accounts"
                self.accountsLabel.textColor = NSColor.systemRed
            }
        }
    }
}
