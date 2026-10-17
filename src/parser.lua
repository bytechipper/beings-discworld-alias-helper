-- Discworld prints each cell as `name: content`, separated by column padding.
-- Colour-enabled aliases use `name (colour replace): content` instead.
-- Only the first colon is structural: $arg:default$ and colons in bodies survive.
local Parser = {}
Parser.__index = Parser

function Parser.new()
    return setmetatable({ category = "default" }, Parser)
end

function Parser:reset()
    self.category = "default"
    self.category_summary = false
end

local function find_cell(text, prefix, offset)
    local first, last, name = text:find(prefix .. "([^%s:]+)[ \t]+%(colour replace%):[ \t]+", offset)
    local plain_first, plain_last, plain_name = text:find(prefix .. "([^%s:]+):[ \t]+", offset)
    if plain_first and (not first or plain_first < first) then
        return plain_first, plain_last, plain_name
    end
    return first, last, name
end

function Parser:line(text)
    local result = {}
    if type(text) ~= "string" then return result end
    text = text:gsub("\27%[[%d;]*m", ""):gsub("\r$", "")
    if text:match("^%s*You currently have the following aliases:%s*$") then
        self:reset()
        return result
    end
    if text:match("^%s*You have the following alias categories defined:%s*$") then
        self.category_summary = true
        return result
    end
    if self.category_summary then
        if text:match("^%s*%d+ total categories, %d+ total aliases%.%s*$") then self:reset() end
        return result
    end
    if text:match("^%s*Default category:%s*$") then
        self:reset()
        return result
    end
    local category = text:match('^%s*The category "(.-)":%s*$')
    if category then
        self.category = category
        return result
    end
    local _, finish, name = find_cell(text, "^%s*", 1)
    if not name then return result end
    local body_start = finish + 1
    while true do
        local first, last, next_name = find_cell(text, "[ \t][ \t]+", body_start)
        local content = text:sub(body_start, first and first - 1 or #text):gsub("[ \t]+$", "")
        if content ~= "" then
            result[#result + 1] = { name = name, content = content, category = self.category }
        end
        if not first then break end
        name, body_start = next_name, last + 1
    end
    return result
end

return Parser
