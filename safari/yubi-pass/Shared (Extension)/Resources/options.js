"use strict";

import { getCodes, storeCodes } from "./utils/storage.js";

async function syncToNativeApp(codes) {
    try {
        await browser.runtime.sendNativeMessage("com.yubipass.extension", {
            action: "syncCodes",
            codes: codes
        });
    } catch (e) {
        console.warn("YubiPass: syncCodes failed:", e);
    }
}

async function loadCurrentOptions() {
    document.querySelector("#addCodeForm").reset();
    let codes = await getCodes();
    // Sync on load so native app always has latest mappings
    await syncToNativeApp(codes);
    let table = buildTable(codes);
    let codesNode = document.querySelector("#currentCodes");
    codesNode.textContent = "";
    codesNode.appendChild(table);
}

async function saveOptions(e) {
    e.preventDefault();
    let codes = await getCodes();
    let newCode = {
        domain: document.querySelector("#domain").value,
        codeName: document.querySelector("#codeName").value
    };
    let updated = [...codes, newCode];
    await storeCodes(updated);
    await syncToNativeApp(updated);
    await loadCurrentOptions();
}

async function removeCode(e) {
    if (e.target.className != "remove-btn") {
        return;
    }
    let codeToRemove = e.target.getAttribute("data-codename");
    let codes = await getCodes();
    let filtered = codes.filter(code => code.codeName != codeToRemove);
    await storeCodes(filtered);
    await syncToNativeApp(filtered);
    await loadCurrentOptions();
}

function buildTable(codes) {
    if (codes.length === 0) {
        let noCodesDiv = document.createElement("div");
        noCodesDiv.className = "no-codes";
        noCodesDiv.textContent = "No TOTP codes configured yet. Add your first one above!";
        return noCodesDiv;
    }

    let table = document.createElement("table");

    let thead = document.createElement("thead");
    let headerRow = document.createElement("tr");
    headerRow.appendChild(createElement("th", "Domain"));
    headerRow.appendChild(createElement("th", "TOTP Code Name"));
    headerRow.appendChild(createElement("th", "Actions"));
    thead.appendChild(headerRow);
    table.appendChild(thead);

    let tbody = document.createElement("tbody");
    codes.forEach(item => {
        tbody.appendChild(buildRow(item));
    });
    table.appendChild(tbody);

    return table;
}

function buildRow(codeSetting) {
    let row = document.createElement("tr");
    row.appendChild(createElement("td", codeSetting.domain));
    row.appendChild(createElement("td", codeSetting.codeName));

    let removeBtn = createElement("button", "Remove", {
        "class": "remove-btn",
        "data-codename": codeSetting.codeName
    });
    let td = createElement("td");
    td.appendChild(removeBtn);
    row.appendChild(td);

    return row;
}

function createElement(tagName, text = null, attributes = {}) {
    let element = document.createElement(tagName);
    if (text != null) {
        element.textContent = text;
    }
    for (const [key, value] of Object.entries(attributes)) {
        element.setAttribute(key, value);
    }
    return element;
}

document.addEventListener("DOMContentLoaded", loadCurrentOptions);
document.querySelector("#addCodeForm").addEventListener("submit", saveOptions);
document.querySelector("#currentCodes").addEventListener("click", removeCode);
