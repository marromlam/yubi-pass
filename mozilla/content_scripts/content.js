"use strict";

browser.runtime.onMessage.addListener((request) => {
  let elem = browser.menus.getTargetElement(request.targetElementId);

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
