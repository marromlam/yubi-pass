"use strict";

// Listen for OTP injection messages from background script
browser.runtime.onMessage.addListener((request) => {
  if (request.otp) {
    const elem = document.activeElement;
    
    if (elem && elem.matches('input, textarea, [contenteditable="true"]')) {
      elem.value = "";
      elem.focus();
      elem.value = request.otp;
      
      // Trigger events for form validation
      elem.dispatchEvent(new Event("input", { bubbles: true, cancelable: true }));
      elem.dispatchEvent(new Event("change", { bubbles: true, cancelable: true }));
      
      // Show success notification
      if (request.account) {
        showNotification(`OTP Generated: ${request.otp}`, `Account: ${request.account}`, 'success');
      } else {
        showNotification(`OTP Generated: ${request.otp}`, '', 'success');
      }
    } else {
      showNotification('Error', 'Please focus on an input field first', 'error');
    }
  }
});

// Show notification
function showNotification(title, subtitle, type) {
  const existingNotification = document.getElementById('yubipass-notification');
  if (existingNotification) {
    existingNotification.remove();
  }
  
  const notification = document.createElement('div');
  notification.id = 'yubipass-notification';
  notification.style.cssText = `
    position: fixed;
    top: 20px;
    right: 20px;
    background: ${type === 'success' ? '#4CAF50' : '#f44336'};
    color: white;
    padding: 15px 20px;
    border-radius: 8px;
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    font-size: 14px;
    z-index: 10000;
    box-shadow: 0 4px 12px rgba(0,0,0,0.3);
    max-width: 300px;
    animation: slideIn 0.3s ease-out;
  `;
  
  notification.innerHTML = `
    <strong>${title}</strong>
    ${subtitle ? `<br><small>${subtitle}</small>` : ''}
  `;
  
  document.body.appendChild(notification);
  
  setTimeout(() => {
    if (notification.parentNode) {
      notification.style.animation = 'slideOut 0.3s ease-out';
      setTimeout(() => notification.remove(), 300);
    }
  }, 3000);
}

// Add CSS animations
const style = document.createElement('style');
style.textContent = `
  @keyframes slideIn {
    from { transform: translateX(400px); opacity: 0; }
    to { transform: translateX(0); opacity: 1; }
  }
  @keyframes slideOut {
    from { transform: translateX(0); opacity: 1; }
    to { transform: translateX(400px); opacity: 0; }
  }
`;
document.head.appendChild(style);

