require = function(name) return dofile(ROOT .. "/src/" .. name .. ".lua") end
local parser = require("parser").new()

local function expect(line, expected)
    local entries = parser:line(line)
    assert(#entries == #expected, "Unexpected number of entries: " .. line)
    for index, entry in ipairs(entries) do
        assert(entry.name == expected[index][1], "Wrong name: " .. entry.name)
        assert(entry.content == expected[index][2], "Wrong content: " .. entry.content)
        assert(entry.category == expected[index][3], "Wrong category: " .. entry.category)
    end
end

expect("colourful (colour replace): say %^BLUE%^example%^RESET%^ $*$", {
    {"colourful", "say %^BLUE%^example%^RESET%^ $*$", "default"},
})
-- Either cell form may appear first, between other cells, or last in a row.
expect("one: say one $*$    two (colour replace): say %^RED%^two $arg:friend$    three: say three", {
    {"one", "say one $*$", "default"},
    {"two", "say %^RED%^two $arg:friend$", "default"},
    {"three", "say three", "default"},
})
expect("one (colour replace): say one    two: say two    three (colour replace): say three", {
    {"one", "say one", "default"}, {"two", "say two", "default"}, {"three", "say three", "default"},
})
-- Only cell headers are structural; annotated-looking text in a body stays literal.
expect("literal: say example (colour replace): $arg:friend$;look", {
    {"literal", "say example (colour replace): $arg:friend$;look", "default"},
})
expect('The category "test":', {})
expect("\27[32m.colour (colour replace): say $1$;look\27[0m\r", {
    {".colour", "say $1$;look", "test"},
})
expect("Default category:", {})
expect("normal: say default", {{"normal", "say default", "default"}})
expect("You have the following alias categories defined:", {})
expect("(default): 1438 aliases", {})
expect("pet-horse: 61 aliases", {})
expect("sailing: 31 aliases", {})
expect("", {})
expect("3 total categories, 1530 total aliases.", {})
expect("You currently have the following aliases:", {})
expect('The category "sailing":', {})
expect("hls: look overboard $*$", {{"hls", "look overboard $*$", "sailing"}})

-- Generate a large listing to test recording and persistence without player data.
local saved
storage = {
    get = function() return saved end,
    set = function(_, value) saved = value end,
}
mud = { note = function(message) error("Unexpected recorder error: " .. message) end }
local aliases = require("aliases")
aliases.init()
aliases.set_character("being")
aliases.set_recording(true)
local samples = dofile(ROOT .. "/tests/samples.lua")
local lines, expected_colours = samples.large()
for _, line in ipairs(lines) do aliases.record(line) end
aliases.set_recording(false)
local data = aliases.display()
assert(#data.aliases == 1530, "Expected 1530 aliases, got " .. #data.aliases)
local seen, colour_count, category_counts = {}, 0, {}
for _, entry in ipairs(data.aliases) do
    assert(not seen[entry.name], "Duplicate alias: " .. entry.name)
    seen[entry.name] = entry
    category_counts[entry.category] = (category_counts[entry.category] or 0) + 1
    if expected_colours[entry.name] then
        assert(entry.content == expected_colours[entry.name], "Changed colour alias body: " .. entry.name)
        assert(entry.category == "default")
        colour_count = colour_count + 1
    end
end
assert(colour_count == 19, "Expected all 19 colour aliases")
assert(category_counts.default == 1438 and category_counts["pet-horse"] == 61 and category_counts.sailing == 31)
assert(seen.default_example_1 and seen.default_example_19 and seen.default_example_1438)
assert(seen.pet_horse_example_61.category == "pet-horse" and seen.sailing_example_31.category == "sailing")
-- Reload keeps every alias; another recording updates entries without duplicating them.
aliases = require("aliases")
aliases.init()
aliases.set_character("being")
assert(#aliases.display().aliases == 1530)
assert(aliases.get("default_example_1").content == expected_colours.default_example_1)
aliases.set_recording(true)
aliases.record("default_example_1 (colour replace): say updated $*$")
assert(#aliases.display().aliases == 1530)
assert(aliases.get("default_example_1").content == "say updated $*$")
aliases.record("You have the following alias categories defined:")
aliases.record("(default): 1438 aliases")
aliases.record("pet-horse: 61 aliases")
aliases.record("sailing: 31 aliases")
aliases.record("3 total categories, 1530 total aliases.")
assert(#aliases.display().aliases == 1530)
assert(not aliases.get("pet-horse") and not aliases.get("sailing") and not aliases.get("(default)"))
print("PASS: 1530 generated aliases, including 19 colour aliases, exact bodies and persistence")
