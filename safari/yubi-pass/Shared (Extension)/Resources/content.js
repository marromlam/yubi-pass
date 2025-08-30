"use strict";

// Function to generate OTP when context menu is clicked
function generateOTPFromContextMenu() {
  console.log("🔐 YubiPass: Context menu OTP generation triggered");
  
  // Get the currently focused element
  const elem = document.activeElement;
  console.log("🔐 YubiPass: Currently focused element:", elem);
  
  if (!elem || !elem.matches('input, textarea, [contenteditable="true"]')) {
    console.error("🔐 YubiPass: No editable element is currently focused");
    alert("Please focus on an input field first");
    return;
  }
  
  // Extract domain from current URL
  const domain = extractDomain(window.location.href);
  console.log("🔐 YubiPass: Current domain:", domain);
  console.log("🔐 YubiPass: Current URL:", window.location.href);
  
  // Send message to the extension handler
  console.log("🔐 YubiPass: Sending OTP request to Safari extension...");
  browser.runtime.sendNativeMessage("com.yubipass.extension", {
    action: "generateOTP",
    domain: domain,
    targetElementId: "current-focus"
  }).then(response => {
    console.log("🔐 YubiPass: Received response from Safari extension:", response);
    if (response.success) {
      console.log("🔐 YubiPass: OTP generation successful!");
      console.log("🔐 YubiPass: Generated OTP:", response.otp);
    } else {
      console.error("🔐 YubiPass: OTP generation failed:", response.error);
      alert("OTP generation failed: " + response.error);
    }
  }).catch(error => {
    console.error("🔐 YubiPass: Error sending message to Safari extension:", error);
    alert("Error: " + error.message);
  });
}

// Function to extract domain from URL
function extractDomain(url) {
  try {
    const urlObj = new URL(url);
    return urlObj.hostname;
  } catch (error) {
    console.error("Error parsing URL:", error);
    return null;
  }
}

// Make the function globally available for the context menu
window.generateOTPFromContextMenu = generateOTPFromContextMenu;

        // Existing message listener for receiving OTP
        browser.runtime.onMessage.addListener((request) => {
          console.log("🔐 YubiPass: Received OTP message:", request);
          
          if (request.otp) {
            console.log("🔐 YubiPass: Injecting OTP:", request.otp);
            if (request.account) {
              console.log("🔐 YubiPass: Using account:", request.account);
            }
            
            // Get the currently focused element
            const elem = document.activeElement;
            if (elem && elem.matches('input, textarea, [contenteditable="true"]')) {
              // Clear the field first
              elem.value = "";
              
              // Focus the element
              elem.focus();
              
              // Set the value
              elem.value = request.otp;
              
              // Trigger input events to simulate real user input
              const inputEvent = new Event("input", { bubbles: true, cancelable: true });
              const changeEvent = new Event("change", { bubbles: true, cancelable: true });
              elem.dispatchEvent(inputEvent);
              elem.dispatchEvent(changeEvent);
              
              console.log("🔐 YubiPass: OTP successfully injected:", request.otp);
              console.log("🔐 YubiPass: Field value after injection:", elem.value);
              
              // Show success message with account info
              showOTPSuccess(request.otp, request.account);
            } else {
              console.error("🔐 YubiPass: No editable element is currently focused");
              alert("Please focus on an input field first");
            }
          }
        });
        
        // Function to show OTP success message
        function showOTPSuccess(otp, account) {
          // Create a temporary success message
          const successDiv = document.createElement('div');
          successDiv.style.cssText = `
            position: fixed;
            top: 20px;
            right: 20px;
            background: #4CAF50;
            color: white;
            padding: 15px 20px;
            border-radius: 5px;
            font-family: Arial, sans-serif;
            font-size: 14px;
            z-index: 10000;
            box-shadow: 0 4px 8px rgba(0,0,0,0.2);
            max-width: 300px;
            word-wrap: break-word;
          `;
          
          if (account) {
            successDiv.innerHTML = `🔐 OTP Generated: <strong>${otp}</strong><br><small>Account: ${account}</small>`;
          } else {
            successDiv.textContent = `🔐 OTP Generated: ${otp}`;
          }
          
          document.body.appendChild(successDiv);
          
          // Remove after 4 seconds
          setTimeout(() => {
            if (successDiv.parentNode) {
              successDiv.parentNode.removeChild(successDiv);
            }
          }, 4000);
        }

console.log("YubiPass content script loaded - context menu OTP generation available");
