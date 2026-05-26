"use strict";

// Global error handler to catch crashes
self.addEventListener('error', (event) => {
  console.error("YubiPass Error:", event.error);
});

self.addEventListener('unhandledrejection', (event) => {
  console.error("YubiPass Unhandled Promise Rejection:", event.reason);
});

// Sync codes to native app whenever storage changes
let restoringMappings = false;
browser.storage.onChanged.addListener((changes, area) => {
  if (area === "local" && changes.codes && !restoringMappings) {
    syncCodesToNativeApp(changes.codes.newValue || []);
  }
});

async function syncCodesToNativeApp(codes) {
  try {
    await browser.runtime.sendNativeMessage("com.yubipass.extension", {
      action: "syncCodes",
      codes: codes
    });
  } catch (error) {
    console.error("YubiPass: Failed to sync codes to native app:", error);
  }
}

// Restore mappings from native app storage if extension storage is empty
async function restoreMappingsIfNeeded() {
  const data = await browser.storage.local.get("codes");
  if (data.codes && data.codes.length > 0) return;
  
  try {
    const response = await browser.runtime.sendNativeMessage("com.yubipass.extension", { action: "getMappings" });
    if (response && response.success && Array.isArray(response.codes) && response.codes.length > 0) {
      restoringMappings = true;
      await browser.storage.local.set({ codes: response.codes });
      restoringMappings = false;
    }
  } catch (error) {
    // Silent fail - no mappings to restore
  }
}

// Delay restore so Safari's native messaging host is fully ready
setTimeout(restoreMappingsIfNeeded, 500);

// Create context menu
const menuId = "generate-otp";

browser.contextMenus.create({
  id: menuId,
  title: "Generate OTP",
  contexts: ["editable"]
}, () => {
  if (browser.runtime.lastError) {
    if (!browser.runtime.lastError.message.includes("exist") && 
        !browser.runtime.lastError.message.includes("duplicate")) {
      console.error("YubiPass: Error creating context menu:", browser.runtime.lastError.message);
    }
  }
});

browser.contextMenus.onClicked.addListener((info, tab) => {
  if (info.menuItemId === "generate-otp") {
    generateOtp(info, tab);
  }
});

// Function to generate and inject OTP
async function generateOtp(info, tab) {
  try {
    let domain = extractDomain(tab.url);
    let otp = await generateOtpViaExtension(domain);
    
    if (otp && otp !== "NO_KEY_FOUND" && otp !== "ERROR" && otp !== "TIMEOUT") {
      await injectOtp({ tabId: tab.id, frameId: info.frameId || 0 }, otp);
    } else {
      await showError(otp);
    }
  } catch (error) {
    console.error("YubiPass: Error generating OTP:", error);
    await showError("NETWORK_ERROR");
  }
}

function extractDomain(url) {
  try {
    let urlObj = new URL(url);
    return urlObj.hostname;
  } catch (error) {
    console.error("Error parsing URL:", error);
    return null;
  }
}

async function generateOtpViaExtension(domain) {
  try {
    const response = await browser.runtime.sendNativeMessage("com.yubipass.extension", {
      action: "generateOTP",
      domain: domain
    });
    
    if (response && response.success) {
      return response.otp;
    } else {
      return response?.error || "ERROR";
    }
  } catch (error) {
    console.error("YubiPass: Error calling native extension:", error);
    return "ERROR";
  }
}

async function showError(errorType) {
  let message = "Unknown error";
  
  switch (errorType) {
    case "NO_KEY_FOUND":
      message = "No TOTP key found for this domain. Please configure it in your YubiPass settings.";
      break;
    case "SERVER_OFFLINE":
      message = "YubiPass server is not running. Please start the server first.";
      break;
    case "TIMEOUT":
      message = "OTP generation timed out. Please try again.";
      break;
    case "ERROR":
      message = "Error generating OTP. Please check your YubiKey connection.";
      break;
    case "NETWORK_ERROR":
      message = "Network error. Please check your connection.";
      break;
  }
  
  // Execute script to show error in the page
  try {
    await browser.scripting.executeScript({
      target: { tabId: (await browser.tabs.query({active: true, currentWindow: true}))[0].id },
      func: showErrorMessage,
      args: [message]
    });
  } catch (error) {
    console.error("Error showing error message:", error);
  }
}

// Function to be injected to show error message
function showErrorMessage(message) {
  // Remove any existing error message
  const existingError = document.getElementById('yubi-pass-error');
  if (existingError) {
    existingError.remove();
  }
  
  // Create error message element
  const errorDiv = document.createElement('div');
  errorDiv.id = 'yubi-pass-error';
  errorDiv.style.cssText = `
    position: fixed;
    top: 20px;
    right: 20px;
    background: #dc3545;
    color: white;
    padding: 15px 20px;
    border-radius: 8px;
    box-shadow: 0 4px 12px rgba(0,0,0,0.3);
    z-index: 10000;
    max-width: 400px;
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    font-size: 14px;
    line-height: 1.4;
  `;
  
  errorDiv.textContent = message;
  
  // Add close button
  const closeBtn = document.createElement('button');
  closeBtn.textContent = '×';
  closeBtn.style.cssText = `
    position: absolute;
    top: 5px;
    right: 10px;
    background: none;
    border: none;
    color: white;
    font-size: 18px;
    cursor: pointer;
    padding: 0;
    width: 20px;
    height: 20px;
    display: flex;
    align-items: center;
    justify-content: center;
  `;
  
  closeBtn.onclick = () => errorDiv.remove();
  errorDiv.appendChild(closeBtn);
  
  // Add to page
  document.body.appendChild(errorDiv);
  
  // Auto-remove after 8 seconds
  setTimeout(() => {
    if (errorDiv.parentNode) {
      errorDiv.remove();
    }
  }, 8000);
}

async function injectOtp(targetParams, otp) {
  try {
    await browser.scripting.executeScript({
      target: { tabId: targetParams.tabId, frameIds: [targetParams.frameId] },
      func: injectOtpIntoField,
      args: [otp]
    });
  } catch (error) {
    console.error("YubiPass: Error injecting OTP:", error);
  }
}

// Function to be injected into the page
function injectOtpIntoField(otp) {
  const elem = document.activeElement;
  
  if (!elem || !elem.matches('input, textarea, [contenteditable="true"]')) {
    return;
  }
  
  elem.value = "";
  elem.focus();
  elem.value = otp;
  
  // Trigger events to ensure form validation works
  elem.dispatchEvent(new Event("input", { bubbles: true, cancelable: true }));
  elem.dispatchEvent(new Event("change", { bubbles: true, cancelable: true }));
  elem.dispatchEvent(new KeyboardEvent("keyup", {
    bubbles: true,
    cancelable: true,
    key: "Digit" + otp.slice(-1),
  }));
}

// Relay messages from popup to native app
browser.runtime.onMessage.addListener((request, sender, sendResponse) => {
  if (request.action === "getAccounts") {
    (async () => {
      try {
        const response = await browser.runtime.sendNativeMessage("com.yubipass.extension", { action: "getAccounts" });
        sendResponse(response);
      } catch (err) {
        sendResponse({ success: false, error: String(err) });
      }
    })();
    return true;
  }
  
  if (request.action === "syncCodes") {
    (async () => {
      try {
        const response = await browser.runtime.sendNativeMessage("com.yubipass.extension", { 
          action: "syncCodes", 
          codes: request.codes 
        });
        sendResponse(response);
      } catch (err) {
        sendResponse({ success: false, error: String(err) });
      }
    })();
    return true;
  }
});

