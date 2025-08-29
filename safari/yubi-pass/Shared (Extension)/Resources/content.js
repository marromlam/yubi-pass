"use strict";

browser.runtime.onMessage.addListener((request) => {
  let elem;
  
  if (request.targetElementId === "current-focus") {
    // Get the currently focused element
    elem = document.activeElement;
    
    // Check if it's an input field
    if (!elem || !elem.matches('input, textarea, [contenteditable="true"]')) {
      console.error("No editable element is currently focused");
      return;
    }
  } else {
    // Fallback to ID-based lookup
    elem = document.getElementById(request.targetElementId) || 
           document.querySelector(`[data-yubi-pass-id="${request.targetElementId}"]`);
    
    if (!elem) {
      console.error("Target element not found:", request.targetElementId);
      return;
    }
  }

  // Clear the field first
  elem.value = "";

  // Focus the element
  elem.focus();

  // Set the value
  elem.value = request.otp;

  // Trigger input events to simulate real user input
  const inputEvent = new Event("input", { bubbles: true, cancelable: true });
  const changeEvent = new Event("change", { bubbles: true, cancelable: true });
  const keyupEvent = new KeyboardEvent("keyup", {
    bubbles: true,
    cancelable: true,
    key: "Digit" + request.otp.slice(-1),
  });

  elem.dispatchEvent(inputEvent);
  elem.dispatchEvent(changeEvent);
  elem.dispatchEvent(keyupEvent);
});
