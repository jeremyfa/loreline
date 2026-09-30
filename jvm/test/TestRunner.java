import loreline.*;

import java.io.*;
import java.nio.file.*;
import java.util.*;
import java.util.regex.*;

/**
 * Loreline JVM test runner.
 *
 * Follows the same test protocol as the JS, C#, Python, and C++ test runners:
 *   - Collects .lor files from the given directory
 *   - Extracts <test> YAML blocks from comments
 *   - Runs each test in LF and CRLF modes
 *   - Runs roundtrip (parse -> print -> parse -> print) stability checks
 *   - Reports pass/fail counts
 *
 * Note: ast-print is intentionally only run by the CLI test runner.
 * AstPrinter is a pure Haxe debug pretty-printer with no target-specific
 * behavior, so a single CLI run is enough to catch any missing node-type
 * case. That's why the CLI test count is higher than each per-target
 * runner's count.
 */
public class TestRunner {
    static int passCount = 0;
    static int failCount = 0;
    static int fileCount = 0;
    static int fileFailCount = 0;

    // -- Helpers ----------------------------------------------------------

    static List<String> collectTestFiles(String directory) {
        List<String> files = new ArrayList<>();
        File dir = new File(directory);
        if (!dir.isDirectory()) return files;
        String[] entries = dir.list();
        if (entries == null) return files;
        Arrays.sort(entries);
        for (String entry : entries) {
            File fullPath = new File(dir, entry);
            if (fullPath.isDirectory()) {
                if (!entry.equals("imports") && !entry.equals("modified")) {
                    files.addAll(collectTestFiles(fullPath.getPath()));
                }
            } else if (entry.endsWith(".lor") && !entry.matches(".*\\.\\w{2}\\.lor$")) {
                files.add(fullPath.getPath());
            }
        }
        return files;
    }

    static String readFile(String path) {
        try {
            return new String(Files.readAllBytes(Paths.get(path)), "UTF-8");
        } catch (Exception e) {
            return null;
        }
    }

    static void handleFile(String path, java.util.function.Consumer<String> callback) {
        callback.accept(readFile(path));
    }

    static String insertTagsInText(String text, List<TextTag> tags, boolean multiline) {
        Set<Integer> offsetsWithTags = new HashSet<>();
        for (TextTag tag : tags) {
            offsetsWithTags.add(tag.offset);
        }

        char[] chars = text.toCharArray();
        int length = chars.length;
        StringBuilder result = new StringBuilder();

        for (int i = 0; i < length; i++) {
            if (offsetsWithTags.contains(i)) {
                for (TextTag tag : tags) {
                    if (tag.offset == i) {
                        result.append("<<");
                        if (tag.closing) result.append("/");
                        result.append(tag.value);
                        result.append(">>");
                    }
                }
            }
            char c = chars[i];
            if (multiline && c == '\n') {
                result.append("\n  ");
            } else {
                result.append(c);
            }
        }

        // Tags at end of text
        for (TextTag tag : tags) {
            if (tag.offset >= length) {
                result.append("<<");
                if (tag.closing) result.append("/");
                result.append(tag.value);
                result.append(">>");
            }
        }

        return result.toString().replaceAll("\\s+$", "");
    }

    static int compareOutput(String expected, String actual) {
        String[] expectedLines = expected.replace("\r\n", "\n").trim().split("\n", -1);
        String[] actualLines = actual.replace("\r\n", "\n").trim().split("\n", -1);
        int minLen = Math.min(expectedLines.length, actualLines.length);
        int maxLen = Math.max(expectedLines.length, actualLines.length);

        for (int i = 0; i < minLen; i++) {
            if (!expectedLines[i].equals(actualLines[i])) return i;
        }
        if (minLen < maxLen) return minLen;
        return -1;
    }

    // -- YAML parser -----------------------------------------------------

    @SuppressWarnings("unchecked")
    static List<Map<String, Object>> parseSimpleYaml(String text) {
        String[] lines = text.split("\n");
        List<Map<String, Object>> items = new ArrayList<>();
        Map<String, Object> current = null;
        String blockKey = null;
        int blockIndent = 0;
        List<String> blockLines = new ArrayList<>();

        for (int i = 0; i < lines.length; i++) {
            String line = lines[i];
            String stripped = line.replaceAll("\\s+$", "");

            // Inside a block scalar?
            if (blockKey != null) {
                if (stripped.isEmpty()) {
                    blockLines.add("");
                    continue;
                }
                String indent = " ".repeat(blockIndent);
                if (line.length() >= blockIndent && line.startsWith(indent)) {
                    blockLines.add(line.substring(blockIndent).replaceAll("\\s+$", ""));
                    continue;
                } else {
                    flushBlock(current, blockKey, blockLines);
                    blockKey = null;
                    blockLines = new ArrayList<>();
                }
            }

            // New list item: "- key: value"
            Matcher m = Pattern.compile("^- (\\w+):\\s*(.*)").matcher(stripped);
            if (m.matches()) {
                current = new LinkedHashMap<>();
                items.add(current);
                String key = m.group(1);
                String value = m.group(2);
                if (value.equals("|")) {
                    blockKey = key;
                    blockIndent = 4;
                    blockLines = new ArrayList<>();
                } else {
                    current.put(key, parseYamlValue(value));
                }
                continue;
            }

            // Continuation key: "  key: value"
            Matcher m2 = Pattern.compile("^  (\\w+):\\s*(.*)").matcher(stripped);
            if (m2.matches() && current != null) {
                String key = m2.group(1);
                String value = m2.group(2);
                if (value.equals("|")) {
                    blockKey = key;
                    blockIndent = 4;
                    blockLines = new ArrayList<>();
                } else {
                    current.put(key, parseYamlValue(value));
                }
                continue;
            }
        }

        if (blockKey != null) {
            flushBlock(current, blockKey, blockLines);
        }
        return items;
    }

    static void flushBlock(Map<String, Object> current, String blockKey, List<String> blockLines) {
        if (blockKey != null && current != null) {
            while (!blockLines.isEmpty() && blockLines.get(blockLines.size() - 1).isEmpty()) {
                blockLines.remove(blockLines.size() - 1);
            }
            current.put(blockKey, String.join("\n", blockLines) + "\n");
        }
    }

    // A saveAtChoice / saveAtDialogue value: absent, one index, or a list of indices
    @SuppressWarnings("unchecked")
    static List<Integer> saveIndices(Object raw) {
        List<Integer> result = new ArrayList<>();
        if (raw == null) return result;
        if (raw instanceof Number) {
            result.add(((Number) raw).intValue());
            return result;
        }
        if (raw instanceof List) {
            for (Object item : (List<Object>) raw) {
                if (!(item instanceof Number)) throw new RuntimeException("Invalid save index: " + item);
                result.add(((Number) item).intValue());
            }
            return result;
        }
        throw new RuntimeException("Invalid save indices: " + raw);
    }

    @SuppressWarnings("unchecked")
    static Object parseYamlValue(String s) {
        s = s.trim();
        if (s.isEmpty()) return null;
        // Inline flow sequence
        if (s.startsWith("[") && s.endsWith("]")) {
            String inner = s.substring(1, s.length() - 1).trim();
            if (inner.isEmpty()) return new ArrayList<>();
            List<Object> list = new ArrayList<>();
            for (String v : inner.split(",")) {
                list.add(parseYamlValue(v.trim()));
            }
            return list;
        }
        // Integer
        if (s.matches("^-?\\d+$")) return Integer.parseInt(s);
        // Boolean
        if (s.equals("true")) return Boolean.TRUE;
        if (s.equals("false")) return Boolean.FALSE;
        // Null
        if (s.equals("null") || s.equals("~")) return null;
        // String (strip optional quotes)
        if (s.length() >= 2 && s.charAt(0) == s.charAt(s.length() - 1) &&
            (s.charAt(0) == '"' || s.charAt(0) == '\'')) {
            return s.substring(1, s.length() - 1);
        }
        return s;
    }

    static List<Map<String, Object>> extractTests(String content) {
        List<Map<String, Object>> tests = new ArrayList<>();
        Matcher matcher = Pattern.compile("<test>([\\s\\S]*?)</test>").matcher(content);
        while (matcher.find()) {
            String yamlContent = matcher.group(1).trim();
            tests.addAll(parseSimpleYaml(yamlContent));
        }
        return tests;
    }

    // -- Test runner -----------------------------------------------------

    @SuppressWarnings("unchecked")
    // Canonical host-registered functions used by test/Functions-Custom.lor to verify
    // the custom-function contract: each receives (interpreter, args), where args is an
    // array and the interpreter can read/write runtime state.
    static Map<String, LorelineFunction> customTestFunctions() {
        Map<String, LorelineFunction> fns = new HashMap<>();
        fns.put("custom_echo", (interp, args) -> {
            StringBuilder sb = new StringBuilder();
            for (int i = 0; i < args.length; i++) {
                if (i > 0) sb.append(",");
                sb.append(String.valueOf(args[i]));
            }
            return sb.toString();
        });
        fns.put("custom_arg_count", (interp, args) -> args.length);
        fns.put("custom_set_state", (interp, args) -> { interp.setStateField((String) args[0], args[1]); return null; });
        fns.put("custom_get_state", (interp, args) -> interp.getStateField((String) args[0]));
        return fns;
    }

    static Object[] runTest(String filePath, String rawContent, Map<String, Object> testItem, boolean crlf) {
        String content = rawContent.replace("\r\n", "\n");
        if (crlf) content = content.replace("\n", "\r\n");

        List<Integer> choices = new ArrayList<>();
        Object choicesObj = testItem.get("choices");
        if (choicesObj instanceof List) {
            for (Object c : (List<Object>) choicesObj) {
                choices.add(((Number) c).intValue());
            }
        }

        String beatName = testItem.get("beat") != null ? testItem.get("beat").toString() : null;

        List<Integer> saveAtChoice = saveIndices(testItem.get("saveAtChoice"));
        List<Integer> saveAtDialogue = saveIndices(testItem.get("saveAtDialogue"));

        String expected = (String) testItem.get("expected");
        StringBuilder output = new StringBuilder();
        int[] choiceCount = {0};
        int[] dialogueCount = {0};
        // Set after a save: the event re-presented by the restore is not counted,
        // so that save indices refer to the events of an uninterrupted run
        boolean[] replayingDialogue = {false};
        boolean[] replayingChoice = {false};
        Script[] parsedScript = {null};
        Object[][] result = {null};

        final List<Integer> fSaveAtChoice = saveAtChoice;
        final List<Integer> fSaveAtDialogue = saveAtDialogue;
        final String fContent = content;

        // Parse the script up-front so we can resolve translations across imports
        Script earlyScript = null;
        try {
            earlyScript = Loreline.parse(content, filePath, TestRunner::handleFile);
        } catch (Exception e) {
            // parse error will be reported when we call play() below; fall through
        }

        // Build options (always register the canonical custom functions; add
        // translations across the import tree if requested)
        InterpreterOptions options = new InterpreterOptions();
        options.functions = customTestFunctions();
        Object translationVal = testItem.get("translation");
        if (translationVal != null && earlyScript != null) {
            String lang = translationVal.toString();
            Object translations = Loreline.loadLocale(lang, earlyScript, filePath, TestRunner::handleFile);
            if (translations != null) {
                options.translations = translations;
            }
        }

        // Load restoreFile content if specified
        String restoreInput = null;
        if (testItem.get("restoreFile") != null) {
            String restorePath = new File(new File(filePath).getParent(), testItem.get("restoreFile").toString()).getPath();
            restoreInput = readFile(restorePath);
            if (restoreInput != null) {
                if (crlf) restoreInput = restoreInput.replace("\r\n", "\n").replace("\n", "\r\n");
                else restoreInput = restoreInput.replace("\r\n", "\n");
            }
        }
        final String fRestoreInput = restoreInput;
        final InterpreterOptions fOptions = options;

        FinishHandler onFinish = (interp) -> {
            int cmp = compareOutput(expected, output.toString());
            result[0] = new Object[]{cmp == -1, output.toString(), expected, null};
        };

        final ChoiceHandler[] choiceHandlerRef = {null};

        DialogueHandler onDialogue = new DialogueHandler() {
            @Override
            public void handle(Interpreter interp, String character, String text, List<TextTag> tags, Runnable advance) {
                boolean multiline = text.contains("\n");
                if (tags == null) tags = Collections.emptyList();
                if (character != null) {
                    Object charName = interp.getCharacterField(character, "name");
                    String name = charName != null ? charName.toString() : character;
                    String taggedText = insertTagsInText(text, tags, multiline);
                    if (multiline) {
                        output.append(name).append(":\n  ").append(taggedText).append("\n\n");
                    } else {
                        output.append(name).append(": ").append(taggedText).append("\n\n");
                    }
                } else {
                    String taggedText = insertTagsInText(text, tags, multiline);
                    output.append("~ ").append(taggedText).append("\n\n");
                }

                if (replayingDialogue[0]) {
                    replayingDialogue[0] = false;
                    advance.run();
                    return;
                }

                if (fSaveAtDialogue.contains(dialogueCount[0])) {
                    dialogueCount[0]++;
                    replayingDialogue[0] = true;
                    String saveData = interp.save();
                    if (fRestoreInput != null) {
                        Script restoreScript = Loreline.parse(fRestoreInput, filePath, TestRunner::handleFile);
                        if (restoreScript != null) {
                            Loreline.resume(restoreScript, this, choiceHandlerRef[0], onFinish, saveData, null, fOptions);
                        } else {
                            result[0] = new Object[]{false, output.toString(), expected, "Error parsing restoreInput script"};
                        }
                    } else {
                        Loreline.resume(parsedScript[0], this, choiceHandlerRef[0], onFinish, saveData, null, fOptions);
                    }
                    return;
                }
                dialogueCount[0]++;
                advance.run();
            }
        };
        ChoiceHandler onChoice = new ChoiceHandler() {
            @Override
            public void handle(Interpreter interp, List<ChoiceOption> choiceOptions, java.util.function.IntConsumer select) {
                for (ChoiceOption opt : choiceOptions) {
                    String prefix = opt.enabled ? "+" : "-";
                    boolean multiline = opt.text.contains("\n");
                    List<TextTag> optTags = opt.tags != null ? opt.tags : Collections.emptyList();
                    String taggedText = insertTagsInText(opt.text, optTags, multiline);
                    output.append(prefix).append(" ").append(taggedText).append("\n");
                }
                output.append("\n");

                // The re-presented choice is not counted
                boolean replayed = replayingChoice[0];
                if (replayingChoice[0]) {
                    replayingChoice[0] = false;
                } else if (fSaveAtChoice.contains(choiceCount[0])) {
                    choiceCount[0]++;
                    replayingChoice[0] = true;
                    String saveData = interp.save();
                    if (fRestoreInput != null) {
                        Script restoreScript = Loreline.parse(fRestoreInput, filePath, TestRunner::handleFile);
                        if (restoreScript != null) {
                            Loreline.resume(restoreScript, onDialogue, this, onFinish, saveData, null, fOptions);
                        } else {
                            result[0] = new Object[]{false, output.toString(), expected, "Error parsing restoreInput script"};
                        }
                    } else {
                        Loreline.resume(parsedScript[0], onDialogue, this, onFinish, saveData, null, fOptions);
                    }
                    return;
                }
                if (!replayed) {
                    choiceCount[0]++;
                }

                if (choices.isEmpty()) {
                    onFinish.handle(interp);
                } else {
                    int index = choices.remove(0);
                    select.accept(index);
                }
            }
        };
        choiceHandlerRef[0] = onChoice;

        try {
            Script script = earlyScript;
            if (script != null) {
                parsedScript[0] = script;
                Loreline.play(script, onDialogue, onChoice, onFinish, beatName, fOptions);
            } else {
                result[0] = new Object[]{false, output.toString(), expected, "Error parsing script"};
            }
        } catch (Exception e) {
            result[0] = new Object[]{false, output.toString(), expected, e.toString()};
        }

        if (result[0] == null) {
            result[0] = new Object[]{false, output.toString(), expected, "Test did not produce a result"};
        }

        return result[0];
    }

    // -- Main ------------------------------------------------------------

    // Child interpreters: same scenario in every binding runner. A child spawned from the
    // root shares its state, gets host functions bound to itself, and both playheads are
    // saved from any interpreter then continued after a restore with resumeSpawn().
    static final String SPAWN_SCRIPT = String.join("\n",
        "state",
        "  gold: 0",
        "",
        "beat Main",
        "  gold = gold + 1",
        "",
        "  Main gold $gold",
        "",
        "  Main where $current_beat() host $who()",
        "",
        "beat Side",
        "  new state",
        "    local: 5",
        "",
        "  gold = gold + 10",
        "",
        "  Side gold $gold local $local",
        "",
        "  Side where $current_beat() host $who()",
        ""
    );

    static final List<String> SPAWN_EXPECTED = Arrays.asList(
        "root: Main gold 1",
        "npc: Side gold 11 local 5",
        "root: Main where Main host root",
        "root: Main where Main host root",
        "npc: Side gold 11 local 5",
        "npc: Side where Side host npc"
    );

    static String spawnNameOf(Interpreter interp) {
        return interp.getKey() != null ? interp.getKey() : "root";
    }

    static void runSpawnTest() {
        final String label = "spawn: shared state, bound functions, save and resumeSpawn";
        try {
            final List<String> log = new ArrayList<>();
            final Map<String, Runnable> pending = new HashMap<>();
            DialogueHandler dialogue = (interp, character, text, tags, advance) -> {
                log.add(spawnNameOf(interp) + ": " + (character != null ? character + ": " : "") + text);
                pending.put(spawnNameOf(interp), advance);
            };
            ChoiceHandler choice = (interp, options, select) -> {};
            FinishHandler finish = interp -> {};

            InterpreterOptions options = new InterpreterOptions();
            options.functions = new HashMap<>();
            options.functions.put("who", (interp, args) -> spawnNameOf(interp));

            Script script = Loreline.parse(SPAWN_SCRIPT);
            Interpreter root = Loreline.play(script, dialogue, choice, finish, null, options);
            Interpreter npc = root.spawn("npc", dialogue, choice, finish);
            npc.start("Side");
            spawnNext(pending, "root");

            List<String> checks = new ArrayList<>();
            if (!"npc".equals(npc.getKey())) checks.add("child key: " + npc.getKey());
            if (root.getKey() != null) checks.add("root key: " + root.getKey());
            if (npc.isRoot() || !root.isRoot()) checks.add("isRoot");
            String saveData = npc.save();
            if (!saveData.equals(root.save())) checks.add("save from child differs from save from root");

            pending.clear();
            Interpreter restored = Loreline.resume(script, dialogue, choice, finish, saveData, null, options);
            List<String> keys = restored.resumableSpawnKeys();
            if (!keys.equals(Arrays.asList("npc"))) checks.add("resumableSpawnKeys: " + keys);
            restored.resumeSpawn("npc", dialogue, choice, finish).resume();
            spawnNext(pending, "npc");

            if (!log.equals(SPAWN_EXPECTED)) {
                checks.add("log:\n    " + String.join("\n    ", log));
            }
            if (!checks.isEmpty()) throw new RuntimeException(String.join("; ", checks));

            passCount++;
            System.out.println("\033[1m\033[32mPASS\033[0m - \033[90m" + label + "\033[0m");
        } catch (Throwable e) {
            failCount++;
            System.out.println("\033[1m\033[31mFAIL\033[0m - \033[90m" + label + "\033[0m");
            System.out.println("  Error: " + e);
        }
    }

    // Fields object handed out by the custom factory of runCustomFieldsTest
    static class TestFieldsMap extends LinkedHashMap<String, Object> {}

    // The customCreateFields option: every fields object comes from the host factory,
    // which receives the interpreter asking for it.
    // The random generator is saved, and seedRandom() reseeds it from the host: same
    // scenario in every binding runner. After a restore at the first line, reseeding with
    // the seed of the script makes the second line draw what the first one drew.
    static void runSeedRandomTest() {
        final String label = "random: seedRandom after restore";
        try {
            final List<String> log = new ArrayList<>();
            final Runnable[] pending = new Runnable[1];
            DialogueHandler dialogue = (interp, character, text, tags, advance) -> {
                log.add(text);
                pending[0] = advance;
            };

            Script script = Loreline.parse(String.join("\n",
                "beat Main",
                "  seed_random(7)",
                "  First $random(1, 1000000000)",
                "",
                "  Second $random(1, 1000000000)",
                ""
            ));
            Interpreter root = Loreline.play(script, dialogue, (interp, opts, select) -> {}, interp -> {});
            String saveData = root.save();

            Interpreter restored = Loreline.resume(script, dialogue, (interp, opts, select) -> {}, interp -> {}, saveData);
            restored.seedRandom(7);
            pending[0].run();

            String first = log.get(0).split(" ")[1];
            String second = log.size() > 2 ? log.get(2).split(" ")[1] : "";
            if (!second.equals(first)) throw new RuntimeException("expected " + first + " after reseeding, got " + String.join(" / ", log));

            passCount++;
            System.out.println("\033[1m\033[32mPASS\033[0m - \033[90m" + label + "\033[0m");
        } catch (Throwable e) {
            failCount++;
            System.out.println("\033[1m\033[31mFAIL\033[0m - \033[90m" + label + "\033[0m");
            System.out.println("  Error: " + e);
        }
    }

    // The strategy of a when block can be a host function: it receives one record per
    // rule and returns the index of the rule to play. Same scenario in every binding runner.
    @SuppressWarnings("rawtypes")
    static void runWhenStrategyTest() {
        final String label = "when: host strategy";
        try {
            final String[] summary = { "" };
            final List<String> log = new ArrayList<>();
            InterpreterOptions options = new InterpreterOptions();
            options.functions = new HashMap<>();
            options.functions.put("chooser", (interp, args) -> {
                List records = (List) args[0];
                List<String> parts = new ArrayList<>();
                int last = -1;
                for (Object item : records) {
                    Map record = (Map) item;
                    int index = ((Number) record.get("index")).intValue();
                    boolean eligible = (Boolean) record.get("eligible");
                    parts.add(index + ":" + eligible);
                    if (eligible) last = index;
                }
                summary[0] = String.join(" ", parts);
                return last;
            });

            Script script = Loreline.parse(String.join("\n",
                "state",
                "  ready: true",
                "",
                "beat Start",
                "  when chooser",
                "    ready",
                "      Zero.",
                "    not ready",
                "      One.",
                "    true",
                "      Two.",
                "  End.",
                ""
            ));
            Loreline.play(script, (interp, character, text, tags, advance) -> { log.add(text); advance.run(); },
                (interp, opts, select) -> {}, interp -> {}, null, options);
            if (!summary[0].equals("0:true 1:false 2:true") || !String.join(",", log).equals("Two.,End.")) {
                throw new RuntimeException("records " + summary[0] + ", log " + String.join(",", log));
            }

            passCount++;
            System.out.println("\033[1m\033[32mPASS\033[0m - \033[90m" + label + "\033[0m");
        } catch (Throwable e) {
            failCount++;
            System.out.println("\033[1m\033[31mFAIL\033[0m - \033[90m" + label + "\033[0m");
            System.out.println("  Error: " + e);
        }
    }

    static void runCustomFieldsTest() {
        final String label = "custom fields: factory used for state and characters";
        try {
            final List<Interpreter> created = new ArrayList<>();
            InterpreterOptions options = new InterpreterOptions();
            options.customCreateFields = (interp, type) -> {
                created.add(interp);
                return new TestFieldsMap();
            };

            Script script = Loreline.parse(String.join("\n",
                "character bob",
                "  name: Bob",
                "",
                "beat Main",
                "  bob.mood = \"happy\"",
                "",
                "  Hello",
                ""
            ));
            Interpreter root = Loreline.play(script,
                (interp, character, text, tags, advance) -> advance.run(),
                (interp, opts, select) -> {},
                interp -> {},
                null, options);

            List<String> checks = new ArrayList<>();
            if (!(root.getCharacter("bob") instanceof TestFieldsMap)) checks.add("character bob not created by the factory");
            if (!"happy".equals(root.getCharacterField("bob", "mood"))) checks.add("bob.mood not written through the factory object");
            if (!created.contains(root)) checks.add("factory not called with the interpreter");
            if (!checks.isEmpty()) throw new RuntimeException(String.join("; ", checks));

            passCount++;
            System.out.println("\033[1m\033[32mPASS\033[0m - \033[90m" + label + "\033[0m");
        } catch (Throwable e) {
            failCount++;
            System.out.println("\033[1m\033[31mFAIL\033[0m - \033[90m" + label + "\033[0m");
            System.out.println("  Error: " + e);
        }
    }

    static void spawnNext(Map<String, Runnable> pending, String name) {
        Runnable cb = pending.remove(name);
        if (cb == null) throw new RuntimeException("No pending dialogue for " + name);
        cb.run();
    }

    public static void main(String[] args) {
        if (args.length < 1) {
            System.err.println("Usage: java TestRunner <test-directory>");
            System.exit(1);
        }

        String testDir = args[0];

        // Test fixtures exercise every supported translation format.
        Loreline.translationFormat("po", true);
        Loreline.translationFormat("xliff", true);
        Loreline.translationFormat("csv", true);

        List<String> testFiles = collectTestFiles(testDir);

        if (testFiles.isEmpty()) {
            System.err.println("No test files found in " + testDir);
            System.exit(1);
        }

        for (String filePath : testFiles) {
            String rawContent = readFile(filePath);
            if (rawContent == null) continue;

            List<Map<String, Object>> testItems = extractTests(rawContent);
            if (testItems.isEmpty()) continue;

            fileCount++;
            int failBefore = failCount;

            for (Map<String, Object> item : testItems) {
                for (boolean crlf : new boolean[]{false, true}) {
                    String modeLabel = crlf ? "CRLF" : "LF";
                    String choicesLabel = "";
                    Object choicesObj = item.get("choices");
                    if (choicesObj instanceof List && !((List<?>) choicesObj).isEmpty()) {
                        StringBuilder sb = new StringBuilder(" ~ [");
                        List<?> cl = (List<?>) choicesObj;
                        for (int i = 0; i < cl.size(); i++) {
                            if (i > 0) sb.append(",");
                            sb.append(cl.get(i));
                        }
                        sb.append("]");
                        choicesLabel = sb.toString();
                    }
                    String label = filePath + " ~ " + modeLabel + choicesLabel;

                    Object[] res = runTest(filePath, rawContent, item, crlf);
                    boolean passed = (Boolean) res[0];
                    String actual = (String) res[1];
                    String expectedStr = (String) res[2];
                    String error = (String) res[3];

                    if (passed) {
                        passCount++;
                        System.out.println("\033[1m\033[32mPASS\033[0m - \033[90m" + label + "\033[0m");
                    } else {
                        failCount++;
                        System.out.println("\033[1m\033[31mFAIL\033[0m - \033[90m" + label + "\033[0m");
                        if (error != null) {
                            System.out.println("  Error: " + error);
                        }
                        String[] expectedLines = expectedStr.replace("\r\n", "\n").trim().split("\n", -1);
                        String[] actualLines = actual.replace("\r\n", "\n").trim().split("\n", -1);
                        int minLen = Math.min(expectedLines.length, actualLines.length);

                        boolean shown = false;
                        for (int i = 0; i < minLen; i++) {
                            if (!expectedLines[i].equals(actualLines[i])) {
                                System.out.println("  > Unexpected output at line " + (i + 1));
                                System.out.println("  >  got: " + actualLines[i]);
                                System.out.println("  > need: " + expectedLines[i]);
                                shown = true;
                                break;
                            }
                        }
                        if (!shown && minLen < Math.max(expectedLines.length, actualLines.length)) {
                            if (minLen < actualLines.length) {
                                System.out.println("  > Unexpected output at line " + (minLen + 1));
                                System.out.println("  >  got: " + actualLines[minLen]);
                                System.out.println("  > need: (empty)");
                            } else {
                                System.out.println("  > Unexpected output at line " + (minLen + 1));
                                System.out.println("  >  got: (empty)");
                                System.out.println("  > need: " + expectedLines[minLen]);
                            }
                        }
                    }
                }
            }

            // Roundtrip tests
            for (boolean crlf : new boolean[]{false, true}) {
                String modeLabel = crlf ? "CRLF" : "LF";
                String label = filePath + " ~ " + modeLabel + " ~ roundtrip";
                String newline = crlf ? "\r\n" : "\n";

                try {
                    String content = rawContent.replace("\r\n", "\n");
                    if (crlf) content = content.replace("\n", "\r\n");

                    Script script1 = Loreline.parse(content, filePath, TestRunner::handleFile);
                    if (script1 == null) {
                        failCount++;
                        System.out.println("\033[1m\033[31mFAIL\033[0m - \033[90m" + label + "\033[0m");
                        System.out.println("  Error: Failed to parse original script");
                        continue;
                    }

                    String print1 = Loreline.print(script1, "  ", newline);
                    Script script2 = Loreline.parse(print1, filePath, TestRunner::handleFile);
                    if (script2 == null) {
                        failCount++;
                        System.out.println("\033[1m\033[31mFAIL\033[0m - \033[90m" + label + "\033[0m");
                        System.out.println("  Error: Failed to parse printed script");
                        continue;
                    }
                    String print2 = Loreline.print(script2, "  ", newline);

                    if (!print1.equals(print2)) {
                        failCount++;
                        System.out.println("\033[1m\033[31mFAIL\033[0m - \033[90m" + label + "\033[0m");
                        String[] lines1 = print1.replace("\r\n", "\n").split("\n", -1);
                        String[] lines2 = print2.replace("\r\n", "\n").split("\n", -1);
                        int ml = Math.min(lines1.length, lines2.length);
                        for (int i = 0; i < ml; i++) {
                            if (!lines1[i].equals(lines2[i])) {
                                System.out.println("  > Printer output not idempotent at line " + (i + 1));
                                System.out.println("  >  print1: " + lines1[i]);
                                System.out.println("  >  print2: " + lines2[i]);
                                break;
                            }
                        }
                        if (lines1.length != lines2.length) {
                            System.out.println("  > Line count differs: print1=" + lines1.length + ", print2=" + lines2.length);
                        }
                        continue;
                    }

                    // Behavioral check
                    boolean allPassed = true;
                    String firstError = null;
                    String firstExpected = null;
                    String firstActual = null;

                    for (Map<String, Object> item : testItems) {
                        Object[] res = runTest(filePath, print1, item, crlf);
                        boolean p = (Boolean) res[0];
                        if (!p) {
                            allPassed = false;
                            if (firstError == null) {
                                firstError = (String) res[3];
                                firstExpected = (String) res[2];
                                firstActual = (String) res[1];
                            }
                        }
                    }

                    if (allPassed) {
                        passCount++;
                        System.out.println("\033[1m\033[32mPASS\033[0m - \033[90m" + label + "\033[0m");
                    } else {
                        failCount++;
                        System.out.println("\033[1m\033[31mFAIL\033[0m - \033[90m" + label + "\033[0m");
                        if (firstError != null) System.out.println("  Error: " + firstError);
                        if (firstExpected != null && firstActual != null) {
                            String[] el = firstExpected.replace("\r\n", "\n").trim().split("\n", -1);
                            String[] al = firstActual.replace("\r\n", "\n").trim().split("\n", -1);
                            int ml = Math.min(el.length, al.length);
                            for (int i = 0; i < ml; i++) {
                                if (!el[i].equals(al[i])) {
                                    System.out.println("  > Unexpected output at line " + (i + 1));
                                    System.out.println("  >  got: " + al[i]);
                                    System.out.println("  > need: " + el[i]);
                                    break;
                                }
                            }
                        }
                    }
                } catch (Exception e) {
                    failCount++;
                    System.out.println("\033[1m\033[31mFAIL\033[0m - \033[90m" + label + "\033[0m");
                    System.out.println("  Error: " + e);
                }
            }

            // JSON roundtrip test
            for (boolean crlf : new boolean[] { false, true }) {
                String modeLabel = crlf ? "CRLF" : "LF";
                String label = filePath + " ~ " + modeLabel + " ~ json-roundtrip";
                try {
                    String content = rawContent.replace("\r\n", "\n");
                    if (crlf) content = content.replace("\n", "\r\n");
                    Script script = Loreline.parse(content, filePath, TestRunner::handleFile);
                    if (script == null) {
                        failCount++;
                        System.out.println("\033[1m\033[31mFAIL\033[0m - \033[90m" + label + "\033[0m");
                        System.out.println("  Error: Failed to parse script");
                    } else {
                        String json1 = script.toJson();
                        Script script2 = Script.fromJson(json1);
                        String json2 = script2.toJson();

                        if (json1.equals(json2)) {
                            passCount++;
                            System.out.println("\033[1m\033[32mPASS\033[0m - \033[90m" + label + "\033[0m");
                        } else {
                            failCount++;
                            System.out.println("\033[1m\033[31mFAIL\033[0m - \033[90m" + label + "\033[0m");
                            System.out.println("  > JSON mismatch after roundtrip");
                        }
                    }
                } catch (Exception e) {
                    failCount++;
                    System.out.println("\033[1m\033[31mFAIL\033[0m - \033[90m" + label + "\033[0m");
                    System.out.println("  Error: " + e);
                }
            }

            if (failCount > failBefore) fileFailCount++;
        }

        runSpawnTest();
        runCustomFieldsTest();
        runSeedRandomTest();
        runWhenStrategyTest();

        int total = passCount + failCount;
        System.out.println();
        if (failCount == 0) {
            System.out.println("\033[1m\033[32m  All " + total + " tests passed (" + fileCount + " files)\033[0m");
        } else {
            System.out.println("\033[1m\033[31m  " + failCount + " of " + total + " tests failed (" + fileFailCount + " of " + fileCount + " files)\033[0m");
            System.exit(1);
        }
    }
}
