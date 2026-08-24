/*
 * Loreline C++ Library: Full Test Runner
 *
 * Reads .lor test files, parses <test> YAML blocks, runs all tests
 * (including save/restore, translations, roundtrips, LF/CRLF), and
 * validates output against expected results.
 *
 * Note: ast-print is intentionally only run by the CLI test runner.
 * AstPrinter is a pure Haxe debug pretty-printer with no target-specific
 * behavior, so a single CLI run is enough to catch any missing node-type
 * case. That's why the CLI test count is higher than each per-target
 * runner's count.
 *
 * Compile with C++17 (for std::filesystem):
 *   clang++ -std=c++17 -o test_runner test_runner.cpp \
 *     -Icpp/include -L<builddir> -lLoreline -Wl,-rpath,@executable_path
 */

#include "Loreline.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <functional>
#include <set>
#include <sstream>
#include <string>
#include <vector>

namespace fs = std::filesystem;

/* -- Globals -------------------------------------------------------------- */

static int passCount = 0;
static int failCount = 0;
static int fileCount = 0;
static int fileFailCount = 0;

/* -- ANSI color helpers --------------------------------------------------- */

#define CLR_BOLD_GREEN "\x1b[1m\x1b[32m"
#define CLR_BOLD_RED   "\x1b[1m\x1b[31m"
#define CLR_GRAY       "\x1b[90m"
#define CLR_RESET      "\x1b[0m"

/* -- Utility -------------------------------------------------------------- */

static std::string readFile(const std::string& path) {
    std::ifstream f(path, std::ios::binary);
    if (!f.is_open()) return "";
    std::ostringstream ss;
    ss << f.rdbuf();
    return ss.str();
}

static std::string replaceAll(const std::string& s, const std::string& from, const std::string& to) {
    if (from.empty()) return s;
    std::string result;
    size_t pos = 0;
    size_t prev = 0;
    while ((pos = s.find(from, prev)) != std::string::npos) {
        result.append(s, prev, pos - prev);
        result.append(to);
        prev = pos + from.size();
    }
    result.append(s, prev, std::string::npos);
    return result;
}

static std::string trim(const std::string& s) {
    size_t start = s.find_first_not_of(" \t\r\n");
    if (start == std::string::npos) return "";
    size_t end = s.find_last_not_of(" \t\r\n");
    return s.substr(start, end - start + 1);
}

static std::string trimEnd(const std::string& s) {
    size_t end = s.find_last_not_of(" \t\r\n");
    if (end == std::string::npos) return "";
    return s.substr(0, end + 1);
}

static std::vector<std::string> splitLines(const std::string& s) {
    std::vector<std::string> lines;
    std::istringstream stream(s);
    std::string line;
    while (std::getline(stream, line)) {
        lines.push_back(line);
    }
    return lines;
}

static bool endsWith(const std::string& s, const std::string& suffix) {
    if (suffix.size() > s.size()) return false;
    return s.compare(s.size() - suffix.size(), suffix.size(), suffix) == 0;
}

static bool startsWith(const std::string& s, const std::string& prefix) {
    if (prefix.size() > s.size()) return false;
    return s.compare(0, prefix.size(), prefix) == 0;
}

/* -- Test item struct ----------------------------------------------------- */

struct TestItem {
    std::string beat;
    std::vector<int> choices;
    bool hasChoices = false;
    std::string expected;
    int saveAtChoice = -1;
    int saveAtDialogue = -1;
    std::string restoreFile;
    std::string translation;
};

/* -- File handler for Loreline_parse -------------------------------------- */

static void fileHandler(Loreline_String path, Loreline_FileRequest* request, void* userData) {
    std::string content = readFile(path.c_str());
    if (content.empty()) {
        Loreline_provideFile(request, Loreline_String());
    } else {
        Loreline_provideFile(request, Loreline_String(content.c_str()));
    }
}

/* -- Test file collection ------------------------------------------------- */

static std::vector<std::string> collectTestFiles(const std::string& dir) {
    std::vector<std::string> files;

    for (auto& entry : fs::directory_iterator(dir)) {
        std::string name = entry.path().filename().string();
        if (entry.is_directory()) {
            if (name != "imports" && name != "modified") {
                auto sub = collectTestFiles(entry.path().string());
                files.insert(files.end(), sub.begin(), sub.end());
            }
        } else if (endsWith(name, ".lor")) {
            /* Skip translation files like *.xx.lor (two-letter code before .lor) */
            size_t dotLor = name.size() - 4; /* position of ".lor" */
            if (dotLor >= 3 && name[dotLor - 3] == '.') {
                /* Check if the two chars before .lor are alpha: e.g. ".fr.lor" */
                char c1 = name[dotLor - 2];
                char c2 = name[dotLor - 1];
                if (std::isalpha(c1) && std::isalpha(c2)) {
                    continue; /* skip translation file */
                }
            }
            files.push_back(entry.path().string());
        }
    }

    std::sort(files.begin(), files.end());
    return files;
}

/* -- Parse [1, 2, 3] int list --------------------------------------------- */

static std::vector<int> parseIntList(const std::string& value) {
    std::vector<int> result;
    std::string v = value;

    /* Strip brackets */
    if (!v.empty() && v[0] == '[') v = v.substr(1);
    if (!v.empty() && v.back() == ']') v.pop_back();
    v = trim(v);
    if (v.empty()) return result;

    std::istringstream ss(v);
    std::string token;
    while (std::getline(ss, token, ',')) {
        token = trim(token);
        if (!token.empty()) {
            result.push_back(std::stoi(token));
        }
    }
    return result;
}

/* -- Extract <test> blocks and parse YAML --------------------------------- */

static std::vector<TestItem> parseTestItems(const std::string& yaml) {
    std::vector<TestItem> items;
    auto lines = splitLines(replaceAll(yaml, "\r\n", "\n"));
    TestItem* current = nullptr;
    std::string currentKey;
    std::string blockValue;
    bool inBlock = false;
    int blockIndent = 0;

    for (size_t i = 0; i < lines.size(); i++) {
        const std::string& line = lines[i];

        /* Collect block scalar lines (for "expected: |") */
        if (inBlock) {
            std::string trimmedLine = trim(line);
            if (!trimmedLine.empty()) {
                int indent = (int)(line.size() - line.size());
                /* Count leading spaces */
                indent = 0;
                for (size_t j = 0; j < line.size(); j++) {
                    if (line[j] == ' ') indent++;
                    else break;
                }
                if (indent >= blockIndent) {
                    blockValue += line.substr(blockIndent) + "\n";
                    continue;
                }
            } else {
                blockValue += "\n";
                continue;
            }

            /* Block ended */
            if (currentKey == "expected" && current) {
                current->expected = blockValue;
            }
            inBlock = false;
            currentKey.clear();
        }

        /* Trim leading whitespace */
        std::string trimmed = line;
        size_t firstNonSpace = line.find_first_not_of(' ');
        if (firstNonSpace != std::string::npos) {
            trimmed = line.substr(firstNonSpace);
        } else {
            trimmed = "";
        }

        /* New list item */
        if (startsWith(trimmed, "- ")) {
            items.emplace_back();
            current = &items.back();
            trimmed = trim(trimmed.substr(2));
        } else if (trimmed.empty() || !current) {
            continue;
        }

        /* Parse key: value */
        size_t colonIdx = trimmed.find(':');
        if (colonIdx == 0 || colonIdx == std::string::npos) continue;

        std::string key = trim(trimmed.substr(0, colonIdx));
        std::string value = trim(trimmed.substr(colonIdx + 1));

        if (key == "beat") {
            current->beat = value;
        } else if (key == "choices") {
            current->choices = parseIntList(value);
            current->hasChoices = true;
        } else if (key == "expected") {
            if (value == "|") {
                currentKey = "expected";
                blockValue.clear();
                inBlock = true;
                blockIndent = 0;
                /* Determine block indent from next non-empty line */
                for (size_t j = i + 1; j < lines.size(); j++) {
                    if (!trim(lines[j]).empty()) {
                        blockIndent = 0;
                        for (size_t k = 0; k < lines[j].size(); k++) {
                            if (lines[j][k] == ' ') blockIndent++;
                            else break;
                        }
                        break;
                    }
                }
            } else {
                current->expected = value;
            }
        } else if (key == "saveAtChoice") {
            current->saveAtChoice = std::stoi(value);
        } else if (key == "saveAtDialogue") {
            current->saveAtDialogue = std::stoi(value);
        } else if (key == "restoreFile") {
            current->restoreFile = value;
        } else if (key == "translation") {
            current->translation = value;
        }
    }

    /* Flush final block */
    if (inBlock && current && currentKey == "expected") {
        current->expected = blockValue;
    }

    return items;
}

static std::vector<TestItem> extractTests(const std::string& content) {
    std::vector<TestItem> tests;
    std::string searchStr = "<test>";
    std::string endStr = "</test>";
    size_t pos = 0;

    while ((pos = content.find(searchStr, pos)) != std::string::npos) {
        size_t start = pos + searchStr.size();
        size_t end = content.find(endStr, start);
        if (end == std::string::npos) break;

        std::string yamlContent = trim(content.substr(start, end - start));
        auto items = parseTestItems(yamlContent);
        tests.insert(tests.end(), items.begin(), items.end());
        pos = end + endStr.size();
    }

    return tests;
}

/* -- Insert tags into text ------------------------------------------------ */

static std::string insertTagsInText(const char* text, const Loreline_TextTag* tags, int tagCount, bool multiline) {
    if (!text) return "";

    std::set<int> offsetsWithTags;
    for (int i = 0; i < tagCount; i++) {
        offsetsWithTags.insert(tags[i].offset);
    }

    int len = (int)strlen(text);
    std::string result;

    for (int i = 0; i < len; i++) {
        if (offsetsWithTags.count(i)) {
            for (int t = 0; t < tagCount; t++) {
                if (tags[t].offset == i) {
                    result += "<<";
                    if (tags[t].closing) result += "/";
                    result += tags[t].value.c_str();
                    result += ">>";
                }
            }
        }
        char c = text[i];
        if (multiline && c == '\n') {
            result += "\n  ";
        } else {
            result += c;
        }
    }

    /* Tags at or beyond end of text */
    for (int t = 0; t < tagCount; t++) {
        if (tags[t].offset >= len) {
            result += "<<";
            if (tags[t].closing) result += "/";
            result += tags[t].value.c_str();
            result += ">>";
        }
    }

    return trimEnd(result);
}

/* -- Compare output ------------------------------------------------------- */

static int compareOutput(const std::string& expected, const std::string& actual) {
    auto expectedLines = splitLines(trim(replaceAll(expected, "\r\n", "\n")));
    auto actualLines = splitLines(trim(replaceAll(actual, "\r\n", "\n")));
    size_t minLen = std::min(expectedLines.size(), actualLines.size());
    size_t maxLen = std::max(expectedLines.size(), actualLines.size());

    for (size_t i = 0; i < minLen; i++) {
        if (expectedLines[i] != actualLines[i]) return (int)i;
    }
    if (minLen < maxLen) return (int)minLen;
    return -1;
}

static void showDiff(const std::string& expected, const std::string& actual) {
    auto expectedLines = splitLines(trim(replaceAll(expected, "\r\n", "\n")));
    auto actualLines = splitLines(trim(replaceAll(actual, "\r\n", "\n")));
    size_t minLen = std::min(expectedLines.size(), actualLines.size());

    for (size_t i = 0; i < minLen; i++) {
        if (expectedLines[i] != actualLines[i]) {
            printf("  > Unexpected output at line %zu\n", i + 1);
            printf("  >  got: %s\n", actualLines[i].c_str());
            printf("  > need: %s\n", expectedLines[i].c_str());
            return;
        }
    }
    if (minLen < std::max(expectedLines.size(), actualLines.size())) {
        if (minLen < actualLines.size()) {
            printf("  > Unexpected output at line %zu\n", minLen + 1);
            printf("  >  got: %s\n", actualLines[minLen].c_str());
            printf("  > need: (empty)\n");
        } else {
            printf("  > Unexpected output at line %zu\n", minLen + 1);
            printf("  >  got: (empty)\n");
            printf("  > need: %s\n", expectedLines[minLen].c_str());
        }
    }
}

/* -- Test result ---------------------------------------------------------- */

struct TestResult {
    bool passed = false;
    std::string actual;
    std::string expected;
    std::string error;
};

/* -- Run a single test ---------------------------------------------------- */

struct TestContext {
    std::string* output;
    std::vector<int> choices;
    std::string expected;
    int saveAtChoice;
    int saveAtDialogue;
    int choiceCount;
    int dialogueCount;
    TestResult* result;
    Loreline_Script* parsedScript;

    /* For save/restore */
    std::string restoreInput;
    std::string filePath;
    Loreline_InterpreterOptions* options;
};

/* Forward declarations */
static void testChoice(
    Loreline_Interpreter* interp,
    const Loreline_ChoiceOption* options,
    int optionCount,
    Loreline_Select select,
    void* userData
);

static void testFinish(
    Loreline_Interpreter* interp,
    void* userData
);

static void testDialogue(
    Loreline_Interpreter* interp,
    Loreline_String character,
    Loreline_String text,
    const Loreline_TextTag* tags,
    int tagCount,
    Loreline_Advance advance,
    void* userData
) {
    TestContext* ctx = (TestContext*)userData;
    bool multiline = text.c_str() && strchr(text.c_str(), '\n') != nullptr;

    if (!character.isNull()) {
        Loreline_Value nameVal = Loreline_getCharacterField(interp, character, "name");
        const char* charName = (nameVal.type == Loreline_StringValue && !nameVal.stringValue.isNull())
            ? nameVal.stringValue.c_str()
            : character.c_str();
        std::string taggedText = insertTagsInText(text.c_str(), tags, tagCount, multiline);
        if (multiline) {
            *ctx->output += std::string(charName) + ":\n  " + taggedText + "\n\n";
        } else {
            *ctx->output += std::string(charName) + ": " + taggedText + "\n\n";
        }
    } else {
        std::string taggedText = insertTagsInText(text.c_str(), tags, tagCount, multiline);
        *ctx->output += "~ " + taggedText + "\n\n";
    }

    /* Save/restore test at dialogue */
    if (ctx->saveAtDialogue >= 0 && ctx->dialogueCount == ctx->saveAtDialogue) {
        ctx->dialogueCount++;
        Loreline_String saveData = Loreline_save(interp);

        if (!ctx->restoreInput.empty()) {
            Loreline_Script* restoreScript = Loreline_parse(
                ctx->restoreInput.c_str(), ctx->filePath.c_str(), fileHandler, nullptr);
            if (restoreScript) {
                Loreline_Interpreter* resumed = Loreline_resume(
                    restoreScript, testDialogue, testChoice, testFinish,
                    saveData, Loreline_String(), ctx->options, ctx);
                Loreline_releaseInterpreter(resumed);
                Loreline_releaseScript(restoreScript);
            } else {
                ctx->result->passed = false;
                ctx->result->actual = *ctx->output;
                ctx->result->error = "Error parsing restoreInput script";
            }
        } else {
            Loreline_Interpreter* resumed = Loreline_resume(
                ctx->parsedScript, testDialogue, testChoice, testFinish,
                saveData, Loreline_String(), ctx->options, ctx);
            Loreline_releaseInterpreter(resumed);
        }
        return;
    }

    ctx->dialogueCount++;
    advance();
}

static void testFinish(
    Loreline_Interpreter* interp,
    void* userData
) {
    TestContext* ctx = (TestContext*)userData;
    int cmp = compareOutput(ctx->expected, *ctx->output);
    ctx->result->passed = (cmp == -1);
    ctx->result->actual = *ctx->output;
}

static void testChoice(
    Loreline_Interpreter* interp,
    const Loreline_ChoiceOption* options,
    int optionCount,
    Loreline_Select select,
    void* userData
) {
    TestContext* ctx = (TestContext*)userData;

    for (int i = 0; i < optionCount; i++) {
        const char* prefix = options[i].enabled ? "+" : "-";
        bool multiline = options[i].text.c_str() && strchr(options[i].text.c_str(), '\n') != nullptr;
        std::string taggedText = insertTagsInText(
            options[i].text.c_str(), options[i].tags, options[i].tagCount, multiline);
        *ctx->output += std::string(prefix) + " " + taggedText + "\n";
    }
    *ctx->output += "\n";

    /* Save/restore test */
    if (ctx->saveAtChoice >= 0 && ctx->choiceCount == ctx->saveAtChoice) {
        ctx->choiceCount++;
        Loreline_String saveData = Loreline_save(interp);

        if (!ctx->restoreInput.empty()) {
            Loreline_Script* restoreScript = Loreline_parse(
                ctx->restoreInput.c_str(), ctx->filePath.c_str(), fileHandler, nullptr);
            if (restoreScript) {
                Loreline_Interpreter* resumed = Loreline_resume(
                    restoreScript, testDialogue, testChoice, testFinish,
                    saveData, Loreline_String(), ctx->options, ctx);
                Loreline_releaseInterpreter(resumed);
                Loreline_releaseScript(restoreScript);
            } else {
                ctx->result->passed = false;
                ctx->result->actual = *ctx->output;
                ctx->result->error = "Error parsing restoreInput script";
            }
        } else {
            Loreline_Interpreter* resumed = Loreline_resume(
                ctx->parsedScript, testDialogue, testChoice, testFinish,
                saveData, Loreline_String(), ctx->options, ctx);
            Loreline_releaseInterpreter(resumed);
        }
        return;
    }

    ctx->choiceCount++;

    if (ctx->choices.empty()) {
        /* No more choices: treat as finish */
        testFinish(interp, userData);
    } else {
        int index = ctx->choices[0];
        ctx->choices.erase(ctx->choices.begin());
        select(index);
    }
}

/* -- Canonical custom functions ---------------------------------------------
 * Used by test/Functions-Custom.lor to verify the custom-function contract via
 * the C API: each receives (interp, args, argCount), where args is an array and
 * the interpreter can read/write runtime state. The linc layer already adapts
 * the core's positional call to this signature (Reflect.makeVarArgs). */

static std::string lorelineValueToString(const Loreline_Value& v) {
    switch (v.type) {
        case Loreline_StringValue: return v.stringValue.c_str() ? std::string(v.stringValue.c_str()) : "";
        case Loreline_Int: return std::to_string(v.intValue);
        case Loreline_Float: return std::to_string(v.floatValue);
        case Loreline_Bool: return v.boolValue ? "true" : "false";
        default: return "";
    }
}

static Loreline_Value custom_echo(Loreline_Interpreter* interp, const Loreline_Value* args, int argCount, void* userData) {
    std::string result;
    for (int i = 0; i < argCount; i++) {
        if (i > 0) result += ",";
        result += lorelineValueToString(args[i]);
    }
    return Loreline_Value::from_string(Loreline_String(result.c_str()));
}

static Loreline_Value custom_arg_count(Loreline_Interpreter* interp, const Loreline_Value* args, int argCount, void* userData) {
    return Loreline_Value::from_int(argCount);
}

static Loreline_Value custom_set_state(Loreline_Interpreter* interp, const Loreline_Value* args, int argCount, void* userData) {
    if (argCount >= 2 && args[0].type == Loreline_StringValue) {
        Loreline_setStateField(interp, args[0].stringValue, args[1]);
    }
    return Loreline_Value::null_val();
}

static Loreline_Value custom_get_state(Loreline_Interpreter* interp, const Loreline_Value* args, int argCount, void* userData) {
    if (argCount >= 1 && args[0].type == Loreline_StringValue) {
        return Loreline_getStateField(interp, args[0].stringValue);
    }
    return Loreline_Value::null_val();
}

static void addCustomTestFunctions(Loreline_InterpreterOptions* options) {
    Loreline_optionsAddFunction(options, Loreline_String("custom_echo"), custom_echo, nullptr);
    Loreline_optionsAddFunction(options, Loreline_String("custom_arg_count"), custom_arg_count, nullptr);
    Loreline_optionsAddFunction(options, Loreline_String("custom_set_state"), custom_set_state, nullptr);
    Loreline_optionsAddFunction(options, Loreline_String("custom_get_state"), custom_get_state, nullptr);
}

static TestResult runTest(const std::string& filePath, const std::string& rawContent,
                          const TestItem& item, bool crlf) {
    /* Normalize line endings */
    std::string content = replaceAll(rawContent, "\r\n", "\n");
    if (crlf) {
        content = replaceAll(content, "\n", "\r\n");
    }

    std::string output;
    TestResult result;
    result.expected = item.expected;

    /* Translations and options will be built after parsing the script */
    Loreline_Translations* translations = nullptr;
    Loreline_InterpreterOptions* options = nullptr;

    /* Load restoreFile content */
    std::string restoreInput;
    if (!item.restoreFile.empty()) {
        fs::path restorePath = fs::path(filePath).parent_path() / item.restoreFile;
        restoreInput = readFile(restorePath.string());
        if (!restoreInput.empty()) {
            restoreInput = replaceAll(restoreInput, "\r\n", "\n");
            if (crlf) {
                restoreInput = replaceAll(restoreInput, "\n", "\r\n");
            }
        }
    }

    /* Set up test context */
    TestContext ctx;
    ctx.output = &output;
    ctx.choices = item.hasChoices ? item.choices : std::vector<int>();
    ctx.expected = item.expected;
    ctx.saveAtChoice = item.saveAtChoice;
    ctx.saveAtDialogue = item.saveAtDialogue;
    ctx.choiceCount = 0;
    ctx.dialogueCount = 0;
    ctx.result = &result;
    ctx.parsedScript = nullptr;
    ctx.restoreInput = restoreInput;
    ctx.filePath = filePath;
    ctx.options = options;

    /* Parse and play */
    Loreline_Script* script = Loreline_parse(content.c_str(), filePath.c_str(), fileHandler, nullptr);
    if (script) {
        /* Always register the canonical custom functions; add translations
         * (walked across the import tree) if requested */
        options = Loreline_createOptions();
        addCustomTestFunctions(options);
        ctx.options = options;
        if (!item.translation.empty()) {
            translations = Loreline_loadLocale(
                item.translation.c_str(), script, Loreline_String(), fileHandler, nullptr);
            if (translations) {
                Loreline_optionsSetTranslations(options, translations);
            }
        }

        ctx.parsedScript = script;
        Loreline_Interpreter* interp = Loreline_play(
            script, testDialogue, testChoice, testFinish,
            item.beat.empty() ? Loreline_String() : Loreline_String(item.beat.c_str()),
            options, &ctx);
        if (interp) {
            Loreline_releaseInterpreter(interp);
        }
        Loreline_releaseScript(script);
    } else {
        result.passed = false;
        result.actual = output;
        result.error = "Error parsing script";
    }

    if (options) {
        Loreline_releaseOptions(options);
    }
    if (translations) {
        Loreline_releaseTranslations(translations);
    }

    return result;
}

/* -- Programmatic container field test ------------------------------------- */
/* Exercises the Loreline_Array / Loreline_Object value model through the
 * state and character field accessors: script-declared containers read
 * from C++, host-built containers set and read back, deep-copy snapshot
 * semantics, and nested values. Runs while the interpreter is paused at
 * its first dialogue (live, stable point to call the accessors). */

static void containerTestCheck(Loreline_Interpreter* interp, bool* okOut, std::string* errorOut) {
    bool ok = true;
    std::string error;

    /* 1. Read a script-declared array */
    Loreline_Value inv = Loreline_getStateField(interp, Loreline_String("inventory"));
    if (inv.type != Loreline_ArrayValue) { ok = false; error = "inventory is not an array"; }
    else if (inv.arrayValue.length() != 2) { ok = false; error = "inventory length != 2"; }
    else {
        Loreline_Value item0 = inv.arrayValue.get(0);
        if (item0.type != Loreline_StringValue || strcmp(item0.stringValue.c_str(), "sword") != 0) {
            ok = false; error = "inventory[0] != sword";
        }
    }

    /* 2. Read a script-declared object with nested values */
    if (ok) {
        Loreline_Value prof = Loreline_getStateField(interp, Loreline_String("profile"));
        if (prof.type != Loreline_ObjectValue) { ok = false; error = "profile is not an object"; }
        else {
            Loreline_Value name = prof.objectValue.get("name");
            Loreline_Value level = prof.objectValue.get("level");
            if (name.type != Loreline_StringValue || strcmp(name.stringValue.c_str(), "Ana") != 0) {
                ok = false; error = "profile.name != Ana";
            }
            else if (level.type != Loreline_Int || level.intValue != 3) {
                ok = false; error = "profile.level != 3";
            }
        }
    }

    /* 3. Build a nested container host-side, set it, read it back */
    if (ok) {
        Loreline_Array items = Loreline_Array::create();
        items.push(Loreline_Value::from_string(Loreline_String("potion")));
        items.push(Loreline_Value::from_int(42));
        Loreline_Object payload = Loreline_Object::create();
        payload.set("items", Loreline_Value::from_array(items));
        payload.set("active", Loreline_Value::from_bool(true));
        Loreline_setStateField(interp, Loreline_String("payload"), Loreline_Value::from_object(payload));

        Loreline_Value back = Loreline_getStateField(interp, Loreline_String("payload"));
        if (back.type != Loreline_ObjectValue) { ok = false; error = "payload did not round-trip as object"; }
        else {
            Loreline_Value backItems = back.objectValue.get("items");
            Loreline_Value backActive = back.objectValue.get("active");
            if (backItems.type != Loreline_ArrayValue || backItems.arrayValue.length() != 2) {
                ok = false; error = "payload.items did not round-trip";
            }
            else if (backItems.arrayValue.get(1).type != Loreline_Int || backItems.arrayValue.get(1).intValue != 42) {
                ok = false; error = "payload.items[1] != 42";
            }
            else if (backActive.type != Loreline_Bool || !backActive.boolValue) {
                ok = false; error = "payload.active != true";
            }
        }
    }

    /* 4. Deep-copy snapshot semantics: mutating a returned copy must
     * not affect interpreter state until set back */
    if (ok) {
        Loreline_Value copy = Loreline_getStateField(interp, Loreline_String("payload"));
        copy.objectValue.set("active", Loreline_Value::from_bool(false));
        Loreline_Value fresh = Loreline_getStateField(interp, Loreline_String("payload"));
        Loreline_Value freshActive = fresh.objectValue.get("active");
        if (freshActive.type != Loreline_Bool || !freshActive.boolValue) {
            ok = false; error = "mutating a returned copy leaked into interpreter state";
        }
    }

    /* 5. Character field containers */
    if (ok) {
        Loreline_Array traits = Loreline_Array::create();
        traits.push(Loreline_Value::from_string(Loreline_String("bold")));
        Loreline_setCharacterField(interp, Loreline_String("ana"), Loreline_String("traits"), Loreline_Value::from_array(traits));
        Loreline_Value backTraits = Loreline_getCharacterField(interp, Loreline_String("ana"), Loreline_String("traits"));
        if (backTraits.type != Loreline_ArrayValue || backTraits.arrayValue.length() != 1) {
            ok = false; error = "character traits did not round-trip";
        }
    }

    /* 6. Beat references cross as their beat name string */
    if (ok) {
        Loreline_Value ref = Loreline_getStateField(interp, Loreline_String("ref"));
        if (ref.type != Loreline_StringValue || strcmp(ref.stringValue.c_str(), "Main") != 0) {
            ok = false; error = "beat reference did not read as its name string";
        }
    }

    *okOut = ok;
    *errorOut = error;
}

struct ContainerTestContext {
    bool ok = false;
    std::string error = "dialogue handler never ran";
};

static void containerTestDialogue(
    Loreline_Interpreter* interp,
    Loreline_String character,
    Loreline_String text,
    const Loreline_TextTag* tags,
    int tagCount,
    Loreline_Advance advance,
    void* userData
) {
    ContainerTestContext* ctx = (ContainerTestContext*)userData;
    containerTestCheck(interp, &ctx->ok, &ctx->error);
    advance();
}

static void containerTestChoice(
    Loreline_Interpreter* interp,
    const Loreline_ChoiceOption* options,
    int optionCount,
    Loreline_Select select,
    void* userData
) {
    select(0);
}

static void containerTestFinish(Loreline_Interpreter* interp, void* userData) {}

static void runContainerFieldTest() {
    const char* source =
        "\n"
        "character ana\n"
        "  name: Ana\n"
        "\n"
        "state\n"
        "  inventory: [sword, shield]\n"
        "  profile: { name: Ana, level: 3 }\n"
        "  ref: null\n"
        "\n"
        "beat Main\n"
        "  ref = Main\n"
        "  Checking fields.\n";

    ContainerTestContext ctx;

    Loreline_Script* script = Loreline_parse(source, "container-fields.lor", nullptr, nullptr);
    if (script) {
        Loreline_Interpreter* interp = Loreline_play(
            script, containerTestDialogue, containerTestChoice, containerTestFinish,
            Loreline_String(), nullptr, &ctx);
        if (interp) {
            Loreline_releaseInterpreter(interp);
        }
        Loreline_releaseScript(script);
    } else {
        ctx.ok = false;
        ctx.error = "Error parsing container fields script";
    }

    if (ctx.ok) {
        passCount++;
        printf(CLR_BOLD_GREEN "PASS" CLR_RESET " - " CLR_GRAY "capi ~ container fields round-trip" CLR_RESET "\n");
    } else {
        failCount++;
        fileFailCount++;
        printf(CLR_BOLD_RED "FAIL" CLR_RESET " - " CLR_GRAY "capi ~ container fields round-trip" CLR_RESET "\n");
        printf("  > %s\n", ctx.error.c_str());
    }
    fflush(stdout);
}

/* -- Main ----------------------------------------------------------------- */

int main(int argc, char* argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: test_runner <test-directory>\n");
        return 1;
    }

    std::string testDir = argv[1];

    /* Disable stdout buffering so all output is visible immediately (important on Windows CI) */
    setvbuf(stdout, NULL, _IONBF, 0);

    Loreline_init();

    /* Test fixtures exercise every supported translation format. */
    Loreline_translationFormat(Loreline_String("po"), true);
    Loreline_translationFormat(Loreline_String("xliff"), true);
    Loreline_translationFormat(Loreline_String("csv"), true);

    auto testFiles = collectTestFiles(testDir);
    if (testFiles.empty()) {
        fprintf(stderr, "No test files found in %s\n", testDir.c_str());
        Loreline_dispose();
        return 1;
    }

    for (const auto& filePath : testFiles) {
        std::string rawContent = readFile(filePath);
        auto testItems = extractTests(rawContent);
        if (testItems.empty()) continue;

        fileCount++;
        int failBefore = failCount;

        /* Run each test item x {LF, CRLF} */
        for (const auto& item : testItems) {
            for (int mode = 0; mode < 2; mode++) {
                bool crlf = (mode == 1);
                std::string modeLabel = crlf ? "CRLF" : "LF";
                std::string choicesLabel;
                if (item.hasChoices) {
                    choicesLabel = " ~ [";
                    for (size_t i = 0; i < item.choices.size(); i++) {
                        if (i > 0) choicesLabel += ",";
                        choicesLabel += std::to_string(item.choices[i]);
                    }
                    choicesLabel += "]";
                }
                std::string label = filePath + " ~ " + modeLabel + choicesLabel;

                auto result = runTest(filePath, rawContent, item, crlf);

                if (result.passed) {
                    passCount++;
                    printf(CLR_BOLD_GREEN "PASS" CLR_RESET " - " CLR_GRAY "%s" CLR_RESET "\n", label.c_str());
                } else {
                    failCount++;
                    printf(CLR_BOLD_RED "FAIL" CLR_RESET " - " CLR_GRAY "%s" CLR_RESET "\n", label.c_str());
                    if (!result.error.empty()) {
                        printf("  Error: %s\n", result.error.c_str());
                    }
                    showDiff(result.expected, result.actual);
                }
            }
        }

        /* Roundtrip tests for each mode (LF, CRLF) */
        for (int mode = 0; mode < 2; mode++) {
            bool crlf = (mode == 1);
            std::string modeLabel = crlf ? "CRLF" : "LF";
            std::string label = filePath + " ~ " + modeLabel + " ~ roundtrip";

            /* Normalize content */
            std::string content = replaceAll(rawContent, "\r\n", "\n");
            if (crlf) {
                content = replaceAll(content, "\n", "\r\n");
            }

            /* Parse original */
            Loreline_Script* script1 = Loreline_parse(
                content.c_str(), filePath.c_str(), fileHandler, nullptr);
            if (!script1) {
                failCount++;
                printf(CLR_BOLD_RED "FAIL" CLR_RESET " - " CLR_GRAY "%s" CLR_RESET "\n", label.c_str());
                printf("  Error: Failed to parse original script\n");
                continue;
            }

            /* Structural check: print -> parse -> print must be stable */
            Loreline_String print1 = Loreline_printScript(script1);
            Loreline_releaseScript(script1);

            if (print1.isNull()) {
                failCount++;
                printf(CLR_BOLD_RED "FAIL" CLR_RESET " - " CLR_GRAY "%s" CLR_RESET "\n", label.c_str());
                printf("  Error: printScript returned null\n");
                continue;
            }

            Loreline_Script* script2 = Loreline_parse(
                print1.c_str(), filePath.c_str(), fileHandler, nullptr);
            if (!script2) {
                failCount++;
                printf(CLR_BOLD_RED "FAIL" CLR_RESET " - " CLR_GRAY "%s" CLR_RESET "\n", label.c_str());
                printf("  Error: Failed to parse printed script\n");
                continue;
            }

            Loreline_String print2 = Loreline_printScript(script2);
            Loreline_releaseScript(script2);

            std::string p1 = print1.c_str();
            std::string p2 = print2.isNull() ? "" : print2.c_str();

            if (p1 != p2) {
                failCount++;
                printf(CLR_BOLD_RED "FAIL" CLR_RESET " - " CLR_GRAY "%s" CLR_RESET "\n", label.c_str());
                auto lines1 = splitLines(replaceAll(p1, "\r\n", "\n"));
                auto lines2 = splitLines(replaceAll(p2, "\r\n", "\n"));
                size_t ml = std::min(lines1.size(), lines2.size());
                for (size_t i = 0; i < ml; i++) {
                    if (lines1[i] != lines2[i]) {
                        printf("  > Printer output not idempotent at line %zu\n", i + 1);
                        printf("  >  print1: %s\n", lines1[i].c_str());
                        printf("  >  print2: %s\n", lines2[i].c_str());
                        break;
                    }
                }
                if (lines1.size() != lines2.size()) {
                    printf("  > Line count differs: print1=%zu, print2=%zu\n",
                           lines1.size(), lines2.size());
                }
                continue;
            }

            /* Behavioral check: run each test item on the printed content */
            bool allPassed = true;
            std::string firstError;
            std::string firstExpected;
            std::string firstActual;

            for (const auto& item : testItems) {
                auto rtResult = runTest(filePath, p1, item, crlf);
                if (!rtResult.passed) {
                    allPassed = false;
                    if (firstError.empty()) {
                        firstError = rtResult.error;
                        firstExpected = rtResult.expected;
                        firstActual = rtResult.actual;
                    }
                }
            }

            if (allPassed) {
                passCount++;
                printf(CLR_BOLD_GREEN "PASS" CLR_RESET " - " CLR_GRAY "%s" CLR_RESET "\n", label.c_str());
            } else {
                failCount++;
                printf(CLR_BOLD_RED "FAIL" CLR_RESET " - " CLR_GRAY "%s" CLR_RESET "\n", label.c_str());
                if (!firstError.empty()) {
                    printf("  Error: %s\n", firstError.c_str());
                }
                if (!firstExpected.empty() || !firstActual.empty()) {
                    showDiff(firstExpected, firstActual);
                }
            }
        }

        /* JSON roundtrip test */
        bool jsonCrlfModes[] = {false, true};
        for (int jm = 0; jm < 2; jm++) {
            bool crlf = jsonCrlfModes[jm];
            const char* modeLabel = crlf ? "CRLF" : "LF";
            std::string label = filePath + " ~ " + modeLabel + " ~ json-roundtrip";

            std::string content = replaceAll(rawContent, "\r\n", "\n");
            if (crlf) content = replaceAll(content, "\n", "\r\n");

            Loreline_Script* script = Loreline_parse(
                content.c_str(), filePath.c_str(), fileHandler, nullptr);

            if (!script) {
                failCount++;
                printf(CLR_BOLD_RED "FAIL" CLR_RESET " - " CLR_GRAY "%s" CLR_RESET "\n", label.c_str());
                printf("  Error: Failed to parse script\n");
            } else {
                Loreline_String json1Str = Loreline_scriptToJson(script, false);

                Loreline_releaseScript(script);

                if (json1Str.isNull()) {
                    failCount++;
                    printf(CLR_BOLD_RED "FAIL" CLR_RESET " - " CLR_GRAY "%s" CLR_RESET "\n", label.c_str());
                    printf("  Error: scriptToJson returned null\n");
                } else {
                    std::string json1 = json1Str.c_str();

                    Loreline_Script* script2 = Loreline_scriptFromJson(json1Str);

                    if (!script2) {
                        failCount++;
                        printf(CLR_BOLD_RED "FAIL" CLR_RESET " - " CLR_GRAY "%s" CLR_RESET "\n", label.c_str());
                        printf("  Error: scriptFromJson returned null\n");
                    } else {
                        Loreline_String json2Str = Loreline_scriptToJson(script2, false);

                        Loreline_releaseScript(script2);

                        std::string json2 = json2Str.isNull() ? "" : json2Str.c_str();

                        if (json1 == json2) {
                            passCount++;
                            printf(CLR_BOLD_GREEN "PASS" CLR_RESET " - " CLR_GRAY "%s" CLR_RESET "\n", label.c_str());
                            fflush(stdout);
                        } else {
                            failCount++;
                            printf(CLR_BOLD_RED "FAIL" CLR_RESET " - " CLR_GRAY "%s" CLR_RESET "\n", label.c_str());
                            printf("  > JSON mismatch after roundtrip\n");
                            fflush(stdout);
                        }
                    }
                }
            }
        }

        if (failCount > failBefore) fileFailCount++;
    }

    /* Programmatic C API checks (not driven by .lor test blocks) */
    fileCount++;
    runContainerFieldTest();

    int total = passCount + failCount;
    printf("\n");
    if (failCount == 0) {
        printf(CLR_BOLD_GREEN "  All %d tests passed (%d files)" CLR_RESET "\n", total, fileCount);
    } else {
        printf(CLR_BOLD_RED "  %d of %d tests failed (%d of %d files)" CLR_RESET "\n", failCount, total, fileFailCount, fileCount);
    }

    Loreline_dispose();

    return failCount > 0 ? 1 : 0;
}
