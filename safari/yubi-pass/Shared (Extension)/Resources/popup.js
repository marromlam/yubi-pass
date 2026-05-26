"use strict";

async function getCodes() {
    const data = await browser.storage.local.get("codes");
    return data.codes || [];
}

async function storeCodes(codes) {
    await browser.storage.local.set({ codes });
}

// ── View switching ────────────────────────────────────────────────────────────

function showMainView() {
    document.getElementById("mainView").style.display = "block";
    document.getElementById("settingsView").style.display = "none";
}

function showSettingsView() {
    document.getElementById("mainView").style.display = "none";
    document.getElementById("settingsView").style.display = "block";
    renderMappings();
}

// ── Account list ──────────────────────────────────────────────────────────────

async function loadAccounts() {
    const container = document.getElementById("accountList");
    container.innerHTML = '<div class="spinner-wrap"><div class="spinner"></div></div>';

    try {
        console.log("🔐 POPUP: calling sendNativeMessage directly...");
        const response = await browser.runtime.sendNativeMessage("com.yubipass.extension", { action: "getAccounts" });
        console.log("🔐 POPUP: got response:", JSON.stringify(response));

        if (response && response.success && Array.isArray(response.accounts)) {
            const accounts = response.accounts;
            if (accounts.length === 0) {
                container.innerHTML = '<p class="empty">No accounts found on YubiKey.</p>';
            } else {
                container.innerHTML = accounts
                    .map(name => `<div class="account-item">${escapeHtml(name)}</div>`)
                    .join("");
            }
        } else {
            const msg = (response && response.error) ? response.error : "Could not load accounts.";
            container.innerHTML = `<p class="error-msg">${escapeHtml(msg)}</p>`;
        }
    } catch (e) {
        container.innerHTML = `<p class="error-msg">Error: ${escapeHtml(String(e))}</p>`;
    }
}

// ── Mappings (settings view) ──────────────────────────────────────────────────

async function syncToNativeApp(codes) {
    try {
        await browser.runtime.sendNativeMessage("com.yubipass.extension", { action: "syncCodes", codes });
    } catch (e) {
        console.warn("YubiPass: syncCodes failed:", e);
    }
}

async function renderMappings() {
    const codes = await getCodes();
    const container = document.getElementById("mappingList");

    if (codes.length === 0) {
        container.innerHTML = '<p class="empty">No mappings yet. Add one above.</p>';
        return;
    }

    const table = document.createElement("table");
    table.innerHTML = `<thead><tr><th>Domain</th><th>Account</th><th></th></tr></thead>`;
    const tbody = document.createElement("tbody");

    codes.forEach(({ domain, codeName }) => {
        const tr = document.createElement("tr");
        tr.innerHTML = `<td>${escapeHtml(domain)}</td><td>${escapeHtml(codeName)}</td><td><button class="del-btn" data-name="${escapeHtml(codeName)}">✕</button></td>`;
        tbody.appendChild(tr);
    });

    table.appendChild(tbody);
    container.innerHTML = "";
    container.appendChild(table);
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function escapeHtml(str) {
    return String(str)
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;");
}

// ── Event listeners ───────────────────────────────────────────────────────────

console.log("🔐 POPUP: attaching gear/back listeners, gearBtn=", document.getElementById("gearBtn"), "backBtn=", document.getElementById("backBtn"));
document.getElementById("gearBtn").addEventListener("click", () => { console.log("🔐 POPUP: gear clicked"); showSettingsView(); });
document.getElementById("backBtn").addEventListener("click", () => { console.log("🔐 POPUP: back clicked"); showMainView(); });

document.getElementById("addMappingForm").addEventListener("submit", async (e) => {
    e.preventDefault();
    const domain = document.getElementById("urlInput").value.trim();
    const codeName = document.getElementById("aliasInput").value.trim();
    const codes = await getCodes();
    const updated = [...codes, { domain, codeName }];
    await storeCodes(updated);
    await syncToNativeApp(updated);
    e.target.reset();
    await renderMappings();
});

document.getElementById("mappingList").addEventListener("click", async (e) => {
    if (!e.target.classList.contains("del-btn")) return;
    const name = e.target.getAttribute("data-name");
    const codes = await getCodes();
    const updated = codes.filter(c => c.codeName !== name);
    await storeCodes(updated);
    await syncToNativeApp(updated);
    await renderMappings();
});

// ── Init ──────────────────────────────────────────────────────────────────────

loadAccounts();
