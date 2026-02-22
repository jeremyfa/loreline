/*
 * Loreline C++ Sample — CoffeeShop
 *
 * Interactive console app that runs the CoffeeShop story.
 * Build with CMake (see CMakeLists.txt) or directly:
 *
 *   clang++ -std=c++11 -o loreline-sample main.cpp \
 *     -I/path/to/include -L/path/to/lib -lLoreline \
 *     -Wl,-rpath,@executable_path
 */

#include "Loreline.h"

#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <sstream>
#include <string>

/* ── Helpers ───────────────────────────────────────────────────────────── */

static std::string readFile(const std::string& path) {
    std::ifstream f(path, std::ios::binary);
    if (!f.is_open()) return std::string();
    std::ostringstream ss;
    ss << f.rdbuf();
    return ss.str();
}

/* ── File handler (for imports like "characters.lor") ──────────────────── */

static void onFileRequest(
    const char* path,
    void (*provide)(const char* content),
    void* /* userData */
) {
    // Loreline resolves import paths relative to the source file's filePath,
    // so the path is already correct (e.g., "story/characters.lor").
    std::string content = readFile(path);
    if (content.empty()) {
        provide(NULL);
    } else {
        provide(content.c_str());
    }
}

/* ── Dialogue handler ──────────────────────────────────────────────────── */

static void onDialogue(
    Loreline_Interpreter* interp,
    Loreline_String character,
    Loreline_String text,
    const Loreline_TextTag* /* tags */,
    int /* tagCount */,
    void (*advance)(void),
    void* /* userData */
) {
    const char* t = text.c_str();

    if (!character.isNull()) {
        // Dialogue — resolve display name
        Loreline_Value nameVal = Loreline_getCharacterField(interp, character.c_str(), "name");
        const char* displayName = (nameVal.type == Loreline_StringValue && nameVal.stringValue)
            ? nameVal.stringValue.c_str()
            : character.c_str();

        // Indent continuation lines for multiline text
        std::string formatted = t;
        size_t pos = 0;
        while ((pos = formatted.find('\n', pos)) != std::string::npos) {
            formatted.replace(pos, 1, "\n   ");
            pos += 4;
        }

        printf(" %s: %s\n", displayName, formatted.c_str());
    } else {
        // Narrative text
        std::string formatted = t;
        size_t pos = 0;
        while ((pos = formatted.find('\n', pos)) != std::string::npos) {
            formatted.replace(pos, 1, "\n ");
            pos += 2;
        }

        printf(" %s\n", formatted.c_str());
    }

    printf("\n");
    advance();
}

/* ── Choice handler ────────────────────────────────────────────────────── */

static void onChoice(
    Loreline_Interpreter* /* interp */,
    const Loreline_ChoiceOption* options,
    int optionCount,
    void (*select)(int index),
    void* /* userData */
) {
    // Display enabled options with 1-based numbering
    int displayIndex = 1;
    for (int i = 0; i < optionCount; i++) {
        if (options[i].enabled) {
            printf(" %d. %s\n", displayIndex, options[i].text.c_str());
            displayIndex++;
        }
    }
    printf("\n");

    // Read user choice
    for (;;) {
        printf(" > ");
        fflush(stdout);

        char buf[64];
        if (!fgets(buf, sizeof(buf), stdin)) {
            // EOF — pick first enabled option
            for (int i = 0; i < optionCount; i++) {
                if (options[i].enabled) {
                    printf("\n");
                    select(i);
                    return;
                }
            }
            return;
        }

        int choice = atoi(buf);
        if (choice >= 1) {
            // Map 1-based display index to 0-based absolute index
            int idx = 1;
            for (int i = 0; i < optionCount; i++) {
                if (options[i].enabled) {
                    if (choice == idx) {
                        printf("\n");
                        select(i);
                        return;
                    }
                    idx++;
                }
            }
        }
        // Invalid input — try again
    }
}

/* ── Finish handler ────────────────────────────────────────────────────── */

static void onFinish(
    Loreline_Interpreter* /* interp */,
    void* /* userData */
) {
    // Story complete
}

/* ── Main ──────────────────────────────────────────────────────────────── */

int main(int argc, char* argv[]) {
    // Default story file, can be overridden via argv[1]
    std::string storyFile = "story/CoffeeShop.lor";
    if (argc >= 2) {
        storyFile = argv[1];
    }

    // Read the story file
    std::string content = readFile(storyFile);
    if (content.empty()) {
        fprintf(stderr, "Error: cannot read '%s'\n", storyFile.c_str());
        return 1;
    }

    // Initialize Loreline
    Loreline_init();

    // Parse the story
    Loreline_Script* script = Loreline_parse(
        content.c_str(), storyFile.c_str(), onFileRequest, NULL
    );
    if (!script) {
        fprintf(stderr, "Error: failed to parse '%s'\n", storyFile.c_str());
        Loreline_dispose();
        return 1;
    }

    printf("\n");

    // Play — callbacks fire synchronously, no update loop needed
    Loreline_Interpreter* interp = Loreline_play(
        script, onDialogue, onChoice, onFinish, NULL, NULL, NULL
    );

    // Cleanup
    if (interp) Loreline_releaseInterpreter(interp);
    Loreline_releaseScript(script);
    Loreline_dispose();

    return 0;
}
