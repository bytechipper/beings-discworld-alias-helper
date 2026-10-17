const byId = id => document.getElementById(id);
const search = byId("search");
const contentSearch = byId("content-search");
const editor = byId("editor");
const nameInput = byId("alias-name");
const contentInput = byId("alias-content");
const categoryFilter = byId("category-filter");
const categoryInput = byId("alias-category");
let state = { character: null, recording: false, aliases: [] };
let editing = null;
let pending = null;
let sequence = 0;

function error(message) {
    byId("editor-error").textContent = message;
    byId("editor-error").hidden = !message;
}

function confirmation(show) {
    byId("delete-confirmation").hidden = !show;
    byId("editor-actions").hidden = show;
    nameInput.disabled = show;
    contentInput.disabled = show;
    categoryInput.disabled = show;
    if (show) byId("cancel-delete").focus();
}

function openEditor(entry, trigger) {
    editing = {
        character: state.character,
        original: entry ? { content: entry.content, category: entry.category } : null,
        trigger,
    };
    nameInput.value = entry ? entry.name : "";
    nameInput.readOnly = !!entry;
    contentInput.value = entry ? entry.content : "";
    byId("editor-title").textContent = entry ? "Edit alias" : "Add new alias";
    categoryInput.value = entry ? entry.category : (categoryFilter.value || "default");
    byId("delete").hidden = !entry;
    confirmation(false);
    error("");
    editor.showModal();
    (entry ? contentInput : nameInput).focus();
}

function render() {
    const categories = new Map([["default", 0]]);
    for (const entry of state.aliases) categories.set(entry.category, (categories.get(entry.category) || 0) + 1);
    const selected = categoryFilter.value;
    categoryFilter.replaceChildren(new Option("All categories", ""));
    byId("category-options").replaceChildren();
    for (const category of [...categories.keys()].sort()) {
        categoryFilter.appendChild(new Option(category + " (" + categories.get(category) + ")", category));
        byId("category-options").appendChild(new Option(category, category));
    }
    categoryFilter.value = categories.has(selected) ? selected : "";
    const query = search.value.toLocaleLowerCase();
    const contentQuery = contentSearch.value.toLocaleLowerCase();
    const filtered = query || contentQuery || categoryFilter.value;
    const matches = state.aliases.filter(entry =>
        entry.name.toLocaleLowerCase().includes(query) && entry.content.toLocaleLowerCase().includes(contentQuery)
        && (!categoryFilter.value || entry.category === categoryFilter.value));
    byId("count").textContent = filtered ? matches.length + " / " + state.aliases.length : state.aliases.length;
    byId("empty").hidden = matches.length > 0;
    byId("empty").textContent = filtered ? "No matching aliases." : "No aliases recorded yet.";
    const list = byId("aliases");
    list.replaceChildren();
    for (const entry of matches) {
        const row = document.createElement("li");
        const button = document.createElement("button");
        button.type = "button";
        button.className = "alias-entry";
        const name = document.createElement("span");
        name.className = "alias-name";
        name.textContent = entry.name;
        const category = document.createElement("span");
        category.className = "alias-category";
        category.textContent = entry.category;
        button.append(name, category);
        button.setAttribute("aria-label", entry.name);
        button.title = "Edit " + entry.name + " · " + entry.category;
        button.disabled = !state.character;
        button.addEventListener("click", () => openEditor(entry, button));
        row.appendChild(button);
        list.appendChild(row);
    }
    byId("character").textContent = state.character ? "Character: " + state.character : "Waiting for login…";
    byId("status").textContent = state.recording ? "Recording" : "Stopped";
    byId("status").className = state.recording ? "recording" : "hint";
    byId("start").disabled = !state.character || state.recording;
    byId("stop").disabled = !state.recording;
    byId("add").disabled = !state.character;
}

function sendChange(action) {
    if (!editing || pending) return;
    const name = nameInput.value;
    const content = contentInput.value;
    const category = categoryInput.value.trim();
    if (!name || /[\s\x00-\x1f\x7f:]/u.test(name)) {
        error("Enter a name without spaces, control characters or colons.");
        return;
    }
    if (action === "save" && (!content.trim() || /[\x00-\x1f\x7f]/u.test(content))) {
        error("Enter non-empty content on one line; separate commands with semicolons.");
        return;
    }
    if (action === "save" && (!category || /[\x00-\x1f\x7f";\\]/u.test(category))) {
        error("Enter a category without quotes, backslashes, semicolons or control characters.");
        return;
    }
    error("");
    pending = String(++sequence);
    editor.querySelectorAll("button").forEach(button => { button.disabled = true; });
    nameInput.disabled = true;
    contentInput.disabled = true;
    categoryInput.disabled = true;
    const data = { request_id: pending, character: editing.character, name };
    if (editing.original) data.original = editing.original;
    if (action === "save") { data.content = content; data.category = category; }
    else data.confirmed = true;
    window.panel.post(action, data);
}

window.panel.on("update", data => {
    if (editing && data.character !== editing.character) {
        pending = null;
        editor.close();
    }
    if (state.character !== data.character) {
        byId("notice").hidden = true;
        categoryFilter.value = "";
    }
    state = { ...data, aliases: Array.isArray(data.aliases) ? data.aliases : [] };
    render();
});
window.panel.on("result", data => {
    if (!pending || data.request_id !== pending) return;
    pending = null;
    editor.querySelectorAll("button").forEach(button => { button.disabled = false; });
    confirmation(false);
    if (data.ok) {
        byId("notice").textContent = data.message;
        byId("notice").hidden = false;
        editor.close();
    } else error(data.message);
});

search.addEventListener("input", render);
contentSearch.addEventListener("input", render);
categoryFilter.addEventListener("change", render);
byId("clear-search").addEventListener("click", () => { search.value = ""; render(); search.focus(); });
byId("clear-content-search").addEventListener("click", () => { contentSearch.value = ""; render(); contentSearch.focus(); });
byId("start").addEventListener("click", () => window.panel.post("start", {}));
byId("stop").addEventListener("click", () => window.panel.post("stop", {}));
byId("add").addEventListener("click", event => openEditor(null, event.currentTarget));
byId("close").addEventListener("click", () => editor.close());
byId("alias-form").addEventListener("submit", event => { event.preventDefault(); sendChange("save"); });
byId("delete").addEventListener("click", () => {
    error("");
    byId("delete-question").textContent = 'Are you sure you want to delete "' + nameInput.value + '" from the MUD?';
    confirmation(true);
});
byId("cancel-delete").addEventListener("click", () => { confirmation(false); byId("delete").focus(); });
byId("confirm-delete").addEventListener("click", () => sendChange("delete"));
editor.addEventListener("cancel", event => { if (pending) event.preventDefault(); });
editor.addEventListener("close", () => {
    const trigger = editing && editing.trigger;
    editing = null;
    editor.querySelectorAll("button").forEach(button => { button.disabled = false; });
    if (trigger && trigger.isConnected) trigger.focus();
    else byId("add").focus();
});
window.panel.post("ready", {});
