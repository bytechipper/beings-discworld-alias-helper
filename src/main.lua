local Aliases = require("aliases")
Aliases.init()
local panel = mud.panel("beings-discworld-alias-helper")

local function update()
    panel:post("update", Aliases.display())
end

Aliases.set_character(gmcp.get("char.info.name") or gmcp.get("Char.Info.name"))
local function identity(_, data)
    if type(data) == "table" and data.name ~= nil and Aliases.set_character(data.name) then update() end
end
gmcp.on("char.info", identity)
gmcp.on("Char.Info", identity)
world.on("disconnect", function()
    Aliases.set_character(nil)
    update()
end)
world.on("line", function(line)
    if Aliases.record(line.text) then update() end
end)
-- A second `alias` listing starts in the default category again.
mud.on_send(function(m)
    if m.text:match("^%s*alias%s*$") then Aliases.begin_listing() end
end)

panel:on_message("ready", update)
panel:on_message("start", function()
    if Aliases.set_recording(true) then
        mud.note("[aliases] Recording started. Type alias, then press Stop record when the list finishes.", { fg = "cyan" })
    end
    update()
end)
panel:on_message("stop", function() Aliases.set_recording(false); update() end)

mud.command("aliases_clear", function()
    local ok, err = Aliases.clear()
    if ok then
        mud.note("[aliases] Cleared all saved aliases for " .. Aliases.display().character .. "; recording stopped.", { fg = "green" })
        update()
    else
        mud.note("[aliases] " .. err, { fg = "red" })
    end
end, { description = "Clear saved aliases for the current character and stop recording; MUD aliases are unchanged" })

-- These tokens select command syntax instead of an individual alias.
local reserved = {
    set = true, rename = true, show = true, sorted = true, category = true,
    categories = true, uncategorised = true, every = true,
}
local function validate(data, removing)
    local state = Aliases.display()
    if type(data) ~= "table" then return "Invalid request." end
    if not state.character or data.character ~= state.character then
        return "The character changed. Close this window and reopen the alias."
    end
    if not Aliases.valid_name(data.name) then return "Enter a name without spaces, control characters or colons." end
    if removing and (data.name == "all" or data.name == "pattern" or data.name == "category") then
        return "This name selects a bulk unalias command; it cannot be deleted here."
    end
    if not removing and reserved[data.name] then return "This name is reserved by the MUD alias command." end
    local old = Aliases.get(data.name)
    if data.original == nil then
        if removing or old then return "This alias already exists. Open it from the list to edit it." end
    elseif type(data.original) ~= "table" or not old
        or data.original.content ~= old.content or data.original.category ~= old.category then
        return "This alias changed since you opened it. Close this window and reopen it."
    end
    if removing then
        if data.confirmed ~= true then return "Please confirm deletion first." end
    elseif not Aliases.valid_content(data.content) then
        return "Enter non-empty content on one line; separate commands with semicolons."
    end
    if not removing and not Aliases.valid_category(data.category or (old and old.category) or "default") then
        return "Enter a category without quotes, backslashes, semicolons or control characters."
    end
    return nil, old
end

local function alias_command(name, content, category)
    if category == "default" then return "alias " .. name .. " " .. content end
    if not Aliases.valid_category(category) then return nil end
    return "alias " .. name .. ' in "' .. category .. '" ' .. content
end

local function change(data, removing)
    local err, old = validate(data, removing)
    local request_id = type(data) == "table" and data.request_id or nil
    local function reply(ok, message)
        panel:post("result", { request_id = request_id, ok = ok, message = message })
    end
    if err then reply(false, err); return end
    local category = data.category or (old and old.category) or "default"
    local steps = {}
    if removing then
        steps[1] = { command = "unalias " .. data.name }
    else
        -- Category-only edits use the MUD's move syntax and leave the body intact.
        -- When both change, update the body in its existing category before moving it.
        if not old or old.content ~= data.content or old.category == category then
            local write_category = old and old.category or category
            local command = alias_command(data.name, data.content, write_category)
            if not command then reply(false, "This category cannot be safely quoted."); return end
            steps[#steps + 1] = { command = command, content = data.content, category = write_category }
        end
        if old and old.category ~= category then
            steps[#steps + 1] = {
                command = "alias set category " .. data.name .. " " .. category,
                content = data.content, category = category,
            }
        end
    end
    -- Send directly to the MUD: semicolons, $arguments$ and backslashes stay literal.
    -- Validation rejects newlines because mud.send fans them out into commands.
    local last_sent
    for _, step in ipairs(steps) do
        local sent, send_err = pcall(mud.send, step.command)
        if not sent then
            local message = "Could not send command: " .. tostring(send_err)
            if last_sent then
                local saved, save_err = Aliases.put(data.name, last_sent.content, last_sent.category)
                message = "Content command sent, but category command could not be sent: " .. tostring(send_err)
                    .. ". Check MUD output, then close and reopen this alias."
                if not saved then message = message .. " Local saving failed: " .. tostring(save_err) end
                update()
            end
            reply(false, message)
            return
        end
        last_sent = step
    end
    local saved, save_err
    if removing then saved, save_err = Aliases.remove(data.name)
    else saved, save_err = Aliases.put(data.name, data.content, category) end
    local message = "Command sent. Check the MUD output for confirmation."
    if not saved then
        message = message .. " Local saving failed: " .. tostring(save_err) .. ". Record the alias list again."
        mud.note("[aliases] " .. message, { fg = "red" })
    end
    update()
    reply(true, message)
end

panel:on_message("save", function(data) change(data, false) end)
panel:on_message("delete", function(data) change(data, true) end)
