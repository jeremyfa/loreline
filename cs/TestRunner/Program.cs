using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using Loreline;

class Program
{
    static int passCount = 0;
    static int failCount = 0;

    static void Main(string[] args)
    {
        if (args.Length == 0)
        {
            Console.Error.WriteLine("Usage: dotnet run --project cs/TestRunner -- <test-directory>");
            Environment.Exit(1);
        }

        string testDir = args[0];
        var testFiles = CollectTestFiles(testDir);

        if (testFiles.Count == 0)
        {
            Console.Error.WriteLine($"No test files found in {testDir}");
            Environment.Exit(1);
        }

        foreach (string filePath in testFiles)
        {
            string rawContent = File.ReadAllText(filePath, Encoding.UTF8);
            var testItems = ExtractTests(rawContent);
            if (testItems.Count == 0) continue;

            foreach (var item in testItems)
            {
                foreach (bool crlf in new[] { false, true })
                {
                    string modeLabel = crlf ? "CRLF" : "LF";
                    string choicesLabel = item.Choices != null ? $" ~ [{string.Join(",", item.Choices)}]" : "";
                    string label = $"{filePath} ~ {modeLabel}{choicesLabel}";

                    var result = RunTest(filePath, rawContent, item, crlf);

                    if (result.Passed)
                    {
                        passCount++;
                        Console.WriteLine($"\x1b[1m\x1b[32mPASS\x1b[0m - \x1b[90m{label}\x1b[0m");
                    }
                    else
                    {
                        failCount++;
                        Console.WriteLine($"\x1b[1m\x1b[31mFAIL\x1b[0m - \x1b[90m{label}\x1b[0m");
                        if (result.Error != null)
                        {
                            Console.WriteLine($"  Error: {result.Error}");
                        }
                        ShowDiff(result.Expected, result.Actual);
                    }
                }
            }

            // Roundtrip tests for each mode (LF, CRLF)
            foreach (bool crlf in new[] { false, true })
            {
                string modeLabel = crlf ? "CRLF" : "LF";
                string label = $"{filePath} ~ {modeLabel} ~ roundtrip";
                string newline = crlf ? "\r\n" : "\n";

                try
                {
                    // Normalize content for this mode
                    string content = rawContent.Replace("\r\n", "\n");
                    if (crlf)
                    {
                        content = content.Replace("\n", "\r\n");
                    }

                    // Parse original
                    Script script1 = Engine.Parse(content, filePath, HandleFile);
                    if (script1 == null)
                    {
                        failCount++;
                        Console.WriteLine($"\x1b[1m\x1b[31mFAIL\x1b[0m - \x1b[90m{label}\x1b[0m");
                        Console.WriteLine("  Error: Failed to parse original script");
                        continue;
                    }

                    // Structural check: print → parse → print must be stable
                    string print1 = Engine.Print(script1, "  ", newline);
                    Script script2 = Engine.Parse(print1, filePath, HandleFile);
                    if (script2 == null)
                    {
                        failCount++;
                        Console.WriteLine($"\x1b[1m\x1b[31mFAIL\x1b[0m - \x1b[90m{label}\x1b[0m");
                        Console.WriteLine("  Error: Failed to parse printed script");
                        continue;
                    }
                    string print2 = Engine.Print(script2, "  ", newline);

                    if (print1 != print2)
                    {
                        failCount++;
                        Console.WriteLine($"\x1b[1m\x1b[31mFAIL\x1b[0m - \x1b[90m{label}\x1b[0m");
                        var lines1 = print1.Replace("\r\n", "\n").Split('\n');
                        var lines2 = print2.Replace("\r\n", "\n").Split('\n');
                        int ml = Math.Min(lines1.Length, lines2.Length);
                        for (int i = 0; i < ml; i++)
                        {
                            if (lines1[i] != lines2[i])
                            {
                                Console.WriteLine($"  > Printer output not idempotent at line {i + 1}");
                                Console.WriteLine($"  >  print1: {lines1[i]}");
                                Console.WriteLine($"  >  print2: {lines2[i]}");
                                break;
                            }
                        }
                        if (lines1.Length != lines2.Length)
                        {
                            Console.WriteLine($"  > Line count differs: print1={lines1.Length}, print2={lines2.Length}");
                        }
                        continue;
                    }

                    // Behavioral check: run each test item on the printed content
                    bool allPassed = true;
                    string firstError = null;
                    string firstExpected = null;
                    string firstActual = null;

                    foreach (var item in testItems)
                    {
                        var rtResult = RunTest(filePath, print1, item, crlf);
                        if (!rtResult.Passed)
                        {
                            allPassed = false;
                            if (firstError == null)
                            {
                                firstError = rtResult.Error;
                                firstExpected = rtResult.Expected;
                                firstActual = rtResult.Actual;
                            }
                        }
                    }

                    if (allPassed)
                    {
                        passCount++;
                        Console.WriteLine($"\x1b[1m\x1b[32mPASS\x1b[0m - \x1b[90m{label}\x1b[0m");
                    }
                    else
                    {
                        failCount++;
                        Console.WriteLine($"\x1b[1m\x1b[31mFAIL\x1b[0m - \x1b[90m{label}\x1b[0m");
                        if (firstError != null)
                        {
                            Console.WriteLine($"  Error: {firstError}");
                        }
                        if (firstExpected != null && firstActual != null)
                        {
                            ShowDiff(firstExpected, firstActual);
                        }
                    }
                }
                catch (Exception e)
                {
                    failCount++;
                    Console.WriteLine($"\x1b[1m\x1b[31mFAIL\x1b[0m - \x1b[90m{label}\x1b[0m");
                    Console.WriteLine($"  Error: {e}");
                }
            }
        }

        int total = passCount + failCount;
        Console.WriteLine();
        if (failCount == 0)
        {
            Console.WriteLine($"\x1b[1m\x1b[32m  All {total} tests passed\x1b[0m");
        }
        else
        {
            Console.WriteLine($"\x1b[1m\x1b[31m  {failCount} of {total} tests failed\x1b[0m");
            Environment.Exit(1);
        }
    }

    static List<string> CollectTestFiles(string dir)
    {
        var files = new List<string>();
        foreach (string entry in Directory.GetFileSystemEntries(dir))
        {
            if (Directory.Exists(entry))
            {
                string name = Path.GetFileName(entry);
                if (name != "imports" && name != "modified")
                {
                    files.AddRange(CollectTestFiles(entry));
                }
            }
            else if (entry.EndsWith(".lor") && !Regex.IsMatch(Path.GetFileName(entry), @"\.\w{2}\.lor$"))
            {
                files.Add(entry);
            }
        }
        files.Sort(StringComparer.Ordinal);
        return files;
    }

    static void HandleFile(string path, Engine.ImportsFileCallback callback)
    {
        try
        {
            string content = File.ReadAllText(path, Encoding.UTF8);
            callback(content);
        }
        catch
        {
            callback(null);
        }
    }

    static string InsertTagsInText(string text, Interpreter.TextTag[] tags, bool multiline)
    {
        var offsetsWithTags = new HashSet<int>();
        foreach (var tag in tags)
        {
            offsetsWithTags.Add(tag.Offset);
        }

        int len = text.Length;
        var result = new StringBuilder();

        for (int i = 0; i < len; i++)
        {
            if (offsetsWithTags.Contains(i))
            {
                foreach (var tag in tags)
                {
                    if (tag.Offset == i)
                    {
                        result.Append("<<");
                        if (tag.Closing) result.Append("/");
                        result.Append(tag.Value);
                        result.Append(">>");
                    }
                }
            }
            char c = text[i];
            if (multiline && c == '\n')
            {
                result.Append("\n  ");
            }
            else
            {
                result.Append(c);
            }
        }

        foreach (var tag in tags)
        {
            if (tag.Offset >= len)
            {
                result.Append("<<");
                if (tag.Closing) result.Append("/");
                result.Append(tag.Value);
                result.Append(">>");
            }
        }

        return result.ToString().TrimEnd();
    }

    static int CompareOutput(string expected, string actual)
    {
        var expectedLines = expected.Replace("\r\n", "\n").Trim().Split('\n');
        var actualLines = actual.Replace("\r\n", "\n").Trim().Split('\n');
        int minLen = Math.Min(expectedLines.Length, actualLines.Length);
        int maxLen = Math.Max(expectedLines.Length, actualLines.Length);

        for (int i = 0; i < minLen; i++)
        {
            if (expectedLines[i] != actualLines[i]) return i;
        }
        if (minLen < maxLen) return minLen;
        return -1;
    }

    static void ShowDiff(string expected, string actual)
    {
        if (expected == null || actual == null) return;
        var expectedLines = expected.Replace("\r\n", "\n").Trim().Split('\n');
        var actualLines = actual.Replace("\r\n", "\n").Trim().Split('\n');
        int minLen = Math.Min(expectedLines.Length, actualLines.Length);

        for (int i = 0; i < minLen; i++)
        {
            if (expectedLines[i] != actualLines[i])
            {
                Console.WriteLine($"  > Unexpected output at line {i + 1}");
                Console.WriteLine($"  >  got: {actualLines[i]}");
                Console.WriteLine($"  > need: {expectedLines[i]}");
                return;
            }
        }
        if (minLen < Math.Max(expectedLines.Length, actualLines.Length))
        {
            if (minLen < actualLines.Length)
            {
                Console.WriteLine($"  > Unexpected output at line {minLen + 1}");
                Console.WriteLine($"  >  got: {actualLines[minLen]}");
                Console.WriteLine($"  > need: (empty)");
            }
            else
            {
                Console.WriteLine($"  > Unexpected output at line {minLen + 1}");
                Console.WriteLine($"  >  got: (empty)");
                Console.WriteLine($"  > need: {expectedLines[minLen]}");
            }
        }
    }

    struct TestResult
    {
        public bool Passed;
        public string Actual;
        public string Expected;
        public string Error;
    }

    static TestResult RunTest(string filePath, string content, TestItem item, bool crlf)
    {
        if (crlf)
        {
            content = content.Replace("\r\n", "\n").Replace("\n", "\r\n");
        }
        else
        {
            content = content.Replace("\r\n", "\n");
        }

        var choices = item.Choices != null ? new List<int>(item.Choices) : null;
        string beatName = item.Beat;
        int saveAtChoice = item.SaveAtChoice ?? -1;
        int saveAtDialogue = item.SaveAtDialogue ?? -1;
        string expected = item.Expected;
        var output = new StringBuilder();
        int choiceCount = 0;
        int dialogueCount = 0;
        Script parsedScript = null;
        TestResult testResult = new TestResult { Expected = expected };

        // Build options
        Interpreter.InterpreterOptions options = Interpreter.InterpreterOptions.Default();
        if (item.Translation != null)
        {
            string lang = item.Translation;
            string basePath = filePath.Substring(0, filePath.Length - 4);
            string translationPath = basePath + "." + lang + ".lor";
            string translationContent = File.ReadAllText(translationPath, Encoding.UTF8);
            if (crlf)
            {
                translationContent = translationContent.Replace("\r\n", "\n").Replace("\n", "\r\n");
            }
            else
            {
                translationContent = translationContent.Replace("\r\n", "\n");
            }
            Script translationScript = Engine.Parse(translationContent, translationPath, HandleFile);
            if (translationScript != null)
            {
                options.Translations = Engine.ExtractTranslations(translationScript);
            }
        }

        // Load restoreFile content
        string restoreInput = null;
        if (item.RestoreFile != null)
        {
            string restorePath = Path.Combine(Path.GetDirectoryName(filePath), item.RestoreFile);
            restoreInput = File.ReadAllText(restorePath, Encoding.UTF8);
            if (crlf)
            {
                restoreInput = restoreInput.Replace("\r\n", "\n").Replace("\n", "\r\n");
            }
            else
            {
                restoreInput = restoreInput.Replace("\r\n", "\n");
            }
        }

        void handleFinish(Interpreter.Finish finish)
        {
            int cmp = CompareOutput(expected, output.ToString());
            testResult.Passed = (cmp == -1);
            testResult.Actual = output.ToString();
        }

        void handleDialogue(Interpreter.Dialogue dialogue)
        {
            bool multiline = dialogue.Text.Contains("\n");
            if (dialogue.Character != null)
            {
                string charName = (string)dialogue.Interpreter.GetCharacterField(dialogue.Character, "name") ?? dialogue.Character;
                string taggedText = InsertTagsInText(dialogue.Text, dialogue.Tags, multiline);
                if (multiline)
                {
                    output.Append(charName + ":\n  " + taggedText + "\n\n");
                }
                else
                {
                    output.Append(charName + ": " + taggedText + "\n\n");
                }
            }
            else
            {
                string taggedText = InsertTagsInText(dialogue.Text, dialogue.Tags, multiline);
                output.Append("~ " + taggedText + "\n\n");
            }

            // Save/restore test at dialogue
            if (saveAtDialogue >= 0 && dialogueCount == saveAtDialogue)
            {
                dialogueCount++;
                string saveData = dialogue.Interpreter.Save();

                if (restoreInput != null)
                {
                    Script restoreScript = Engine.Parse(restoreInput, filePath, HandleFile);
                    if (restoreScript != null)
                    {
                        Engine.Resume(restoreScript, handleDialogue, handleChoice, handleFinish, saveData, null, options);
                    }
                    else
                    {
                        testResult.Passed = false;
                        testResult.Actual = output.ToString();
                        testResult.Error = "Error parsing restoreInput script";
                    }
                }
                else
                {
                    Engine.Resume(parsedScript, handleDialogue, handleChoice, handleFinish, saveData, null, options);
                }
                return;
            }

            dialogueCount++;
            dialogue.Callback();
        }

        void handleChoice(Interpreter.Choice choice)
        {
            foreach (var opt in choice.Options)
            {
                string prefix = opt.Enabled ? "+" : "-";
                bool multiline = opt.Text.Contains("\n");
                string taggedText = InsertTagsInText(opt.Text, opt.Tags, multiline);
                output.Append(prefix + " " + taggedText + "\n");
            }
            output.Append("\n");

            // Save/restore test
            if (saveAtChoice >= 0 && choiceCount == saveAtChoice)
            {
                choiceCount++;
                string saveData = choice.Interpreter.Save();

                if (restoreInput != null)
                {
                    Script restoreScript = Engine.Parse(restoreInput, filePath, HandleFile);
                    if (restoreScript != null)
                    {
                        Engine.Resume(restoreScript, handleDialogue, handleChoice, handleFinish, saveData, null, options);
                    }
                    else
                    {
                        testResult.Passed = false;
                        testResult.Actual = output.ToString();
                        testResult.Error = "Error parsing restoreInput script";
                    }
                }
                else
                {
                    Engine.Resume(parsedScript, handleDialogue, handleChoice, handleFinish, saveData, null, options);
                }
                return;
            }

            choiceCount++;

            if (choices == null || choices.Count == 0)
            {
                handleFinish(new Interpreter.Finish { Interpreter = choice.Interpreter });
            }
            else
            {
                int index = choices[0];
                choices.RemoveAt(0);
                choice.Callback(index);
            }
        }

        try
        {
            Script script = Engine.Parse(content, filePath, HandleFile);
            if (script != null)
            {
                parsedScript = script;
                Engine.Play(script, handleDialogue, handleChoice, handleFinish, beatName, options);
            }
            else
            {
                testResult.Passed = false;
                testResult.Actual = output.ToString();
                testResult.Error = "Error parsing script";
            }
        }
        catch (Exception e)
        {
            testResult.Passed = false;
            testResult.Actual = output.ToString();
            testResult.Error = e.ToString();
        }

        return testResult;
    }

    class TestItem
    {
        public string Beat { get; set; }
        public List<int> Choices { get; set; }
        public string Expected { get; set; }
        public int? SaveAtChoice { get; set; }
        public int? SaveAtDialogue { get; set; }
        public string RestoreFile { get; set; }
        public string Translation { get; set; }
    }

    static List<TestItem> ExtractTests(string content)
    {
        var tests = new List<TestItem>();
        var regex = new Regex(@"<test>([\s\S]*?)</test>");
        var matches = regex.Matches(content);

        foreach (Match match in matches)
        {
            string yamlContent = match.Groups[1].Value.Trim();
            tests.AddRange(ParseTestItems(yamlContent));
        }

        return tests;
    }

    static List<TestItem> ParseTestItems(string yaml)
    {
        var items = new List<TestItem>();
        var lines = yaml.Replace("\r\n", "\n").Split('\n');
        TestItem current = null;
        string currentKey = null;
        StringBuilder blockValue = null;
        int blockIndent = 0;

        for (int i = 0; i < lines.Length; i++)
        {
            string line = lines[i];

            // Collect block scalar lines (for "expected: |")
            if (blockValue != null)
            {
                if (line.Length > 0 && line.TrimStart().Length > 0)
                {
                    int indent = line.Length - line.TrimStart().Length;
                    if (indent >= blockIndent)
                    {
                        blockValue.Append(line.Substring(blockIndent) + "\n");
                        continue;
                    }
                }
                else if (line.Trim().Length == 0)
                {
                    blockValue.Append("\n");
                    continue;
                }

                // Block ended
                if (currentKey == "expected")
                    current.Expected = blockValue.ToString();
                blockValue = null;
                currentKey = null;
            }

            string trimmed = line.TrimStart();

            // New list item
            if (trimmed.StartsWith("- "))
            {
                current = new TestItem();
                items.Add(current);
                trimmed = trimmed.Substring(2).TrimStart();
            }
            else if (trimmed.Length == 0 || current == null)
            {
                continue;
            }

            // Parse key: value
            int colonIdx = trimmed.IndexOf(':');
            if (colonIdx <= 0) continue;

            string key = trimmed.Substring(0, colonIdx).Trim();
            string value = trimmed.Substring(colonIdx + 1).Trim();

            switch (key)
            {
                case "beat":
                    current.Beat = value;
                    break;
                case "choices":
                    current.Choices = ParseIntList(value);
                    break;
                case "expected":
                    if (value == "|")
                    {
                        currentKey = "expected";
                        blockValue = new StringBuilder();
                        blockIndent = (line.Length - line.TrimStart().Length) + 2;
                        if (trimmed.StartsWith("- ") || items.Count == 1 && i < 3)
                            blockIndent = line.Length - line.TrimStart().Length + 2;
                        // Determine block indent from next non-empty line
                        for (int j = i + 1; j < lines.Length; j++)
                        {
                            if (lines[j].Trim().Length > 0)
                            {
                                blockIndent = lines[j].Length - lines[j].TrimStart().Length;
                                break;
                            }
                        }
                    }
                    else
                    {
                        current.Expected = value;
                    }
                    break;
                case "saveAtChoice":
                    if (int.TryParse(value, out int sac))
                        current.SaveAtChoice = sac;
                    break;
                case "saveAtDialogue":
                    if (int.TryParse(value, out int sad))
                        current.SaveAtDialogue = sad;
                    break;
                case "restoreFile":
                    current.RestoreFile = value;
                    break;
                case "translation":
                    current.Translation = value;
                    break;
            }
        }

        // Flush final block
        if (blockValue != null && current != null && currentKey == "expected")
        {
            current.Expected = blockValue.ToString();
        }

        return items;
    }

    static List<int> ParseIntList(string value)
    {
        // Parse "[1, 2, 3]" or "[]"
        value = value.Trim();
        if (value.StartsWith("[")) value = value.Substring(1);
        if (value.EndsWith("]")) value = value.Substring(0, value.Length - 1);
        value = value.Trim();
        if (value.Length == 0) return new List<int>();

        var result = new List<int>();
        foreach (string part in value.Split(','))
        {
            if (int.TryParse(part.Trim(), out int n))
                result.Add(n);
        }
        return result;
    }
}
