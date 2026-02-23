--- Loreline - interactive fiction scripting language.
-- @module loreline

local core = require("loreline.core")

local M = {}

-- ── Internal helpers ────────────────────────────────────────────────────

--- Convert an internal Haxe array to a plain Lua table (1-indexed).
local function hx_array_to_lua(arr)
    if arr == nil then return {} end
    local t = {}
    for i = 0, arr.length - 1 do
        t[#t + 1] = arr[i]
    end
    return t
end

--- Wrap an internal TextTag into a plain Lua table.
local function wrap_tag(tag)
    return {
        value = tag.value,
        offset = tag.offset,
        closing = tag.closing,
    }
end

--- Wrap a list of internal TextTags into a plain Lua table.
local function wrap_tags(tags)
    if tags == nil then return {} end
    local result = {}
    for i = 0, tags.length - 1 do
        result[#result + 1] = wrap_tag(tags[i])
    end
    return result
end

--- Wrap an internal ChoiceOption into a plain Lua table.
local function wrap_option(opt)
    return {
        text = opt.text,
        tags = wrap_tags(opt.tags),
        enabled = opt.enabled,
    }
end

--- Wrap a list of internal ChoiceOptions into a plain Lua table.
local function wrap_options(options)
    local result = {}
    for i = 0, options.length - 1 do
        result[#result + 1] = wrap_option(options[i])
    end
    return result
end

-- ── Script ──────────────────────────────────────────────────────────────

--- A parsed Loreline script AST.
-- Obtain via `loreline.parse()`. Pass to `loreline.play()` or
-- `loreline.resume()` to execute.
-- @type Script
local Script = {}
Script.__index = Script

--- @param internal table The internal Haxe script object.
function Script._new(internal)
    return setmetatable({ _internal = internal }, Script)
end

-- ── Interpreter ─────────────────────────────────────────────────────────

--- A running Loreline script interpreter.
-- Provides methods to save/restore state and access character data.
-- @type Interpreter
local Interpreter = {}
Interpreter.__index = Interpreter

--- @param internal table The internal Haxe interpreter object.
function Interpreter._new(internal)
    return setmetatable({ _internal = internal }, Interpreter)
end

--- Save the current interpreter state.
-- @return table Opaque save-data that can be passed to `loreline.resume()`
--   or `interpreter:restore()` later.
function Interpreter:save()
    return self._internal:save()
end

--- Restore the interpreter to a previously saved state.
-- @param save_data table The opaque save-data from `save()`.
function Interpreter:restore(save_data)
    self._internal:restore(save_data)
end

--- Resume execution after restoring state.
function Interpreter:resume()
    self._internal:resume()
end

--- Start or restart execution from a specific beat.
-- @param beat_name string|nil Name of the beat to start from.
--   If nil, starts from the first beat.
function Interpreter:start(beat_name)
    self._internal:start(beat_name)
end

--- Get a character's fields by name.
-- @param name string The character identifier.
-- @return table|nil The character's fields, or nil if not found.
function Interpreter:get_character(name)
    return self._internal:getCharacter(name)
end

--- Get a specific field of a character.
-- @param character string The character identifier.
-- @param field string The field name to retrieve.
-- @return any The field value, or nil if not found.
function Interpreter:get_character_field(character, field)
    return self._internal:getCharacterField(character, field)
end

--- Set a specific field of a character.
-- @param character string The character identifier.
-- @param field string The field name to set.
-- @param value any The value to assign.
function Interpreter:set_character_field(character, field, value)
    self._internal:setCharacterField(character, field, value)
end

-- ── Callback bridges ────────────────────────────────────────────────────

local function make_dialogue_bridge(handle_dialogue)
    return function(interp, character, text, tags, advance)
        local wrapper = Interpreter._new(interp)
        handle_dialogue(wrapper, character, text, wrap_tags(tags), advance)
    end
end

local function make_choice_bridge(handle_choice)
    return function(interp, options, select)
        local wrapper = Interpreter._new(interp)
        handle_choice(wrapper, wrap_options(options), select)
    end
end

local function make_finish_bridge(handle_finish)
    return function(interp)
        local wrapper = Interpreter._new(interp)
        handle_finish(wrapper)
    end
end

-- ── Public API ──────────────────────────────────────────────────────────

--- Parse a Loreline script string into a Script AST.
-- @param source string The `.lor` script content.
-- @param file_path string|nil Optional file path for resolving imports.
-- @param handle_file function|nil Optional handler `function(path, callback)` to load imported files.
-- @param callback function|nil Optional callback `function(script)` receiving the parsed Script.
-- @return Script|nil The parsed Script, or nil if loaded asynchronously.
function M.parse(source, file_path, handle_file, callback)
    local wrapped_callback = nil
    if callback ~= nil then
        wrapped_callback = function(internal_script)
            callback(Script._new(internal_script))
        end
    end

    local result = __loreline_Loreline.parse(source, file_path, handle_file, wrapped_callback)
    if result ~= nil then
        return Script._new(result)
    end
    return nil
end

--- Start playing a parsed script.
-- @param script Script A parsed Script from `parse()`.
-- @param handle_dialogue function Called when dialogue text should be displayed:
--   `function(interpreter, character, text, tags, advance)`
-- @param handle_choice function Called when the player must make a choice:
--   `function(interpreter, options, select)`
-- @param handle_finish function Called when script execution completes:
--   `function(interpreter)`
-- @param beat_name string|nil Optional beat to start from (default: first beat).
-- @param options table|nil Optional table with fields:
--   `functions` (table), `strict_access` (bool), `translations` (table).
-- @return Interpreter The running Interpreter instance.
function M.play(script, handle_dialogue, handle_choice, handle_finish, beat_name, options)
    local hx_options = nil
    if options ~= nil then
        hx_options = _G._hx_o({
            __fields__ = {
                functions = options.functions ~= nil,
                strictAccess = options.strict_access ~= nil,
                translations = options.translations ~= nil,
            },
            functions = options.functions,
            strictAccess = options.strict_access or false,
            translations = options.translations,
        })
    end

    local internal = __loreline_Loreline.play(
        script._internal,
        make_dialogue_bridge(handle_dialogue),
        make_choice_bridge(handle_choice),
        make_finish_bridge(handle_finish),
        beat_name,
        hx_options
    )
    return Interpreter._new(internal)
end

--- Resume a script from saved state.
-- @param script Script A parsed Script from `parse()`.
-- @param handle_dialogue function Called when dialogue text should be displayed.
-- @param handle_choice function Called when the player must make a choice.
-- @param handle_finish function Called when script execution completes.
-- @param save_data table The opaque save-data from `Interpreter:save()`.
-- @param beat_name string|nil Optional beat name to override resume point.
-- @param options table|nil Optional table (same as `play()`).
-- @return Interpreter The running Interpreter instance.
function M.resume(script, handle_dialogue, handle_choice, handle_finish, save_data, beat_name, options)
    local hx_options = nil
    if options ~= nil then
        hx_options = _G._hx_o({
            __fields__ = {
                functions = options.functions ~= nil,
                strictAccess = options.strict_access ~= nil,
                translations = options.translations ~= nil,
            },
            functions = options.functions,
            strictAccess = options.strict_access or false,
            translations = options.translations,
        })
    end

    local internal = __loreline_Loreline.resume(
        script._internal,
        make_dialogue_bridge(handle_dialogue),
        make_choice_bridge(handle_choice),
        make_finish_bridge(handle_finish),
        save_data,
        beat_name,
        hx_options
    )
    return Interpreter._new(internal)
end

--- Extract translations from a parsed translation script.
-- @param script Script A parsed translation script (`.XX.lor` file).
-- @return table A translations object to pass to `play()` or `resume()`.
function M.extract_translations(script)
    return __loreline_Loreline.extractTranslations(script._internal)
end

--- Print a parsed script back into Loreline source code.
-- @param script Script A parsed Script from `parse()`.
-- @param indent string The indentation string (default: two spaces).
-- @param newline string The newline string (default: "\n").
-- @return string The printed source code.
function M.print(script, indent, newline)
    indent = indent or "  "
    newline = newline or "\n"
    return __loreline_Loreline.print(script._internal, indent, newline)
end

-- Export types for introspection
M.Script = Script
M.Interpreter = Interpreter

return M
