"use strict";

console.log("Background script loaded!");

// Create just one OTP context menu item
try {
  browser.contextMenus.create({
    id: "generate-otp",
    title: "Generate OTP",
    contexts: ["editable"]
  });
  console.log("OTP context menu created successfully");
} catch (error) {
  console.error("Error creating OTP context menu:", error);
}

// Listen for context menu clicks
browser.contextMenus.onClicked.addListener((info, tab) => {
  console.log("Context menu clicked:", info.menuItemId);
  
  if (info.menuItemId === "generate-otp") {
    console.log("Generate OTP clicked!");
    generateOtp(info, tab);
  }
});

// Function to generate and inject OTP
async function generateOtp(info, tab) {
  try {
    console.log("Generating OTP for:", info, tab);
    
    // Get the target element info
    let targetParams = {
      tabId: tab.id,
      frameId: info.frameId || 0,
      targetElementId: "current-focus"
    };
    
    // Get the domain from the URL
    let domain = extractDomain(tab.url);
    console.log("Domain:", domain);
    
    // Generate OTP using Safari extension native messaging
    let otp = await generateOtpViaExtension(domain);
    
    if (otp && otp !== "NO_KEY_FOUND" && otp !== "ERROR" && otp !== "TIMEOUT") {
      console.log("🔐 YubiPass Background: OTP generation successful!");
      console.log("🔐 YubiPass Background: Generated OTP:", otp);
      
      // Check if we have account information
      if (typeof otp === 'object' && otp.account) {
        console.log("🔐 YubiPass Background: Using account:", otp.account);
        console.log("🔐 YubiPass Background: Final OTP:", otp.otp);
      }
      
      console.log("🔐 YubiPass Background: Injecting OTP into page...");
      
      // Inject the OTP into the focused field
      await injectOtp(targetParams, otp);
    } else {
      console.error("🔐 YubiPass Background: Failed to generate OTP:", otp);
      // Show error to user
      await showError(otp);
    }
    
  } catch (error) {
    console.error("Error in generateOtp:", error);
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
    console.log("🔐 YubiPass Background: Requesting OTP via Safari extension for domain:", domain);
    
    // Send message to the Safari extension handler
    const response = await browser.runtime.sendNativeMessage("com.yubipass.extension", {
      action: "generateOTP",
      domain: domain
    });
    
    console.log("🔐 YubiPass Background: Safari extension response:", response);
    
    if (response && response.success) {
      console.log("🔐 YubiPass Background: OTP generation successful!");
      console.log("🔐 YubiPass Background: Final OTP:", response.otp);
      return response.otp;
    } else {
      console.error("🔐 YubiPass Background: OTP generation failed!");
      console.error("🔐 YubiPass Background: Error details:", response?.error || "Unknown error");
      return response?.error || "ERROR";
    }
    
  } catch (error) {
    console.error("🔐 YubiPass Background: Error calling Safari extension:", error);
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
    console.log("🔐 YubiPass Background: Injecting OTP:", targetParams, otp);
    
    // Execute the content script to inject the OTP
    await browser.scripting.executeScript({
      target: { tabId: targetParams.tabId, frameIds: [targetParams.frameId] },
      func: injectOtpIntoField,
      args: [otp]
    });
    
    console.log("🔐 YubiPass Background: OTP injected successfully!");
    
  } catch (error) {
    console.error("🔐 YubiPass Background: Error injecting OTP:", error);
  }
}

// Function to be injected into the page
function injectOtpIntoField(otp) {
  console.log("🔐 YubiPass Content: Injecting OTP into field:", otp);
  
  // Get the currently focused element
  let elem = document.activeElement;
  console.log("🔐 YubiPass Content: Target element:", elem);
  
  // Check if it's an input field
  if (!elem || !elem.matches('input, textarea, [contenteditable="true"]')) {
    console.error("🔐 YubiPass Content: No editable element is currently focused");
    return;
  }
  
  console.log("🔐 YubiPass Content: Injecting OTP into element:", elem);
  console.log("🔐 YubiPass Content: Element type:", elem.type);
  console.log("🔐 YubiPass Content: Element name:", elem.name);
  console.log("🔐 YubiPass Content: Element id:", elem.id);
  
  // Clear the field first
  elem.value = "";
  
  // Focus the element
  elem.focus();
  
  // Set the value
  elem.value = otp;
  
  // Trigger input events to simulate real user input
  const inputEvent = new Event("input", { bubbles: true, cancelable: true });
  const changeEvent = new Event("change", { bubbles: true, cancelable: true });
  const keyupEvent = new KeyboardEvent("keyup", {
    bubbles: true,
    cancelable: true,
    key: "Digit" + otp.slice(-1),
  });
  
  elem.dispatchEvent(inputEvent);
  elem.dispatchEvent(changeEvent);
  elem.dispatchEvent(keyupEvent);
  
  console.log("🔐 YubiPass Content: OTP successfully injected into field:", otp);
  console.log("🔐 YubiPass Content: Field value after injection:", elem.value);
}

console.log("Background script setup complete");
