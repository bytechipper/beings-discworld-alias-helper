local Parser = require("parser")
local Aliases = {}
local profiles, aliases = {}, {}
local character, recording = nil, false
local parser = Parser.new()
local key = "aliases"

local function copy(source)
    local result = {}
    for name, entry in pairs(source) do result[name] = entry end
    return result
end

local function sorted(source)
    local result = {}
    for _, entry in pairs(source) do
        result[#result + 1] = { name = entry.name, content = entry.content, category = entry.category }
    end
    table.sort(result, function(a, b) return a.name < b.name end)
    return result
end

function Aliases.valid_name(name)
    return type(name) == "string" and name ~= "" and not name:find("[%s%c:]")
end

function Aliases.valid_content(content)
    return type(content) == "string" and content:find("%S") ~= nil and not content:find("%c")
end

function Aliases.valid_category(category)
    return type(category) == "string" and category ~= "" and not category:find('[%c";\\]')
        and category == category:match("^%s*(.-)%s*$")
end

local function read(list)
    if type(list) ~= "table" then error("[aliases] Invalid saved list; refusing to overwrite it") end
    local result = {}
    for _, entry in ipairs(list) do
        if type(entry) ~= "table" or not Aliases.valid_name(entry.name)
            or not Aliases.valid_content(entry.content) or type(entry.category) ~= "string"
            or entry.category == "" or entry.category:find("%c") then
            error("[aliases] Invalid saved alias; refusing to overwrite it")
        end
        result[entry.name] = { name = entry.name, content = entry.content, category = entry.category }
    end
    return result
end

function Aliases.init()
    local saved = storage.get(key)
    if saved == nil then return end
    if type(saved) ~= "table" or saved.version ~= 1 or type(saved.characters) ~= "table" then
        error("[aliases] Unsupported saved data; refusing to overwrite it")
    end
    for name, list in pairs(saved.characters) do
        if type(name) ~= "string" or name == "" then error("[aliases] Invalid saved character") end
        profiles[name] = sorted(read(list))
    end
end

local function commit(next_aliases)
    local next_profiles = copy(profiles)
    next_profiles[character] = sorted(next_aliases)
    local ok, err = pcall(storage.set, key, { version = 1, characters = next_profiles })
    if not ok then return false, tostring(err) end
    profiles, aliases = next_profiles, next_aliases
    return true
end

function Aliases.set_character(name)
    name = type(name) == "string" and name:match("^%s*(.-)%s*$"):lower() or nil
    if name == "" or name == "you" then name = nil end
    if name == character then return false end
    character, recording = name, false
    aliases = name and read(profiles[name] or {}) or {}
    parser:reset()
    return true
end

function Aliases.display()
    return { character = character, recording = recording, aliases = sorted(aliases) }
end

function Aliases.get(name)
    local entry = aliases[name]
    if entry then return { name = entry.name, content = entry.content, category = entry.category } end
end

function Aliases.set_recording(value)
    recording = value == true and character ~= nil
    parser:reset()
    return recording
end

function Aliases.begin_listing()
    parser:reset()
end

function Aliases.clear()
    if not character then return false, "Waiting for the logged-in character name from Discworld." end
    local ok, err = commit({})
    if not ok then return false, "Could not clear saved aliases: " .. err end
    recording = false
    parser:reset()
    return true
end

function Aliases.record(text)
    if not recording then return false end
    local next_aliases, changed = copy(aliases), false
    for _, entry in ipairs(parser:line(text)) do
        if Aliases.valid_name(entry.name) and Aliases.valid_content(entry.content) then
            local old = next_aliases[entry.name]
            if not old or old.content ~= entry.content or old.category ~= entry.category then
                next_aliases[entry.name], changed = entry, true
            end
        end
    end
    if not changed then return false end
    local ok, err = commit(next_aliases)
    if not ok then
        recording = false
        mud.note("[aliases] Recording stopped: could not save aliases: " .. err, { fg = "red" })
        return true
    end
    return true
end

function Aliases.put(name, content, category)
    local next_aliases = copy(aliases)
    next_aliases[name] = { name = name, content = content, category = category }
    return commit(next_aliases)
end

function Aliases.remove(name)
    local next_aliases = copy(aliases)
    next_aliases[name] = nil
    return commit(next_aliases)
end

return Aliases
