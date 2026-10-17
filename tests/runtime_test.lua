-- Match Mallard's src-relative, non-caching sandbox require.
require = function(name) return dofile(ROOT .. "/src/" .. name .. ".lua") end
local saved, state, result
local messages, sent, notes, handlers, events, identities = {}, {}, {}, {}, {}, {}
local commands = {}
local write_failure, send_failure = false, false
local send_failure_at
local writes = 0
storage = {
    get = function() return saved end,
    set = function(key, value)
        assert(key == "aliases")
        if write_failure then error("disk full") end
        writes = writes + 1
        saved = value
    end,
}
local panel = {
    post = function(_, name, data)
        messages[#messages + 1] = { name = name, data = data }
        if name == "update" then state = data else result = data end
    end,
    on_message = function(_, name, fn) handlers[name] = fn end,
}
mud = {
    command = function(name, fn, options)
        assert(type(options.description) == "string")
        commands[name] = fn
    end,
    panel = function(id) assert(id == "beings-discworld-alias-helper"); return panel end,
    note = function(message) notes[#notes + 1] = message end,
    send = function(command)
        if send_failure or send_failure_at == #sent + 1 then error("not connected") end
        sent[#sent + 1] = command
    end,
    on_send = function(fn) events.send = fn end,
}
gmcp = {
    get = function() return nil end,
    on = function(name, fn) identities[name] = fn end,
}
world = { on = function(name, fn) events[name] = fn end }
dofile(ROOT .. "/src/main.lua")
handlers.ready()
assert(state.character == nil and #state.aliases == 0)
handlers.start()
events.line({text = "test: ignore me"})
assert(not state.recording and #state.aliases == 0 and #sent == 0)
identities["char.info"]("char.info", {name = "  Being  "})
assert(state.character == "being")
handlers.start()
assert(state.recording and #sent == 0)
local samples = dofile(ROOT .. "/tests/samples.lua")
for _, line in ipairs(samples.small()) do assert(events.line({text = line}) == nil) end
assert(#state.aliases == 11, "sample count: " .. #state.aliases)
local counts = {}
local function find(name)
    for _, entry in ipairs(state.aliases) do if entry.name == name then return entry end end
end
for index, entry in ipairs(state.aliases) do
    counts[entry.category] = (counts[entry.category] or 0) + 1
    if index > 1 then assert(state.aliases[index - 1].name < entry.name) end
end
assert(counts.default == 6 and counts["pet-horse"] == 4 and counts.sailing == 1)
assert(find("rate_check").content == "rate $*$ in example-city")
assert(find("wrap_output").content == "cols 201;$ifarg:$*$;unwrap$endif$")
assert(find("pursue_target").content == "pursue $arg:opponents$")
assert(find("'").content == "say $*$" and find("<<").content == "say left $*$")
assert(find("§").content == "say symbol $*$")
assert(find("mount_emote").content == [[emote mount nuzzles \$me\$; $*$]])
assert(find("groom_mount").content == [[retrieve grooming kit from $arg:ExampleMount$;groom $arg:ExampleMount$;look;]])
assert(find("dress_mount").category == "pet-horse" and find("feed_dragon").category == "sailing")
assert(find("feed_dragon").content == "take $2$ from backpack; feed $2$ to $1$")
local previous_writes = writes
events.send({text = "alias"})
events.line({text = "rate_check: rate $*$ in example-city"})
assert(find("rate_check").category == "default" and writes == previous_writes)
events.line({text = "\27[32mpursue_target: pursue $arg:opponents$\27[0m"})
assert(writes == previous_writes)
handlers.stop()
events.line({text = "ignored: should not be saved"})
assert(not find("ignored") and not state.recording)

local function request(action, name, content, extra)
    local entry = find(name)
    local data = { request_id = "1", character = state.character, name = name, content = content,
        original = entry and {content = entry.content, category = entry.category} }
    for key, value in pairs(extra or {}) do data[key] = value end
    result = nil
    handlers[action](data)
    assert(result and result.request_id == "1")
    return result
end
assert(request("save", "new", [[say $arg:friend$;look \$me\$]]).ok)
assert(sent[#sent] == [[alias new say $arg:friend$;look \$me\$]])
assert(find("new").content == [[say $arg:friend$;look \$me\$]])
assert(request("save", "new", "say changed $*$").ok)
assert(sent[#sent] == "alias new say changed $*$")
assert(request("save", "assist_mount", "ask ExampleMount assist; $*$").ok)
assert(sent[#sent] == [[alias assist_mount in "pet-horse" ask ExampleMount assist; $*$]])
assert(find("assist_mount").category == "pet-horse")
local total = #sent
assert(not request("delete", "new").ok and #sent == total and find("new"))
assert(request("delete", "new", nil, {confirmed = true}).ok)
assert(sent[#sent] == "unalias new" and not find("new"))

-- Create in a category, move without rewriting content, and edit both fields.
assert(request("save", "categorised", "say hello $*$", {category = "sailing"}).ok)
assert(sent[#sent] == [[alias categorised in "sailing" say hello $*$]])
total = #sent
assert(request("save", "categorised", "say hello $*$", {category = "pet-horse"}).ok)
assert(#sent == total + 1 and sent[#sent] == "alias set category categorised pet-horse")
assert(find("categorised").content == "say hello $*$" and find("categorised").category == "pet-horse")
total = #sent
assert(request("save", "categorised", "say edited $arg:friend$", {category = "new category"}).ok)
assert(#sent == total + 2)
assert(sent[total + 1] == [[alias categorised in "pet-horse" say edited $arg:friend$]])
assert(sent[total + 2] == "alias set category categorised new category")
assert(find("categorised").category == "new category")
assert(request("save", "categorised", "say edited $arg:friend$", {category = "default"}).ok)
assert(sent[#sent] == "alias set category categorised default")
total = #sent
for _, category in ipairs({"", " ", " trailing ", 'bad"category', "bad;quit", "bad\\category", "bad\nquit", "bad\rquit", "bad\0category", {}}) do
    assert(not request("save", "categorised", "say edited $arg:friend$", {category = category}).ok)
end
assert(#sent == total)
assert(not request("save", "categorised", "say edited $arg:friend$", {
    category = "sailing", original = {content = "say edited $arg:friend$", category = "sailing"},
}).ok)
-- If the second send fails, retain only the body edit that was actually sent.
send_failure_at = #sent + 2
assert(not request("save", "categorised", "say partial", {category = "sailing"}).ok)
assert(result.message:find("Content command sent", 1, true))
assert(find("categorised").content == "say partial" and find("categorised").category == "default")
send_failure_at = nil
assert(request("save", "categorised", "say partial", {category = "sailing"}).ok)
dofile(ROOT .. "/src/main.lua")
identities["char.info"]("char.info", {name = "Being"})
assert(find("categorised").content == "say partial" and find("categorised").category == "sailing")
assert(request("delete", "categorised", nil, {confirmed = true}).ok)

total = #sent
for _, name in ipairs({"all", "pattern", "category"}) do
    handlers.start(); events.line({text = name .. ": say hi $*$"}); handlers.stop()
    assert(not request("delete", name, nil, {confirmed = true}).ok)
end
for _, name in ipairs({"a b", "a\nquit", "bad:", "", "set", "rename", "sorted"}) do
    assert(not request("save", name, "hello").ok)
end
for _, content in ipairs({"", "  ", "hello\nquit", "hello\rquit", "hello\0quit"}) do
    assert(not request("save", "unsafe", content).ok)
end
assert(not request("save", "unsafe", "hello", {character = "other"}).ok)
assert(not request("save", "rate_check", "hello", {original = {content = "stale", category = "default"}}).ok)
assert(#sent == total)
handlers.save({request_id = "duplicate", character = "being", name = "rate_check", content = "hello"})
assert(not result.ok and #sent == total)

-- Server send failures leave memory and persisted state unchanged.
send_failure = true
assert(not request("save", "rate_check", "changed").ok)
assert(find("rate_check").content == "rate $*$ in example-city" and #sent == total)
send_failure = false
-- Storage failure after sending is reported honestly, without claiming acceptance.
write_failure = true
assert(request("save", "unsaved", "say hello").ok)
assert(result.message:find("Local saving failed", 1, true) and not find("unsaved"))
handlers.start(); events.line({text = "unsaved: say hello"})
assert(not state.recording and not find("unsaved"))
write_failure = false

-- Switching and disconnecting isolate characters and stop recording.
identities["Char.Info"]("Char.Info", {name = "Another"})
assert(state.character == "another" and #state.aliases == 0 and not state.recording)
assert(request("save", "mine", "say another").ok)
identities["char.info"]("char.info", {name = "Being"})
assert(find("rate_check") and not find("mine"))
handlers.start()
events["disconnect"]()
assert(state.character == nil and #state.aliases == 0 and not state.recording)
-- A fresh runtime reload reads both persisted profiles and starts stopped.
dofile(ROOT .. "/src/main.lua")
identities["char.info"]("char.info", {name = "Being"})
assert(find("rate_check") and not find("new") and not state.recording)
identities["char.info"]("char.info", {name = "Another"})
assert(#state.aliases == 1 and find("mine"))

-- Clearing saves only the current profile, stops recording, and never sends to the MUD.
identities["char.info"]("char.info", {name = "Being"})
handlers.start()
local before_clear_count, before_clear_saved, before_clear_sent = #state.aliases, saved, #sent
assert(before_clear_count > 0 and state.recording)
write_failure = true
commands.aliases_clear()
assert(#state.aliases == before_clear_count and state.recording)
assert(saved == before_clear_saved and notes[#notes]:find("disk full", 1, true))
write_failure = false
commands.aliases_clear()
assert(#state.aliases == 0 and not state.recording)
assert(#saved.characters.being == 0 and #saved.characters.another == 1)
assert(notes[#notes]:find("Cleared all saved aliases for being", 1, true))
events.line({text = "stray: should not repopulate a cleared list"})
assert(#state.aliases == 0)
commands.aliases_clear() -- Clearing an empty list is harmless.
assert(#state.aliases == 0 and #sent == before_clear_sent)
dofile(ROOT .. "/src/main.lua")
identities["char.info"]("char.info", {name = "Being"})
assert(#state.aliases == 0 and not state.recording)
identities["char.info"]("char.info", {name = "Another"})
assert(#state.aliases == 1 and find("mine"))
events["disconnect"]()
local before_clear_writes = writes
commands.aliases_clear()
assert(writes == before_clear_writes and #sent == before_clear_sent)
assert(notes[#notes]:find("Waiting for the logged-in character name", 1, true))
print("PASS: synthetic aliases, CRUD, categories, persistence, validation, clearing and failures")
