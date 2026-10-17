"""Exercise the panel through a mocked Mallard bridge in Chromium."""
from pathlib import Path
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parent.parent
DATA = {
    "character": "being", "recording": False,
    "aliases": [
        {"name": "rate_check", "content": "rate $*$ in example-city", "category": "default"},
        {"name": "groom_mount", "content": "retrieve grooming kit from $arg:ExampleMount$;groom $arg:ExampleMount$;look;", "category": "pet-horse"},
        {"name": "pursue_target", "content": "pursue $arg:opponents$", "category": "default"},
        {"name": "wrap_output", "content": "cols 201;$ifarg:$*$;unwrap$endif$", "category": "default"},
    ],
}

with sync_playwright() as playwright:
    browser = playwright.chromium.launch(headless=True, args=["--no-sandbox"])
    page = browser.new_page(viewport={"width": 360, "height": 480}, device_scale_factor=2)
    errors = []
    page.on("pageerror", lambda error: errors.append(str(error)))
    page.add_init_script("""
        window.messages = [];
        window.handlers = {};
        window.panel = {
            on: (name, fn) => { window.handlers[name] = fn; },
            post: (name, data) => { window.messages.push({name, data}); }
        };
    """)
    page.goto((ROOT / "ui/panel.html").as_uri())

    def update(data=DATA):
        page.evaluate("data => window.handlers.update(data)", data)

    def messages(action):
        return page.evaluate("action => window.messages.filter(m => m.name === action)", action)

    def reply(ok=True, message="Command sent. Check the MUD output for confirmation."):
        request = page.evaluate("window.messages.at(-1).data.request_id")
        page.evaluate("data => window.handlers.result(data)", {
            "request_id": request, "ok": ok, "message": message,
        })

    assert messages("ready") == [{"name": "ready", "data": {}}]
    assert page.locator("#add").is_disabled()
    update()
    assert page.locator(".alias-entry").count() == 4
    assert page.locator(".alias-category").all_text_contents() == ["default", "pet-horse", "default", "default"]
    assert page.locator("#category-filter option").all_text_contents() == ["All categories", "default (3)", "pet-horse (1)"]
    assert page.locator("#stop").is_disabled()
    page.locator("#start").click()
    assert messages("start")[-1] == {"name": "start", "data": {}}
    update({**DATA, "recording": True})
    assert page.locator("#start").is_disabled()
    page.locator("#stop").click()
    assert messages("stop")[-1] == {"name": "stop", "data": {}}
    update()

    # Name and content searches are independent, case-insensitive literal filters.
    page.get_by_role("searchbox", name="Search alias names").fill("RATE_CHECK")
    assert page.locator(".alias-name").all_text_contents() == ["rate_check"]
    page.locator("#search").fill("ExampleMount")
    assert page.locator(".alias-entry").count() == 0
    page.locator("#clear-search").click()
    page.get_by_role("searchbox", name="Search alias content").fill("EXAMPLEMOUNT")
    assert page.locator(".alias-name").all_text_contents() == ["groom_mount"]
    assert page.locator("#count").inner_text() == "1 / 4"
    page.locator("#search").fill("GROOM")
    update()
    assert page.locator(".alias-name").all_text_contents() == ["groom_mount"]
    assert page.locator("#search").input_value() == "GROOM"
    assert page.locator("#content-search").input_value() == "EXAMPLEMOUNT"
    page.locator("#search").fill("pursue_target")
    assert page.locator(".alias-entry").count() == 0
    assert page.locator("#empty").inner_text() == "No matching aliases."
    page.locator("#clear-search").click()
    assert page.locator("#content-search").input_value() == "EXAMPLEMOUNT"
    assert page.locator(".alias-name").all_text_contents() == ["groom_mount"]
    page.locator("#content-search").fill("$arg:")
    assert page.locator(".alias-name").all_text_contents() == ["groom_mount", "pursue_target"]
    page.locator("#search").fill("pursue_target")
    page.locator("#clear-content-search").click()
    assert page.locator("#search").input_value() == "pursue_target"
    assert page.locator(".alias-name").all_text_contents() == ["pursue_target"]
    page.locator("#clear-search").click()
    page.locator("#content-search").fill("missing")
    assert page.locator("#empty").inner_text() == "No matching aliases."
    page.locator("#clear-content-search").click()
    page.locator("#search").fill("missing")
    assert page.locator("#empty").inner_text() == "No matching aliases."
    page.locator("#clear-search").click()
    assert page.locator(".alias-entry").count() == 4

    # Category selection combines with both searches and persists across updates.
    page.get_by_label("Category", exact=True).first.select_option("pet-horse")
    assert page.locator(".alias-name").all_text_contents() == ["groom_mount"]
    assert page.locator("#count").inner_text() == "1 / 4"
    page.locator("#content-search").fill("ExampleMount")
    page.locator("#search").fill("groom")
    update()
    assert page.locator("#category-filter").input_value() == "pet-horse"
    assert page.locator(".alias-name").all_text_contents() == ["groom_mount"]
    page.locator("#search").fill("pursue_target")
    assert page.locator(".alias-entry").count() == 0
    page.locator("#clear-search").click()
    assert page.locator("#category-filter").input_value() == "pet-horse"
    page.locator("#clear-content-search").click()
    page.locator("#add").click()
    assert page.locator("#alias-category").input_value() == "pet-horse"
    page.keyboard.press("Escape")
    page.locator("#category-filter").select_option("default")
    assert page.locator(".alias-name").all_text_contents() == ["rate_check", "pursue_target", "wrap_output"]
    page.locator("#category-filter").select_option("")

    # A row opens an editor; refreshes never overwrite a draft.
    page.get_by_role("button", name="groom_mount", exact=True).click()
    assert page.locator("#editor").is_visible()
    assert page.locator("#alias-name").get_attribute("readonly") is not None
    assert page.locator("#alias-content").input_value() == DATA["aliases"][1]["content"]
    assert page.locator("#alias-category").input_value() == "pet-horse"
    assert page.locator("#category-options option").evaluate_all("options => options.map(option => option.value)") == ["default", "pet-horse"]
    draft = r"groom $arg:ExampleMount$;say \$me\$;look;"
    page.locator("#alias-content").fill(draft)
    update()
    assert page.locator("#alias-content").input_value() == draft
    page.locator("#save").click()
    save = messages("save")[-1]["data"]
    assert save["name"] == "groom_mount" and save["content"] == draft
    assert save["character"] == "being"
    assert save["category"] == "pet-horse"
    assert save["original"] == {"content": DATA["aliases"][1]["content"], "category": "pet-horse"}
    assert page.locator("#save").is_disabled()
    # Backend errors preserve the draft and re-enable editing.
    reply(False, "This alias changed since you opened it.")
    assert page.locator("#editor-error").is_visible()
    assert page.locator("#alias-content").input_value() == draft
    assert page.locator("#save").is_enabled()
    page.locator("#save").click()
    reply()
    assert not page.locator("#editor").is_visible()
    assert "Command sent" in page.locator("#notice").inner_text()

    # Moving an alias updates its label and available category choices.
    page.get_by_role("button", name="groom_mount", exact=True).click()
    page.locator("#alias-category").fill("sailing")
    update()
    assert page.locator("#alias-category").input_value() == "sailing"
    page.locator("#save").click()
    assert messages("save")[-1]["data"]["category"] == "sailing"
    moved = {**DATA, "aliases": [{**entry, "category": "sailing"} if entry["name"] == "groom_mount" else entry for entry in DATA["aliases"]]}
    update(moved)
    reply()
    assert page.get_by_role("button", name="groom_mount", exact=True).locator(".alias-category").inner_text() == "sailing"
    assert page.locator("#category-filter option").all_text_contents() == ["All categories", "default (3)", "sailing (1)"]
    page.locator("#category-filter").select_option("sailing")
    update()  # The last alias left this category; restore All categories.
    assert page.locator("#category-filter").input_value() == ""

    # New alias starts empty. Newlines are rejected before any bridge message.
    page.locator("#add").click()
    assert page.locator("#alias-name").input_value() == ""
    assert page.locator("#alias-content").input_value() == ""
    assert page.locator("#alias-category").input_value() == "default"
    assert not page.locator("#delete").is_visible()
    page.locator("#alias-name").fill("newalias")
    page.locator("#alias-content").fill("say hi\nquit")
    count = len(messages("save"))
    page.locator("#save").click()
    assert len(messages("save")) == count
    assert "one line" in page.locator("#editor-error").inner_text()
    page.locator("#alias-content").fill("say hi;look $*$")
    page.locator("#alias-category").fill('bad"category')
    page.locator("#save").click()
    assert len(messages("save")) == count
    assert "category" in page.locator("#editor-error").inner_text()
    page.locator("#alias-category").fill("new category")
    page.locator("#save").click()
    save = messages("save")[-1]["data"]
    assert save["name"] == "newalias" and "original" not in save
    assert save["category"] == "new category"
    reply()

    # Delete requires a second click; cancelling never sends an unalias.
    page.get_by_role("button", name="pursue_target", exact=True).click()
    count = len(messages("delete"))
    page.locator("#delete").click()
    assert page.locator("#alias-category").is_disabled()
    assert "Are you sure" in page.locator("#delete-question").inner_text()
    assert len(messages("delete")) == count
    page.locator("#cancel-delete").click()
    assert page.locator("#alias-content").is_enabled()
    assert page.locator("#alias-category").is_enabled()
    page.locator("#delete").click()
    page.locator("#confirm-delete").click()
    deletion = messages("delete")[-1]["data"]
    assert deletion["name"] == "pursue_target" and deletion["confirmed"] is True
    assert "content" not in deletion
    reply()

    # A character switch invalidates even an open unsaved editor.
    page.locator("#category-filter").select_option("pet-horse")
    page.get_by_role("button", name="groom_mount", exact=True).click()
    update({"character": None, "recording": False, "aliases": []})
    assert not page.locator("#editor").is_visible()
    assert page.locator("#add").is_disabled()
    assert not page.locator("#notice").is_visible()
    # A pending request interrupted by disconnect must not leave buttons disabled.
    update()
    assert page.locator("#category-filter").input_value() == ""
    page.locator("#add").click()
    page.locator("#alias-name").fill("test")
    page.locator("#alias-content").fill("look")
    page.locator("#save").click()
    update({"character": None, "recording": False, "aliases": []})
    update()
    page.locator("#add").click()
    assert page.locator("#save").is_enabled()
    page.keyboard.press("Escape")

    # Alias text is data, including HTML-looking names and content.
    update({**DATA, "aliases": [{"name": "<img>", "content": "<script>throw 1</script>", "category": "default"}]})
    assert page.locator("#aliases img").count() == 0
    page.locator(".alias-entry").click()
    assert page.locator("#alias-content").input_value() == "<script>throw 1</script>"
    page.keyboard.press("Escape")

    # Narrow panels and short popouts remain usable without horizontal overflow.
    update()
    for width, height in [(280, 320), (360, 480), (720, 600)]:
        page.set_viewport_size({"width": width, "height": height})
        page.locator("#add").click()
        assert page.evaluate("document.documentElement.scrollWidth <= innerWidth")
        bounds = page.locator("#editor").bounding_box()
        assert bounds["x"] >= 0 and bounds["x"] + bounds["width"] <= width
        page.keyboard.press("Escape")

    page.set_viewport_size({"width": 360, "height": 480})
    page.screenshot(path=str(ROOT / "docs/panel-preview.png"))
    page.get_by_role("button", name="groom_mount", exact=True).click()
    page.screenshot(path=str(ROOT / "docs/editor-preview.png"))
    assert not errors, errors
    browser.close()

print("PASS: panel categories, combined filters, category editing, recording, dialogs, confirmation, character switches, and layout")
