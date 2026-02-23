#!/usr/bin/env lua
--[[
Loreline Lua test runner.

Follows the same test protocol as the JS, C#, C++, and Python test runners:
  - Collects .lor files from the given directory
  - Extracts <test> YAML blocks from comments
  - Runs each test in LF and CRLF modes
  - Runs roundtrip (parse -> print -> parse -> print) stability checks
  - Reports pass/fail counts
]]

-- Add lua/ to package path so we can require loreline.core
local script_dir = arg[0]:match("(.*/)")  or "./"
package.path = script_dir .. "?.lua;" .. script_dir .. "?/init.lua;" .. package.path

dofile(script_dir .. "loreline/core.lua")

local pass_count = 0
local fail_count = 0
local file_count = 0
local file_fail_count = 0

-- ── Helpers ──────────────────────────────────────────────────────────────

local function read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return content
end

local function is_dir(path)
    -- Try to open as directory by listing it
    local f = io.popen('test -d "' .. path .. '" && echo yes || echo no')
    if not f then return false end
    local result = f:read("*l")
    f:close()
    return result == "yes"
end

local function list_dir(path)
    local entries = {}
    local f = io.popen('ls -1 "' .. path .. '" 2>/dev/null')
    if not f then return entries end
    for line in f:lines() do
        table.insert(entries, line)
    end
    f:close()
    table.sort(entries)
    return entries
end

local function collect_test_files(directory)
    local files = {}
    local entries = list_dir(directory)
    for _, entry in ipairs(entries) do
        local full_path = directory .. "/" .. entry
        if is_dir(full_path) then
            if entry ~= "imports" and entry ~= "modified" then
                local sub_files = collect_test_files(full_path)
                for _, f in ipairs(sub_files) do
                    table.insert(files, f)
                end
            end
        elseif entry:match("%.lor$") and not entry:match("%.%w%w%.lor$") then
            table.insert(files, full_path)
        end
    end
    return files
end

local function handle_file(path, callback)
    local content = read_file(path)
    callback(content)
end

local function hx_array_to_lua(arr)
    if arr == nil then return {} end
    local result = {}
    for i = 0, arr.length - 1 do
        result[i + 1] = arr[i]
    end
    return result
end

local function insert_tags_in_text(text, tags, multiline)
    local offsets_with_tags = {}
    for _, tag in ipairs(tags) do
        offsets_with_tags[tag.offset] = true
    end

    local chars = {}
    for i = 1, #text do
        chars[i] = text:sub(i, i)
    end
    local length = #chars
    local result = {}

    for i = 1, length do
        local offset = i - 1  -- 0-based offset
        if offsets_with_tags[offset] then
            for _, tag in ipairs(tags) do
                if tag.offset == offset then
                    table.insert(result, "<<")
                    if tag.closing then
                        table.insert(result, "/")
                    end
                    table.insert(result, tag.value)
                    table.insert(result, ">>")
                end
            end
        end
        local c = chars[i]
        if multiline and c == "\n" then
            table.insert(result, "\n  ")
        else
            table.insert(result, c)
        end
    end

    -- Tags at end of text
    for _, tag in ipairs(tags) do
        if tag.offset >= length then
            table.insert(result, "<<")
            if tag.closing then
                table.insert(result, "/")
            end
            table.insert(result, tag.value)
            table.insert(result, ">>")
        end
    end

    local s = table.concat(result)
    return s:match("^(.-)%s*$") or ""  -- rtrim
end

local function compare_output(expected, actual)
    local function split_lines(s)
        s = s:gsub("\r\n", "\n")
        s = s:match("^%s*(.-)%s*$") or ""  -- trim
        local lines = {}
        for line in (s .. "\n"):gmatch("([^\n]*)\n") do
            table.insert(lines, line)
        end
        return lines
    end

    local expected_lines = split_lines(expected)
    local actual_lines = split_lines(actual)
    local min_len = math.min(#expected_lines, #actual_lines)
    local max_len = math.max(#expected_lines, #actual_lines)

    for i = 1, min_len do
        if expected_lines[i] ~= actual_lines[i] then
            return i - 1  -- 0-based index
        end
    end
    if min_len < max_len then
        return min_len
    end
    return -1
end

-- ── Minimal YAML parser ─────────────────────────────────────────────────

local function parse_yaml_value(s)
    s = s:match("^%s*(.-)%s*$") or ""
    if s == "" then return nil end
    -- Inline flow sequence: [0, 1, 2]
    if s:sub(1, 1) == "[" and s:sub(-1) == "]" then
        local inner = s:sub(2, -2):match("^%s*(.-)%s*$") or ""
        if inner == "" then return {} end
        local items = {}
        for val in inner:gmatch("[^,]+") do
            table.insert(items, parse_yaml_value(val))
        end
        return items
    end
    -- Integer
    if s:match("^%-?%d+$") then
        return tonumber(s)
    end
    -- Boolean
    if s == "true" then return true end
    if s == "false" then return false end
    -- Null
    if s == "null" or s == "~" then return nil end
    -- String (strip optional quotes)
    if #s >= 2 and s:sub(1, 1) == s:sub(-1) and (s:sub(1, 1) == '"' or s:sub(1, 1) == "'") then
        return s:sub(2, -2)
    end
    return s
end

local function parse_simple_yaml(text)
    local lines = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        table.insert(lines, line)
    end

    local items = {}
    local current = nil
    local block_key = nil
    local block_indent = 0
    local block_lines = {}
    local i = 1

    local function flush_block()
        if block_key and current then
            -- Strip trailing empty lines
            while #block_lines > 0 and block_lines[#block_lines] == "" do
                table.remove(block_lines)
            end
            current[block_key] = table.concat(block_lines, "\n") .. "\n"
        end
        block_key = nil
        block_lines = {}
    end

    while i <= #lines do
        local line = lines[i]
        local stripped = line:match("^(.-)%s*$") or ""

        -- Inside a block scalar?
        if block_key then
            if stripped == "" then
                table.insert(block_lines, "")
                i = i + 1
                goto continue
            end
            if #line >= block_indent and line:sub(1, block_indent) == string.rep(" ", block_indent) then
                local content = line:sub(block_indent + 1):match("^(.-)%s*$") or ""
                table.insert(block_lines, content)
                i = i + 1
                goto continue
            else
                flush_block()
                -- Fall through
            end
        end

        -- New list item: "- key: value"
        local key, value = stripped:match("^%- (%w+):%s*(.*)")
        if key then
            current = {}
            table.insert(items, current)
            if value == "|" then
                block_key = key
                block_indent = 4
                block_lines = {}
            else
                current[key] = parse_yaml_value(value)
            end
            i = i + 1
            goto continue
        end

        -- Continuation key: "  key: value"
        local key2, value2 = stripped:match("^  (%w+):%s*(.*)")
        if key2 and current then
            if value2 == "|" then
                block_key = key2
                block_indent = 4
                block_lines = {}
            else
                current[key2] = parse_yaml_value(value2)
            end
            i = i + 1
            goto continue
        end

        i = i + 1
        ::continue::
    end

    flush_block()
    return items
end

local function extract_tests(content)
    local tests = {}
    for yaml_content in content:gmatch("<test>(.-)</test>") do
        yaml_content = yaml_content:match("^%s*(.-)%s*$") or ""
        local parsed = parse_simple_yaml(yaml_content)
        for _, item in ipairs(parsed) do
            table.insert(tests, item)
        end
    end
    return tests
end

-- ── Test runner ──────────────────────────────────────────────────────────

local function run_test(file_path, content, test_item, crlf)
    -- Normalize line endings
    if crlf then
        content = content:gsub("\r\n", "\n"):gsub("\n", "\r\n")
    else
        content = content:gsub("\r\n", "\n")
    end

    local choices = {}
    if test_item.choices then
        for _, c in ipairs(test_item.choices) do
            table.insert(choices, c)
        end
    end
    local beat_name = test_item.beat or nil
    local save_at_choice = test_item.saveAtChoice or -1
    local save_at_dialogue = test_item.saveAtDialogue or -1
    local expected = test_item.expected
    local output = {""}
    local choice_count = {0}
    local dialogue_count = {0}
    local parsed_script = {nil}
    local result = {nil}

    -- Build options
    local options = nil
    local translation_val = test_item.translation
    if translation_val then
        local lang = translation_val
        local base_path = file_path:sub(1, -5)  -- strip .lor
        local translation_path = base_path .. "." .. lang .. ".lor"
        local translation_content = read_file(translation_path)
        if translation_content then
            if crlf then
                translation_content = translation_content:gsub("\r\n", "\n"):gsub("\n", "\r\n")
            else
                translation_content = translation_content:gsub("\r\n", "\n")
            end
            local translation_script = __loreline_Loreline.parse(
                translation_content, translation_path, handle_file
            )
            if translation_script then
                local translations = __loreline_Loreline.extractTranslations(translation_script)
                options = _hx_o({__fields__={translations=true}, translations=translations})
            end
        end
    end

    -- Load restoreFile content if specified
    local restore_input = nil
    if test_item.restoreFile then
        local dir = file_path:match("(.*/)")  or "./"
        local restore_path = dir .. test_item.restoreFile
        restore_input = read_file(restore_path)
        if restore_input then
            if crlf then
                restore_input = restore_input:gsub("\r\n", "\n"):gsub("\n", "\r\n")
            else
                restore_input = restore_input:gsub("\r\n", "\n")
            end
        end
    end

    local function on_finish(interp)
        local cmp = compare_output(expected, output[1])
        result[1] = {cmp == -1, output[1], expected, nil}
    end

    local function on_choice(interp, choice_options, select)
        local opts = hx_array_to_lua(choice_options)
        for _, opt in ipairs(opts) do
            local prefix = opt.enabled and "+" or "-"
            local multiline = opt.text:find("\n") ~= nil
            local opt_tags = opt.tags and hx_array_to_lua(opt.tags) or {}
            local tagged_text = insert_tags_in_text(opt.text, opt_tags, multiline)
            output[1] = output[1] .. prefix .. " " .. tagged_text .. "\n"
        end
        output[1] = output[1] .. "\n"

        -- Save/restore test
        if save_at_choice >= 0 and choice_count[1] == save_at_choice then
            choice_count[1] = choice_count[1] + 1
            local save_data = interp:save()

            if restore_input then
                local restore_script = __loreline_Loreline.parse(
                    restore_input, file_path, handle_file
                )
                if restore_script then
                    __loreline_Loreline.resume(
                        restore_script, on_dialogue, on_choice, on_finish,
                        save_data, nil, options
                    )
                else
                    result[1] = {false, output[1], expected, "Error parsing restoreInput script"}
                end
            else
                __loreline_Loreline.resume(
                    parsed_script[1], on_dialogue, on_choice, on_finish,
                    save_data, nil, options
                )
            end
            return
        end

        choice_count[1] = choice_count[1] + 1

        if #choices == 0 then
            on_finish(interp)
        else
            local index = table.remove(choices, 1)
            select(index)
        end
    end

    function on_dialogue(interp, character, text, tags, advance)
        local multiline = text:find("\n") ~= nil
        local lua_tags = tags and hx_array_to_lua(tags) or {}
        if character ~= nil then
            local char_name = interp:getCharacterField(character, "name")
            if char_name == nil then
                char_name = character
            end
            local tagged_text = insert_tags_in_text(text, lua_tags, multiline)
            if multiline then
                output[1] = output[1] .. char_name .. ":\n  " .. tagged_text .. "\n\n"
            else
                output[1] = output[1] .. char_name .. ": " .. tagged_text .. "\n\n"
            end
        else
            local tagged_text = insert_tags_in_text(text, lua_tags, multiline)
            output[1] = output[1] .. "~ " .. tagged_text .. "\n\n"
        end
        -- Save/restore test at dialogue
        if save_at_dialogue >= 0 and dialogue_count[1] == save_at_dialogue then
            dialogue_count[1] = dialogue_count[1] + 1
            local save_data = interp:save()

            if restore_input then
                local restore_script = __loreline_Loreline.parse(
                    restore_input, file_path, handle_file
                )
                if restore_script then
                    __loreline_Loreline.resume(
                        restore_script, on_dialogue, on_choice, on_finish,
                        save_data, nil, options
                    )
                else
                    result[1] = {false, output[1], expected, "Error parsing restoreInput script"}
                end
            else
                __loreline_Loreline.resume(
                    parsed_script[1], on_dialogue, on_choice, on_finish,
                    save_data, nil, options
                )
            end
            return
        end

        dialogue_count[1] = dialogue_count[1] + 1
        advance()
    end

    local ok, err = pcall(function()
        local script = __loreline_Loreline.parse(content, file_path, handle_file)
        if script then
            parsed_script[1] = script
            __loreline_Loreline.play(
                script, on_dialogue, on_choice, on_finish, beat_name, options
            )
        else
            result[1] = {false, output[1], expected, "Error parsing script"}
        end
    end)

    if not ok then
        result[1] = {false, output[1], expected, tostring(err)}
    end

    if result[1] == nil then
        result[1] = {false, output[1], expected, "Test did not produce a result"}
    end

    return result[1][1], result[1][2], result[1][3], result[1][4]
end

-- ── Main ─────────────────────────────────────────────────────────────────

local function main()
    if #arg < 1 then
        io.stderr:write("Usage: lua lua/test-runner.lua <test-directory>\n")
        os.exit(1)
    end

    local test_dir = arg[1]
    local test_files = collect_test_files(test_dir)

    if #test_files == 0 then
        io.stderr:write("No test files found in " .. test_dir .. "\n")
        os.exit(1)
    end

    for _, file_path in ipairs(test_files) do
        local raw_content = read_file(file_path)
        if not raw_content then goto next_file end

        local test_items = extract_tests(raw_content)
        if #test_items == 0 then goto next_file end

        file_count = file_count + 1
        local file_fail_before = fail_count

        for _, item in ipairs(test_items) do
            for _, crlf in ipairs({false, true}) do
                local mode_label = crlf and "CRLF" or "LF"
                local choices_label = ""
                if item.choices then
                    local parts = {}
                    for _, c in ipairs(item.choices) do
                        table.insert(parts, tostring(c))
                    end
                    choices_label = " ~ [" .. table.concat(parts, ",") .. "]"
                end
                local label = file_path .. " ~ " .. mode_label .. choices_label

                local passed, actual, expected_str, error_msg = run_test(file_path, raw_content, item, crlf)

                if passed then
                    pass_count = pass_count + 1
                    io.write("\027[1m\027[32mPASS\027[0m - \027[90m" .. label .. "\027[0m\n")
                else
                    fail_count = fail_count + 1
                    io.write("\027[1m\027[31mFAIL\027[0m - \027[90m" .. label .. "\027[0m\n")
                    if error_msg then
                        io.write("  Error: " .. error_msg .. "\n")
                    end

                    -- Show diff
                    if expected_str and actual then
                        local function split(s)
                            s = s:gsub("\r\n", "\n"):match("^%s*(.-)%s*$") or ""
                            local lines = {}
                            for line in (s .. "\n"):gmatch("([^\n]*)\n") do
                                table.insert(lines, line)
                            end
                            return lines
                        end
                        local el = split(expected_str)
                        local al = split(actual)
                        local ml = math.min(#el, #al)
                        local shown = false
                        for i = 1, ml do
                            if el[i] ~= al[i] then
                                io.write("  > Unexpected output at line " .. i .. "\n")
                                io.write("  >  got: " .. al[i] .. "\n")
                                io.write("  > need: " .. el[i] .. "\n")
                                shown = true
                                break
                            end
                        end
                        if not shown and ml < math.max(#el, #al) then
                            if ml < #al then
                                io.write("  > Unexpected output at line " .. (ml + 1) .. "\n")
                                io.write("  >  got: " .. al[ml + 1] .. "\n")
                                io.write("  > need: (empty)\n")
                            else
                                io.write("  > Unexpected output at line " .. (ml + 1) .. "\n")
                                io.write("  >  got: (empty)\n")
                                io.write("  > need: " .. el[ml + 1] .. "\n")
                            end
                        end
                    end
                end
            end
        end

        -- Roundtrip tests for each mode
        for _, crlf in ipairs({false, true}) do
            local mode_label = crlf and "CRLF" or "LF"
            local label = file_path .. " ~ " .. mode_label .. " ~ roundtrip"
            local newline = crlf and "\r\n" or "\n"

            local ok2, err2 = pcall(function()
                local content = raw_content:gsub("\r\n", "\n")
                if crlf then
                    content = content:gsub("\n", "\r\n")
                end

                local script1 = __loreline_Loreline.parse(content, file_path, handle_file)
                if not script1 then
                    fail_count = fail_count + 1
                    io.write("\027[1m\027[31mFAIL\027[0m - \027[90m" .. label .. "\027[0m\n")
                    io.write("  Error: Failed to parse original script\n")
                    return
                end

                local print1 = __loreline_Loreline.print(script1, "  ", newline)
                local script2 = __loreline_Loreline.parse(print1, file_path, handle_file)
                if not script2 then
                    fail_count = fail_count + 1
                    io.write("\027[1m\027[31mFAIL\027[0m - \027[90m" .. label .. "\027[0m\n")
                    io.write("  Error: Failed to parse printed script\n")
                    return
                end
                local print2 = __loreline_Loreline.print(script2, "  ", newline)

                if print1 ~= print2 then
                    fail_count = fail_count + 1
                    io.write("\027[1m\027[31mFAIL\027[0m - \027[90m" .. label .. "\027[0m\n")
                    local function split_nl(s)
                        local lines = {}
                        for line in (s:gsub("\r\n", "\n") .. "\n"):gmatch("([^\n]*)\n") do
                            table.insert(lines, line)
                        end
                        return lines
                    end
                    local l1 = split_nl(print1)
                    local l2 = split_nl(print2)
                    local ml = math.min(#l1, #l2)
                    for i = 1, ml do
                        if l1[i] ~= l2[i] then
                            io.write("  > Printer output not idempotent at line " .. i .. "\n")
                            io.write("  >  print1: " .. l1[i] .. "\n")
                            io.write("  >  print2: " .. l2[i] .. "\n")
                            break
                        end
                    end
                    if #l1 ~= #l2 then
                        io.write("  > Line count differs: print1=" .. #l1 .. ", print2=" .. #l2 .. "\n")
                    end
                    return
                end

                -- Behavioral check
                local all_passed = true
                local first_error = nil

                for _, item in ipairs(test_items) do
                    local passed, actual, expected_str, error_msg = run_test(
                        file_path, print1, item, crlf
                    )
                    if not passed then
                        all_passed = false
                        if not first_error then
                            first_error = error_msg
                        end
                    end
                end

                if all_passed then
                    pass_count = pass_count + 1
                    io.write("\027[1m\027[32mPASS\027[0m - \027[90m" .. label .. "\027[0m\n")
                else
                    fail_count = fail_count + 1
                    io.write("\027[1m\027[31mFAIL\027[0m - \027[90m" .. label .. "\027[0m\n")
                    if first_error then
                        io.write("  Error: " .. first_error .. "\n")
                    end
                end
            end)

            if not ok2 then
                fail_count = fail_count + 1
                io.write("\027[1m\027[31mFAIL\027[0m - \027[90m" .. label .. "\027[0m\n")
                io.write("  Error: " .. tostring(err2) .. "\n")
            end
        end

        if fail_count > file_fail_before then
            file_fail_count = file_fail_count + 1
        end

        ::next_file::
    end

    local total = pass_count + fail_count
    io.write("\n")
    if fail_count == 0 then
        io.write("\027[1m\027[32m  All " .. total .. " tests passed (" .. file_count .. " files)\027[0m\n")
    else
        io.write("\027[1m\027[31m  " .. fail_count .. " of " .. total .. " tests failed (" .. file_fail_count .. " of " .. file_count .. " files)\027[0m\n")
        os.exit(1)
    end
end

main()
