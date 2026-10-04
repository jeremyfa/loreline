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
    std::vector<int> saveAtChoice;
    std::vector<int> saveAtDialogue;
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

static std::vector<int> parseIntList(const std::string& value);

/* A saveAtChoice / saveAtDialogue value: one index, or a list of indices */
static std::vector<int> parseSaveIndices(const std::string& value) {
    std::string v = value;
    while (!v.empty() && v[0] == ' ') v.erase(0, 1);
    if (!v.empty() && v[0] == '[') return parseIntList(v);
    return std::vector<int>{ std::stoi(v) };
}

static bool containsIndex(const std::vector<int>& list, int value) {
    for (int v : list) {
        if (v == value) return true;
    }
    return false;
}

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
            current->saveAtChoice = parseSaveIndices(value);
        } else if (key == "saveAtDialogue") {
            current->saveAtDialogue = parseSaveIndices(value);
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

/* Tag offsets count the UTF-16 units of the text, the units of the strings the
 * interpreter works with on hxcpp, while the text arrives as UTF-8: the byte
 * where a tag goes, for an offset. */
static int tagByteOffset(const char* text, int len, int offset) {
    int i = 0;
    int units = 0;
    while (i < len && units < offset) {
        unsigned char c = (unsigned char)text[i];
        int bytes = c < 0x80 ? 1 : c < 0xE0 ? 2 : c < 0xF0 ? 3 : 4;
        units += bytes == 4 ? 2 : 1;
        i += bytes;
    }
    return units < offset ? len + (offset - units) : i;
}

static std::string insertTagsInText(const char* text, const Loreline_TextTag* tags, int tagCount, bool multiline) {
    if (!text) return "";

    int len = (int)strlen(text);

    std::vector<int> tagBytes(tagCount);
    std::set<int> offsetsWithTags;
    for (int i = 0; i < tagCount; i++) {
        tagBytes[i] = tagByteOffset(text, len, tags[i].offset);
        offsetsWithTags.insert(tagBytes[i]);
    }

    std::string result;

    for (int i = 0; i < len; i++) {
        if (offsetsWithTags.count(i)) {
            for (int t = 0; t < tagCount; t++) {
                if (tagBytes[t] == i) {
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
        if (tagBytes[t] >= len) {
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
    std::vector<int> saveAtChoice;
    std::vector<int> saveAtDialogue;
    int choiceCount;
    int dialogueCount;
    /* Set after a save: the event re-presented by the restore is not counted,
     * so that save indices refer to the events of an uninterrupted run */
    bool replayingDialogue;
    bool replayingChoice;
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

    if (ctx->replayingDialogue) {
        ctx->replayingDialogue = false;
        advance();
        return;
    }

    /* Save/restore test at dialogue */
    if (containsIndex(ctx->saveAtDialogue, ctx->dialogueCount)) {
        ctx->dialogueCount++;
        ctx->replayingDialogue = true;
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

    /* Save/restore test (the re-presented choice is not counted) */
    bool replayed = ctx->replayingChoice;
    if (ctx->replayingChoice) {
        ctx->replayingChoice = false;
    } else if (containsIndex(ctx->saveAtChoice, ctx->choiceCount)) {
        ctx->choiceCount++;
        ctx->replayingChoice = true;
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

    if (!replayed) {
        ctx->choiceCount++;
    }

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
    ctx.replayingDialogue = false;
    ctx.replayingChoice = false;
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

    /* 6. Beat references cross as marker objects (the save data shape),
     * recognizable and accepted back by the runtime */
    if (ok) {
        Loreline_Value ref = Loreline_getStateField(interp, Loreline_String("ref"));
        if (ref.type != Loreline_ObjectValue) {
            ok = false; error = "beat reference did not read as a marker object";
        }
        else {
            Loreline_Value markerType = ref.objectValue.get("type");
            if (markerType.type != Loreline_StringValue || strcmp(markerType.stringValue.c_str(), "$beatRef") != 0) {
                ok = false; error = "beat reference marker has wrong type field";
            }
            else {
                /* Hand the marker back: the runtime must restore a live reference */
                Loreline_setStateField(interp, Loreline_String("refBack"), ref);
                Loreline_Value back = Loreline_getStateField(interp, Loreline_String("refBack"));
                if (back.type != Loreline_ObjectValue) {
                    ok = false; error = "beat reference marker did not round-trip";
                }
            }
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


/* -- Names in any language ------------------------------------------------- */
/* Characters and state fields named with Chinese letters or emoji go through
 * the field accessors as UTF-8, like any other name. */

static bool unicodeStringIs(Loreline_Value value, const char* expected) {
    return value.type == Loreline_StringValue && strcmp(value.stringValue.c_str(), expected) == 0;
}

static void unicodeNamesTestCheck(Loreline_Interpreter* interp, bool* okOut, std::string* errorOut) {
    bool ok = true;
    std::string error;

    /* 国王 named 路易斯, 🐉 named Smaug, 金币, 💰 and 龙, written as UTF-8 bytes */
    if (!unicodeStringIs(Loreline_getCharacterField(interp, Loreline_String("\xE5\x9B\xBD\xE7\x8E\x8B"), Loreline_String("name")), "\xE8\xB7\xAF\xE6\x98\x93\xE6\x96\xAF")) {
        ok = false; error = "name of the character with a Chinese name is wrong";
    }
    else if (!unicodeStringIs(Loreline_getCharacterField(interp, Loreline_String("\xF0\x9F\x90\x89"), Loreline_String("name")), "Smaug")) {
        ok = false; error = "name of the character with an emoji name is not Smaug";
    }
    else {
        Loreline_setStateField(interp, Loreline_String("\xE9\x87\x91\xE5\xB8\x81"), Loreline_Value::from_int(10));
        Loreline_Value coins = Loreline_getStateField(interp, Loreline_String("\xE9\x87\x91\xE5\xB8\x81"));
        if (coins.type != Loreline_Int || coins.intValue != 10) {
            ok = false; error = "state field with a Chinese name did not round-trip";
        }
    }
    if (ok) {
        Loreline_setCharacterField(interp, Loreline_String("\xF0\x9F\x90\x89"), Loreline_String("\xF0\x9F\x92\xB0"), Loreline_Value::from_int(3));
        Loreline_Value gold = Loreline_getCharacterField(interp, Loreline_String("\xF0\x9F\x90\x89"), Loreline_String("\xF0\x9F\x92\xB0"));
        if (gold.type != Loreline_Int || gold.intValue != 3) {
            ok = false; error = "emoji character field did not round-trip";
        }
    }
    if (ok) {
        Loreline_Value unknown = Loreline_getCharacterField(interp, Loreline_String("\xE9\xBE\x99"), Loreline_String("name"));
        if (unknown.type != Loreline_Null) {
            ok = false; error = "an unknown character gives a value";
        }
    }

    *okOut = ok;
    *errorOut = error;
}

static void unicodeNamesTestDialogue(
    Loreline_Interpreter* interp,
    Loreline_String character,
    Loreline_String text,
    const Loreline_TextTag* tags,
    int tagCount,
    Loreline_Advance advance,
    void* userData
) {
    ContainerTestContext* ctx = (ContainerTestContext*)userData;
    unicodeNamesTestCheck(interp, &ctx->ok, &ctx->error);
    advance();
}

static void runUnicodeNamesTest() {
    /* character 国王 named 路易斯, character 🐉 named Smaug, state field 金币 */
    const char* source =
        "\n"
        "character \xE5\x9B\xBD\xE7\x8E\x8B\n"
        "  name: \xE8\xB7\xAF\xE6\x98\x93\xE6\x96\xAF\n"
        "\n"
        "character \xF0\x9F\x90\x89\n"
        "  name: Smaug\n"
        "\n"
        "state\n"
        "  \xE9\x87\x91\xE5\xB8\x81: 1\n"
        "\n"
        "beat Main\n"
        "  \xE5\x9B\xBD\xE7\x8E\x8B: Checking fields.\n";

    ContainerTestContext ctx;

    Loreline_Script* script = Loreline_parse(source, "unicode-names.lor", nullptr, nullptr);
    if (script) {
        Loreline_Interpreter* interp = Loreline_play(
            script, unicodeNamesTestDialogue, containerTestChoice, containerTestFinish,
            Loreline_String(), nullptr, &ctx);
        if (interp) {
            Loreline_releaseInterpreter(interp);
        }
        Loreline_releaseScript(script);
    } else {
        ctx.ok = false;
        ctx.error = "Error parsing the names script";
    }

    if (ctx.ok) {
        passCount++;
        printf(CLR_BOLD_GREEN "PASS" CLR_RESET " - " CLR_GRAY "capi ~ names in any language" CLR_RESET "\n");
    } else {
        failCount++;
        fileFailCount++;
        printf(CLR_BOLD_RED "FAIL" CLR_RESET " - " CLR_GRAY "capi ~ names in any language" CLR_RESET "\n");
        printf("  > %s\n", ctx.error.c_str());
    }
    fflush(stdout);
}

/* -- Parallel interpreters test -------------------------------------------- */

/* Mirrors the Godot lifetime suite's parallel test at the C API level: several
 * interpreters run side by side, driven round-robin through PARKED
 * continuations (the host answers long after the handler returned, which is
 * exactly what Loreline_Advance / Loreline_Select carrying their interpreter
 * make safe). Each run must receive only its own callbacks and keep its own
 * state. */

struct ParallelRunCtx {
    std::vector<std::string> texts;
    Loreline_Advance advance { nullptr };
    Loreline_Select select { nullptr };
    bool hasAdvance = false;
    bool hasSelect = false;
    bool finished = false;
};

static void parallelTestDialogue(
    Loreline_Interpreter* /* interp */,
    Loreline_String /* character */,
    Loreline_String text,
    const Loreline_TextTag* /* tags */,
    int /* tagCount */,
    Loreline_Advance advance,
    void* userData
) {
    ParallelRunCtx* ctx = (ParallelRunCtx*)userData;
    ctx->texts.push_back(text.c_str() ? text.c_str() : "");
    /* Park the continuation: the driver answers on its own schedule. */
    ctx->advance = advance;
    ctx->hasAdvance = true;
}

static void parallelTestChoice(
    Loreline_Interpreter* /* interp */,
    const Loreline_ChoiceOption* /* options */,
    int /* optionCount */,
    Loreline_Select select,
    void* userData
) {
    ParallelRunCtx* ctx = (ParallelRunCtx*)userData;
    ctx->select = select;
    ctx->hasSelect = true;
}

static void parallelTestFinish(Loreline_Interpreter* /* interp */, void* userData) {
    ((ParallelRunCtx*)userData)->finished = true;
}

static std::string parallelPicked(Loreline_Interpreter* interp) {
    Loreline_Value v = Loreline_getStateField(interp, Loreline_String("picked"));
    if (v.type == Loreline_StringValue && !v.stringValue.isNull()) {
        return v.stringValue.c_str();
    }
    return "<not a string>";
}

static void runParallelInterpretersTest() {
    const char* source =
        "state\n"
        "  picked: \"none\"\n"
        "\n"
        "beat Start\n"
        "  Narrator: begin\n"
        "\n"
        "  choice\n"
        "    take alpha\n"
        "      picked = \"alpha\"\n"
        "\n"
        "      -> Show\n"
        "    take beta\n"
        "      picked = \"beta\"\n"
        "\n"
        "      -> Show\n"
        "\n"
        "beat Show\n"
        "  Narrator: chose $picked\n";

    bool ok = true;
    std::string error;
    auto fail = [&](const std::string& msg) {
        if (ok) { ok = false; error = msg; }
    };

    Loreline_Script* script = Loreline_parse(source, "parallel.lor", nullptr, nullptr);
    if (!script) {
        fail("Error parsing parallel test script");
    } else {
        const int RUNS = 3;
        ParallelRunCtx ctx[RUNS];
        Loreline_Interpreter* interps[RUNS] = { nullptr, nullptr, nullptr };
        for (int i = 0; i < RUNS; i++) {
            interps[i] = Loreline_play(
                script, parallelTestDialogue, parallelTestChoice, parallelTestFinish,
                Loreline_String(), nullptr, &ctx[i]);
            if (!interps[i]) fail("play() returned null");
        }

        /* Drive every run to its first choice (answering only dialogues). */
        for (int round = 0; round < 50 && ok; round++) {
            bool allAtChoice = true;
            for (int i = 0; i < RUNS; i++) {
                if (ctx[i].hasAdvance) {
                    ctx[i].hasAdvance = false;
                    ctx[i].advance();
                }
                if (!ctx[i].hasSelect) allAtChoice = false;
            }
            Loreline_update(0.016);
            if (allAtChoice) break;
        }
        for (int i = 0; i < RUNS && ok; i++) {
            if (!ctx[i].hasSelect) fail("a run never reached its choice");
        }

        /* Answer run 0 only, and check run 1 saw nothing of it: neither its
         * state nor its callbacks may move. */
        if (ok) {
            size_t run1TextsBefore = ctx[1].texts.size();
            ctx[0].hasSelect = false;
            ctx[0].select(0); /* alpha */
            for (int round = 0; round < 50 && !ctx[0].finished; round++) {
                if (ctx[0].hasAdvance) { ctx[0].hasAdvance = false; ctx[0].advance(); }
                Loreline_update(0.016);
            }
            if (!ctx[0].finished) fail("run 0 did not finish");
            if (parallelPicked(interps[1]) != "none") fail("run 1 state moved while only run 0 was driven");
            if (ctx[1].texts.size() != run1TextsBefore) fail("run 1 received callbacks meant for run 0");
        }

        /* Now finish runs 1 (beta) and 2 (alpha), interleaved. */
        if (ok) {
            ctx[1].hasSelect = false;
            ctx[1].select(1); /* beta */
            ctx[2].hasSelect = false;
            ctx[2].select(0); /* alpha */
            for (int round = 0; round < 50 && !(ctx[1].finished && ctx[2].finished); round++) {
                for (int i = 1; i < RUNS; i++) {
                    if (ctx[i].hasAdvance) { ctx[i].hasAdvance = false; ctx[i].advance(); }
                }
                Loreline_update(0.016);
            }
            if (!ctx[1].finished || !ctx[2].finished) fail("runs 1 and 2 did not both finish");
        }

        /* Per-run transcript and state stayed isolated. */
        if (ok) {
            const char* expected[RUNS] = { "chose alpha", "chose beta", "chose alpha" };
            const char* picked[RUNS] = { "alpha", "beta", "alpha" };
            for (int i = 0; i < RUNS; i++) {
                if (ctx[i].texts.size() != 2 || ctx[i].texts[0] != "begin" || ctx[i].texts[1] != expected[i]) {
                    fail("run transcript is wrong or polluted by another run");
                }
                if (parallelPicked(interps[i]) != picked[i]) {
                    fail("run state does not match the option it picked");
                }
            }
        }

        for (int i = 0; i < RUNS; i++) {
            if (interps[i]) Loreline_releaseInterpreter(interps[i]);
        }
        Loreline_releaseScript(script);
    }

    if (ok) {
        passCount++;
        printf(CLR_BOLD_GREEN "PASS" CLR_RESET " - " CLR_GRAY "capi ~ parallel interpreters stay independent" CLR_RESET "\n");
    } else {
        failCount++;
        fileFailCount++;
        printf(CLR_BOLD_RED "FAIL" CLR_RESET " - " CLR_GRAY "capi ~ parallel interpreters stay independent" CLR_RESET "\n");
        printf("  > %s\n", error.c_str());
    }
    fflush(stdout);
}

/* -- Child interpreters test ---------------------------------------------- */

/* Same scenario in every binding runner. A child spawned from the root shares its
 * state, gets host functions bound to itself (the custom function receives the
 * child handle), and both playheads are saved from any interpreter then continued
 * after a restore with Loreline_resumeSpawn(). Each interpreter gets its own
 * userData, used here to name it in the log. */

struct SpawnTestLog {
    std::vector<std::string> lines;
    std::vector<std::pair<std::string, Loreline_Advance>> pending;
};

struct SpawnTestFlow {
    SpawnTestLog* log;
    std::string name;
};

static void spawnTestDialogue(
    Loreline_Interpreter* /* interp */,
    Loreline_String character,
    Loreline_String text,
    const Loreline_TextTag* /* tags */,
    int /* tagCount */,
    Loreline_Advance advance,
    void* userData
) {
    SpawnTestFlow* flow = (SpawnTestFlow*)userData;
    std::string line = flow->name + ": ";
    if (!character.isNull()) line += std::string(character.c_str()) + ": ";
    line += text.c_str() ? text.c_str() : "";
    flow->log->lines.push_back(line);
    flow->log->pending.push_back(std::make_pair(flow->name, advance));
}

static void spawnTestChoice(Loreline_Interpreter*, const Loreline_ChoiceOption*, int, Loreline_Select, void*) {}

static void spawnTestFinish(Loreline_Interpreter*, void*) {}

static Loreline_Value spawnTestWho(Loreline_Interpreter* interp, const Loreline_Value*, int, void*) {
    Loreline_String key = Loreline_interpreterKey(interp);
    return Loreline_Value::from_string(key.isNull() ? Loreline_String("root") : key);
}

static void spawnTestPump() {
    for (int i = 0; i < 5; i++) Loreline_update(0.016);
}

static bool spawnTestNext(SpawnTestLog& log, const std::string& name) {
    for (size_t i = 0; i < log.pending.size(); i++) {
        if (log.pending[i].first == name) {
            Loreline_Advance advance = log.pending[i].second;
            log.pending.erase(log.pending.begin() + i);
            advance();
            spawnTestPump();
            return true;
        }
    }
    return false;
}

static void runSpawnTest() {
    const char* source =
        "state\n"
        "  gold: 0\n"
        "\n"
        "beat Main\n"
        "  gold = gold + 1\n"
        "\n"
        "  Main gold $gold\n"
        "\n"
        "  Main where $current_beat() host $who()\n"
        "\n"
        "beat Side\n"
        "  new state\n"
        "    local: 5\n"
        "\n"
        "  gold = gold + 10\n"
        "\n"
        "  Side gold $gold local $local\n"
        "\n"
        "  Side where $current_beat() host $who()\n";

    const char* expected[] = {
        "root: Main gold 1",
        "npc: Side gold 11 local 5",
        "root: Main where Main host root",
        "root: Main where Main host root",
        "npc: Side gold 11 local 5",
        "npc: Side where Side host npc"
    };
    const size_t expectedCount = sizeof(expected) / sizeof(expected[0]);

    bool ok = true;
    std::string error;
    auto fail = [&](const std::string& msg) {
        if (ok) { ok = false; error = msg; }
    };

    SpawnTestLog log;
    SpawnTestFlow rootFlow { &log, "root" };
    SpawnTestFlow npcFlow { &log, "npc" };

    Loreline_Script* script = Loreline_parse(source, "spawn.lor", nullptr, nullptr);
    if (!script) {
        fail("Error parsing spawn test script");
    } else {
        Loreline_InterpreterOptions* options = Loreline_createOptions();
        Loreline_optionsAddFunction(options, Loreline_String("who"), spawnTestWho, nullptr);

        Loreline_Interpreter* root = Loreline_play(
            script, spawnTestDialogue, spawnTestChoice, spawnTestFinish,
            Loreline_String("Main"), options, &rootFlow);
        spawnTestPump();
        Loreline_Interpreter* npc = root ? Loreline_spawn(root, Loreline_String("npc"),
            spawnTestDialogue, spawnTestChoice, spawnTestFinish, &npcFlow) : nullptr;
        if (!npc) fail("spawn returned null");

        Loreline_Interpreter* restored = nullptr;
        Loreline_Interpreter* restoredNpc = nullptr;
        if (ok) {
            Loreline_start(npc, Loreline_String("Side"));
            spawnTestPump();
            if (!spawnTestNext(log, "root")) fail("no pending dialogue for root");
        }
        if (ok) {
            Loreline_String key = Loreline_interpreterKey(npc);
            if (key.isNull() || std::string(key.c_str()) != "npc") fail("child key is not npc");
            if (!Loreline_interpreterKey(root).isNull()) fail("root key is not null");
            if (Loreline_isRoot(npc) || !Loreline_isRoot(root)) fail("isRoot");
        }
        std::string saveData;
        if (ok) {
            saveData = Loreline_save(npc).c_str();
            if (saveData != std::string(Loreline_save(root).c_str())) fail("save from child differs from save from root");
        }
        if (ok) {
            log.pending.clear();
            restored = Loreline_resume(script, spawnTestDialogue, spawnTestChoice, spawnTestFinish,
                Loreline_String(saveData.c_str()), Loreline_String(), options, &rootFlow);
            spawnTestPump();
            if (!restored) fail("resume returned null");
        }
        if (ok) {
            if (Loreline_resumableSpawnKeyCount(restored) != 1
                || std::string(Loreline_resumableSpawnKey(restored, 0).c_str()) != "npc") {
                fail("restored child keys are not [npc]");
            }
        }
        if (ok) {
            restoredNpc = Loreline_resumeSpawn(restored, Loreline_String("npc"),
                spawnTestDialogue, spawnTestChoice, spawnTestFinish, &npcFlow);
            spawnTestPump();
            if (!restoredNpc) fail("resumeSpawn returned null");
            else if (!spawnTestNext(log, "npc")) fail("no pending dialogue for npc after resumeSpawn");
        }
        if (ok) {
            bool same = log.lines.size() == expectedCount;
            for (size_t i = 0; same && i < expectedCount; i++) {
                if (log.lines[i] != expected[i]) same = false;
            }
            if (!same) {
                std::string got;
                for (const auto& line : log.lines) got += "\n    " + line;
                fail("unexpected log:" + got);
            }
        }

        if (restoredNpc) Loreline_releaseInterpreter(restoredNpc);
        if (restored) Loreline_releaseInterpreter(restored);
        if (npc) Loreline_releaseInterpreter(npc);
        if (root) Loreline_releaseInterpreter(root);
        Loreline_releaseOptions(options);
        Loreline_releaseScript(script);
    }

    if (ok) {
        passCount++;
        printf(CLR_BOLD_GREEN "PASS" CLR_RESET " - " CLR_GRAY "spawn: shared state, bound functions, save and resumeSpawn" CLR_RESET "\n");
    } else {
        failCount++;
        fileFailCount++;
        printf(CLR_BOLD_RED "FAIL" CLR_RESET " - " CLR_GRAY "spawn: shared state, bound functions, save and resumeSpawn" CLR_RESET "\n");
        printf("  > %s\n", error.c_str());
    }
    fflush(stdout);
}

/* -- Random generator ------------------------------------------------------ */

/* The random generator is saved, and Loreline_seedRandom() reseeds it from the host:
 * same scenario in every binding runner. After a restore at the first line, reseeding
 * with the seed of the script makes the second line draw what the first one drew. */
static void runPrepareCachesTest() {
    const char* source =
        "state\n"
        "  concept: \"greet\"\n"
        "\n"
        "beat Main\n"
        "  Bark()\n"
        "  concept = \"leave\"\n"
        "  Bark()\n"
        "\n"
        "beat Bark\n"
        "  when\n"
        "    concept is \"greet\"\n"
        "      Hello.\n"
        "    concept is \"leave\"\n"
        "      Bye.\n"
        "    true\n"
        "      Nothing.\n";
    const char* label = "caches: prepareCaches leaves the picks unchanged";

    bool ok = true;
    std::string error;
    auto fail = [&](const std::string& msg) {
        if (ok) { ok = false; error = msg; }
    };
    auto check = [&](const SpawnTestLog& log, const std::string& what) {
        if (log.lines.size() != 2 || log.lines[0] != "root: Hello." || log.lines[1] != "root: Bye.") {
            std::string got;
            for (const auto& line : log.lines) got += "\n    " + line;
            fail(what + ": expected Hello. then Bye., got:" + got);
        }
    };

    Loreline_Script* script = Loreline_parse(source, "caches.lor", nullptr, nullptr);
    if (!script) {
        fail("Error parsing caches test script");
    } else {
        // Prepared by the option, before the script starts
        SpawnTestLog optionLog;
        SpawnTestFlow optionFlow { &optionLog, "root" };
        Loreline_InterpreterOptions* options = Loreline_createOptions();
        Loreline_optionsSetPrepareCaches(options, true);
        Loreline_Interpreter* prepared = Loreline_play(
            script, spawnTestDialogue, spawnTestChoice, spawnTestFinish,
            Loreline_String("Main"), options, &optionFlow);
        spawnTestPump();
        spawnTestNext(optionLog, "root");
        spawnTestNext(optionLog, "root");
        check(optionLog, "option");

        // Prepared by the method, between two picks
        SpawnTestLog methodLog;
        SpawnTestFlow methodFlow { &methodLog, "root" };
        Loreline_Interpreter* lazy = Loreline_play(
            script, spawnTestDialogue, spawnTestChoice, spawnTestFinish,
            Loreline_String("Main"), nullptr, &methodFlow);
        spawnTestPump();
        Loreline_prepareCaches(lazy);
        Loreline_prepareCaches(lazy);
        spawnTestNext(methodLog, "root");
        spawnTestNext(methodLog, "root");
        check(methodLog, "method");

        if (prepared) Loreline_releaseInterpreter(prepared);
        if (lazy) Loreline_releaseInterpreter(lazy);
        Loreline_releaseOptions(options);
        Loreline_releaseScript(script);
    }

    if (ok) {
        passCount++;
        printf(CLR_BOLD_GREEN "PASS" CLR_RESET " - " CLR_GRAY "%s" CLR_RESET "\n", label);
    } else {
        failCount++;
        fileFailCount++;
        printf(CLR_BOLD_RED "FAIL" CLR_RESET " - " CLR_GRAY "%s" CLR_RESET "\n", label);
        printf("  > %s\n", error.c_str());
    }
    fflush(stdout);
}

static void runSeedRandomTest() {
    const char* source =
        "beat Main\n"
        "  seed_random(7)\n"
        "  First $random(1, 1000000000)\n"
        "\n"
        "  Second $random(1, 1000000000)\n";
    const char* label = "random: seedRandom after restore";

    bool ok = true;
    std::string error;
    auto fail = [&](const std::string& msg) {
        if (ok) { ok = false; error = msg; }
    };
    auto valueOf = [](const std::string& line) {
        size_t space = line.rfind(' ');
        return space == std::string::npos ? std::string() : line.substr(space + 1);
    };

    SpawnTestLog log;
    SpawnTestFlow rootFlow { &log, "root" };

    Loreline_Script* script = Loreline_parse(source, "random.lor", nullptr, nullptr);
    if (!script) {
        fail("Error parsing random test script");
    } else {
        Loreline_Interpreter* root = Loreline_play(
            script, spawnTestDialogue, spawnTestChoice, spawnTestFinish,
            Loreline_String("Main"), nullptr, &rootFlow);
        spawnTestPump();
        if (!root || log.lines.size() != 1) fail("first line not shown");

        Loreline_Interpreter* restored = nullptr;
        if (ok) {
            std::string saveData = Loreline_save(root).c_str();
            log.pending.clear();
            restored = Loreline_resume(script, spawnTestDialogue, spawnTestChoice, spawnTestFinish,
                Loreline_String(saveData.c_str()), Loreline_String(), nullptr, &rootFlow);
            spawnTestPump();
            if (!restored) fail("resume returned null");
        }
        if (ok) {
            Loreline_seedRandom(restored, true, 7);
            if (!spawnTestNext(log, "root")) fail("no pending dialogue after resume");
        }
        if (ok) {
            std::string first = valueOf(log.lines[0]);
            std::string second = log.lines.size() > 2 ? valueOf(log.lines[2]) : std::string();
            if (second != first) {
                std::string got;
                for (const auto& line : log.lines) got += "\n    " + line;
                fail("expected " + first + " after reseeding, got:" + got);
            }
        }

        if (restored) Loreline_releaseInterpreter(restored);
        if (root) Loreline_releaseInterpreter(root);
        Loreline_releaseScript(script);
    }

    if (ok) {
        passCount++;
        printf(CLR_BOLD_GREEN "PASS" CLR_RESET " - " CLR_GRAY "%s" CLR_RESET "\n", label);
    } else {
        failCount++;
        fileFailCount++;
        printf(CLR_BOLD_RED "FAIL" CLR_RESET " - " CLR_GRAY "%s" CLR_RESET "\n", label);
        printf("  > %s\n", error.c_str());
    }
    fflush(stdout);
}

/* -- When strategy -------------------------------------------------------- */

/* The strategy of a when block can be a host function: it receives one record per
 * rule and returns the index of the rule to play. Same scenario in every binding runner. */
static std::string whenStrategySummary;

static Loreline_Value whenStrategyChooser(Loreline_Interpreter*, const Loreline_Value* args, int argCount, void*) {
    int last = -1;
    std::string parts;
    if (argCount >= 1 && args[0].type == Loreline_ArrayValue) {
        const Loreline_Array& records = args[0].arrayValue;
        for (int i = 0; i < records.length(); i++) {
            Loreline_Value record = records.get(i);
            if (record.type != Loreline_ObjectValue) continue;
            Loreline_Value indexValue = record.objectValue.get("index");
            Loreline_Value eligibleValue = record.objectValue.get("eligible");
            int index = indexValue.type == Loreline_Float ? (int)indexValue.floatValue : indexValue.intValue;
            bool eligible = eligibleValue.type == Loreline_Bool && eligibleValue.boolValue;
            if (!parts.empty()) parts += " ";
            parts += std::to_string(index) + ":" + (eligible ? "true" : "false");
            if (eligible) last = index;
        }
    }
    whenStrategySummary = parts;
    return Loreline_Value::from_int(last);
}

static void runWhenStrategyTest() {
    const char* source =
        "state\n"
        "  ready: true\n"
        "\n"
        "beat Start\n"
        "  when chooser\n"
        "    ready\n"
        "      Zero.\n"
        "    not ready\n"
        "      One.\n"
        "    true\n"
        "      Two.\n"
        "  End.\n";
    const char* label = "when: host strategy";

    bool ok = true;
    std::string error;
    whenStrategySummary.clear();

    SpawnTestLog log;
    SpawnTestFlow rootFlow { &log, "root" };

    Loreline_Script* script = Loreline_parse(source, "when-strategy.lor", nullptr, nullptr);
    if (!script) {
        ok = false;
        error = "Error parsing when strategy test script";
    } else {
        Loreline_InterpreterOptions* options = Loreline_createOptions();
        Loreline_optionsAddFunction(options, Loreline_String("chooser"), whenStrategyChooser, nullptr);
        Loreline_Interpreter* root = Loreline_play(
            script, spawnTestDialogue, spawnTestChoice, spawnTestFinish,
            Loreline_String("Start"), options, &rootFlow);
        spawnTestPump();
        while (spawnTestNext(log, "root")) {}

        std::string joined;
        for (const auto& line : log.lines) {
            if (!joined.empty()) joined += ",";
            joined += line;
        }
        if (whenStrategySummary != "0:true 1:false 2:true" || joined != "root: Two.,root: End.") {
            ok = false;
            error = "records " + whenStrategySummary + ", log " + joined;
        }

        if (root) Loreline_releaseInterpreter(root);
        Loreline_releaseOptions(options);
        Loreline_releaseScript(script);
    }

    if (ok) {
        passCount++;
        printf(CLR_BOLD_GREEN "PASS" CLR_RESET " - " CLR_GRAY "%s" CLR_RESET "\n", label);
    } else {
        failCount++;
        fileFailCount++;
        printf(CLR_BOLD_RED "FAIL" CLR_RESET " - " CLR_GRAY "%s" CLR_RESET "\n", label);
        printf("  > %s\n", error.c_str());
    }
    fflush(stdout);
}

/* -- Sync calls after Loreline_update() ------------------------------------ */

/* Once Loreline_update() has been called, callbacks are deferred to the dispatch
 * queue. The sync wrappers must still complete: their own completion does not go
 * through that queue. */

static void syncAfterUpdateFileHandler(Loreline_String path, Loreline_FileRequest* request, void* userData) {
    /* No translation file: answered right away */
    Loreline_provideFile(request, Loreline_String());
}

static void runSyncAfterUpdateTest() {
    bool ok = true;
    std::string error;

    Loreline_update(0.016);

    Loreline_Script* script = Loreline_parse(
        "beat Main\n  Hello\n", "sync-after-update.lor", nullptr, nullptr);
    if (!script) {
        ok = false;
        error = "Loreline_parse returned null after Loreline_update";
    } else {
        /* Returns (null or empty translations are fine): what matters is that it returns */
        Loreline_Translations* translations = Loreline_loadLocale(
            Loreline_String("fr"), script, Loreline_String("sync-after-update.lor"),
            syncAfterUpdateFileHandler, nullptr);
        if (translations) Loreline_releaseTranslations(translations);
        Loreline_releaseScript(script);
    }

    if (ok) {
        passCount++;
        printf(CLR_BOLD_GREEN "PASS" CLR_RESET " - " CLR_GRAY "capi ~ sync parse/loadLocale after update" CLR_RESET "\n");
    } else {
        failCount++;
        fileFailCount++;
        printf(CLR_BOLD_RED "FAIL" CLR_RESET " - " CLR_GRAY "capi ~ sync parse/loadLocale after update" CLR_RESET "\n");
        printf("  > %s\n", error.c_str());
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
    runUnicodeNamesTest();
    fileCount++;
    runParallelInterpretersTest();
    fileCount++;
    runSpawnTest();
    runSeedRandomTest();
    runPrepareCachesTest();
    runWhenStrategyTest();
    fileCount++;
    runSyncAfterUpdateTest();

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
