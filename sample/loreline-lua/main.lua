#!/usr/bin/env lua
--- Loreline Lua Sample — CoffeeShop
--
-- Interactive console app that runs the CoffeeShop story.
--
-- Usage:
--     lua main.lua

local loreline = require("loreline")

--- Read a file and return its contents, or empty string on error.
local function read_file(path)
    local f = io.open(path, "r")
    if not f then return "" end
    local content = f:read("*a")
    f:close()
    return content
end

--- Resolve the directory of this script.
local function script_dir()
    local info = debug.getinfo(1, "S")
    local path = info.source:match("^@(.*/)")
    return path or "./"
end

--- Load an imported file (e.g. characters.lor).
local function handle_file(path, provide)
    local content = read_file(path)
    provide(content)
end

--- Display dialogue or narrative text.
local function handle_dialogue(interp, character, text, tags, advance)
    -- Indent continuation lines for multiline text
    local formatted = text:gsub("\n", "\n ")

    if character ~= nil then
        -- Dialogue — resolve display name
        local name = interp:get_character_field(character, "name")
        local display_name = name or character
        io.write(" " .. display_name .. ": " .. formatted .. "\n")
    else
        -- Narrative text
        io.write(" " .. formatted .. "\n")
    end

    advance()
end

--- Prompt the user to pick a choice.
local function handle_choice(interp, options, select)
    io.write("\n")
    local enabled_indices = {}
    for i, opt in ipairs(options) do
        if opt.enabled then
            enabled_indices[#enabled_indices + 1] = i - 1  -- 0-based index for select()
            io.write(" " .. #enabled_indices .. ". " .. opt.text .. "\n")
        end
    end

    while true do
        io.write("\n> ")
        io.flush()
        local raw = io.read("*l")
        if raw == nil then break end  -- EOF
        local choice = tonumber(raw:match("^%s*(.-)%s*$"))
        if choice and choice >= 1 and choice <= #enabled_indices then
            select(enabled_indices[choice])
            return
        end
        io.write("  Please enter a valid choice number.\n")
    end
end

--- Called when the story ends.
local function handle_finish(interp)
    io.write("\n--- End of story ---\n")
end

-- Main
local story_dir = script_dir() .. "story/"
local story_path = story_dir .. "CoffeeShop.lor"

local source = read_file(story_path)
if source == "" then
    io.stderr:write("Error: could not read " .. story_path .. "\n")
    os.exit(1)
end

local script = loreline.parse(source, story_path, handle_file)
if script == nil then
    io.stderr:write("Error: failed to parse script\n")
    os.exit(1)
end

io.write("=== CoffeeShop ===\n\n")
loreline.play(script, handle_dialogue, handle_choice, handle_finish)
