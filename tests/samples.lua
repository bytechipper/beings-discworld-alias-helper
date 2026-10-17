-- Invented examples only. Never copy a player's alias export into this file.
local Samples = {}

function Samples.small()
    return {
        "Default category:",
        "rate_check: rate $*$ in example-city    wrap_output: cols 201;$ifarg:$*$;unwrap$endif$",
        "pursue_target: pursue $arg:opponents$    ': say $*$    <<: say left $*$    §: say symbol $*$",
        'The category "pet-horse":',
        "groom_mount: retrieve grooming kit from $arg:ExampleMount$;groom $arg:ExampleMount$;look;",
        "assist_mount: ask ExampleMount assist; $*$    dress_mount: dress mount $*$",
        [[mount_emote: emote mount nuzzles \$me\$; $*$]],
        'The category "sailing":',
        "feed_dragon: take $2$ from backpack; feed $2$ to $1$",
    }
end

function Samples.large()
    local lines, colours = {}, {}
    for _, group in ipairs({{"default", 1438}, {"pet-horse", 61}, {"sailing", 31}}) do
        local category, count = group[1], group[2]
        lines[#lines + 1] = category == "default" and "Default category:" or 'The category "' .. category .. '":'
        local cells = {}
        for index = 1, count do
            local name = category:gsub("-", "_") .. "_example_" .. index
            local content = "say sample " .. index .. ";look $arg:example$"
            local annotated = category == "default" and index <= 19
            if annotated then
                content = "say %^BLUE%^sample " .. index .. "%^RESET%^ $*$"
                colours[name] = content
            end
            cells[#cells + 1] = name .. (annotated and " (colour replace)" or "") .. ": " .. content
            if #cells == 3 or index == count then
                lines[#lines + 1] = table.concat(cells, "    ")
                cells = {}
            end
        end
    end
    return lines, colours
end

return Samples
