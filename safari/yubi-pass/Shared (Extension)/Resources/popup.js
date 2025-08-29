console.log("Popup script loaded!");

// Test if we can access browser APIs
try {
  console.log("Browser runtime available:", !!browser.runtime);
  console.log("Browser contextMenus available:", !!browser.contextMenus);
  
  document.getElementById('status').textContent = 'Browser APIs available!';
} catch (error) {
  console.error("Error accessing browser APIs:", error);
  document.getElementById('status').textContent = 'Error: ' + error.message;
}

// Test context menu creation
async function testContextMenu() {
  try {
    await browser.contextMenus.create({
      id: "popup-test-menu",
      title: "Popup Test Menu",
      contexts: ["all"]
    });
    console.log("Popup test menu created successfully");
    document.getElementById('status').textContent = 'Test menu created!';
  } catch (error) {
    console.error("Error creating popup test menu:", error);
    document.getElementById('status').textContent = 'Error creating menu: ' + error.message;
  }
}

// Test when popup opens
document.addEventListener('DOMContentLoaded', () => {
  console.log("Popup DOM loaded");
  testContextMenu();
});
