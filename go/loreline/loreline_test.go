package loreline_test

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"testing"

	"github.com/mikaib/loreline/go/loreline"
)

var customTestFunctions = map[string]loreline.Function{
	"custom_echo": func(it *loreline.Interpreter, args []any) any {
		parts := make([]string, len(args))
		for i, arg := range args {
			parts[i] = fmt.Sprint(arg)
		}
		return strings.Join(parts, ",")
	},
	"custom_arg_count": func(it *loreline.Interpreter, args []any) any {
		return len(args)
	},
	"custom_set_state": func(it *loreline.Interpreter, args []any) any {
		it.SetStateField(fmt.Sprint(args[0]), args[1])
		return nil
	},
	"custom_get_state": func(it *loreline.Interpreter, args []any) any {
		return it.StateField(fmt.Sprint(args[0]))
	},
}

type testItem map[string]any

func testDir() string {
	if dir := os.Getenv("LORELINE_TEST_DIR"); dir != "" {
		return dir
	}
	return filepath.Join("..", "..", "test")
}

func collectTestFiles(t *testing.T, dir string) []string {
	var files []string
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	locale := regexp.MustCompile(`\.\w{2}\.lor$`)
	for _, entry := range entries {
		full := filepath.Join(dir, entry.Name())
		if entry.IsDir() {
			if entry.Name() != "imports" && entry.Name() != "modified" {
				files = append(files, collectTestFiles(t, full)...)
			}
		} else if strings.HasSuffix(entry.Name(), ".lor") && !locale.MatchString(entry.Name()) {
			files = append(files, full)
		}
	}
	sort.Strings(files)
	return files
}

func insertTagsInText(text string, tags []loreline.TextTag, multiline bool) string {
	chars := []rune(text)
	var b strings.Builder
	writeTag := func(tag loreline.TextTag) {
		b.WriteString("<<")
		if tag.Closing {
			b.WriteString("/")
		}
		b.WriteString(tag.Value)
		b.WriteString(">>")
	}
	for i, c := range chars {
		for _, tag := range tags {
			if tag.Offset == i {
				writeTag(tag)
			}
		}
		if multiline && c == '\n' {
			b.WriteString("\n  ")
		} else {
			b.WriteRune(c)
		}
	}
	for _, tag := range tags {
		if tag.Offset >= len(chars) {
			writeTag(tag)
		}
	}
	return strings.TrimRight(b.String(), " \t\r\n")
}

func normalizedLines(s string) []string {
	return strings.Split(strings.TrimSpace(strings.ReplaceAll(s, "\r\n", "\n")), "\n")
}

func firstDifference(expected string, actual string) (int, string, string) {
	e := normalizedLines(expected)
	a := normalizedLines(actual)
	n := min(len(e), len(a))
	for i := 0; i < n; i++ {
		if e[i] != a[i] {
			return i, a[i], e[i]
		}
	}
	if len(e) != len(a) {
		got, need := "(empty)", "(empty)"
		if n < len(a) {
			got = a[n]
		}
		if n < len(e) {
			need = e[n]
		}
		return n, got, need
	}
	return -1, "", ""
}

var (
	yamlItem = regexp.MustCompile(`^- (\w+):\s*(.*)`)
	yamlKey  = regexp.MustCompile(`^  (\w+):\s*(.*)`)
	yamlInt  = regexp.MustCompile(`^-?\d+$`)
)

func parseYamlValue(s string) any {
	s = strings.TrimSpace(s)
	switch {
	case s == "":
		return nil
	case strings.HasPrefix(s, "[") && strings.HasSuffix(s, "]"):
		inner := strings.TrimSpace(s[1 : len(s)-1])
		if inner == "" {
			return []any{}
		}
		var values []any
		for _, v := range strings.Split(inner, ",") {
			values = append(values, parseYamlValue(v))
		}
		return values
	case yamlInt.MatchString(s):
		n, _ := strconv.Atoi(s)
		return n
	case s == "true":
		return true
	case s == "false":
		return false
	case s == "null" || s == "~":
		return nil
	case len(s) >= 2 && s[0] == s[len(s)-1] && (s[0] == '"' || s[0] == '\''):
		return s[1 : len(s)-1]
	}
	return s
}

func parseSimpleYaml(text string) []testItem {
	var items []testItem
	var current testItem
	blockKey := ""
	var blockLines []string

	flush := func() {
		if blockKey != "" && current != nil {
			for len(blockLines) > 0 && blockLines[len(blockLines)-1] == "" {
				blockLines = blockLines[:len(blockLines)-1]
			}
			current[blockKey] = strings.Join(blockLines, "\n") + "\n"
		}
		blockKey = ""
		blockLines = nil
	}

	for _, line := range strings.Split(text, "\n") {
		stripped := strings.TrimRight(line, " \t\r")
		if blockKey != "" {
			if stripped == "" {
				blockLines = append(blockLines, "")
				continue
			}
			if strings.HasPrefix(line, "    ") {
				blockLines = append(blockLines, strings.TrimRight(line[4:], " \t\r"))
				continue
			}
			flush()
		}

		if m := yamlItem.FindStringSubmatch(stripped); m != nil {
			current = testItem{}
			items = append(items, current)
			if m[2] == "|" {
				blockKey = m[1]
			} else {
				current[m[1]] = parseYamlValue(m[2])
			}
			continue
		}
		if m := yamlKey.FindStringSubmatch(stripped); m != nil && current != nil {
			if m[2] == "|" {
				blockKey = m[1]
			} else {
				current[m[1]] = parseYamlValue(m[2])
			}
		}
	}
	flush()
	return items
}

func extractTests(content string) []testItem {
	var tests []testItem
	for _, m := range regexp.MustCompile(`<test>([\s\S]*?)</test>`).FindAllStringSubmatch(content, -1) {
		tests = append(tests, parseSimpleYaml(strings.TrimSpace(m[1]))...)
	}
	return tests
}

func intList(value any) []int {
	switch v := value.(type) {
	case nil:
		return nil
	case int:
		return []int{v}
	case []any:
		result := make([]int, len(v))
		for i, item := range v {
			result[i] = item.(int)
		}
		return result
	}
	panic(fmt.Sprintf("invalid indices: %v", value))
}

func contains(values []int, value int) bool {
	for _, v := range values {
		if v == value {
			return true
		}
	}
	return false
}

func setLineEndings(content string, crlf bool) string {
	content = strings.ReplaceAll(content, "\r\n", "\n")
	if crlf {
		content = strings.ReplaceAll(content, "\n", "\r\n")
	}
	return content
}

type testResult struct {
	passed   bool
	actual   string
	expected string
	err      string
}

func runTest(filePath string, content string, item testItem, crlf bool) testResult {
	content = setLineEndings(content, crlf)

	var choices []int
	if c, ok := item["choices"].([]any); ok {
		for _, v := range c {
			choices = append(choices, v.(int))
		}
	}
	beat, _ := item["beat"].(string)
	saveAtChoice := intList(item["saveAtChoice"])
	saveAtDialogue := intList(item["saveAtDialogue"])
	expected, _ := item["expected"].(string)

	var output strings.Builder
	choiceCount, dialogueCount := 0, 0
	replayingDialogue, replayingChoice := false, false
	var result *testResult

	script, err := loreline.ParseWithImports(content, filePath, loreline.ReadFile)

	var translations *loreline.Translations
	if locale, ok := item["translation"].(string); ok && locale != "" && script != nil {
		translations, err = loreline.LoadLocale(locale, script, filePath, loreline.ReadFile)
		if err != nil {
			return testResult{false, "", expected, err.Error()}
		}
	}

	var restoreInput string
	hasRestore := false
	if restoreFile, ok := item["restoreFile"].(string); ok && restoreFile != "" {
		data, err := os.ReadFile(filepath.Join(filepath.Dir(filePath), restoreFile))
		if err != nil {
			return testResult{false, "", expected, err.Error()}
		}
		restoreInput = setLineEndings(string(data), crlf)
		hasRestore = true
	}

	options := &loreline.Options{Beat: beat, Functions: customTestFunctions, Translations: translations}

	var handlers loreline.Handlers

	finish := func(it *loreline.Interpreter) {
		cmp, _, _ := firstDifference(expected, output.String())
		result = &testResult{cmp == -1, output.String(), expected, ""}
	}

	saveAndResume := func(it *loreline.Interpreter) {
		save, err := it.Save()
		if err != nil {
			result = &testResult{false, output.String(), expected, err.Error()}
			return
		}
		target := script
		if hasRestore {
			target, err = loreline.ParseWithImports(restoreInput, filePath, loreline.ReadFile)
			if err != nil {
				result = &testResult{false, output.String(), expected, "Error parsing restoreInput script"}
				return
			}
		}
		if _, err := target.Resume(handlers, save, &loreline.Options{Functions: customTestFunctions, Translations: translations}); err != nil {
			result = &testResult{false, output.String(), expected, err.Error()}
		}
	}

	handlers.Dialogue = func(it *loreline.Interpreter, character string, text string, tags []loreline.TextTag, advance func()) {
		multiline := strings.Contains(text, "\n")
		tagged := insertTagsInText(text, tags, multiline)
		if character != "" {
			name, _ := it.CharacterField(character, "name").(string)
			if name == "" {
				name = character
			}
			if multiline {
				output.WriteString(name + ":\n  " + tagged + "\n\n")
			} else {
				output.WriteString(name + ": " + tagged + "\n\n")
			}
		} else {
			output.WriteString("~ " + tagged + "\n\n")
		}

		if replayingDialogue {
			replayingDialogue = false
			advance()
			return
		}
		if contains(saveAtDialogue, dialogueCount) {
			dialogueCount++
			replayingDialogue = true
			saveAndResume(it)
			return
		}
		dialogueCount++
		advance()
	}

	handlers.Choice = func(it *loreline.Interpreter, options []loreline.ChoiceOption, choose func(int)) {
		for _, option := range options {
			prefix := "-"
			if option.Enabled {
				prefix = "+"
			}
			output.WriteString(prefix + " " + insertTagsInText(option.Text, option.Tags, strings.Contains(option.Text, "\n")) + "\n")
		}
		output.WriteString("\n")

		replayed := replayingChoice
		if replayingChoice {
			replayingChoice = false
		} else if contains(saveAtChoice, choiceCount) {
			choiceCount++
			replayingChoice = true
			saveAndResume(it)
			return
		}
		if !replayed {
			choiceCount++
		}

		if len(choices) == 0 {
			finish(it)
		} else {
			index := choices[0]
			choices = choices[1:]
			choose(index)
		}
	}

	handlers.Finish = finish

	if script == nil {
		message := "Error parsing script"
		if err != nil {
			message = err.Error()
		}
		return testResult{false, output.String(), expected, message}
	}

	if _, err := script.Play(handlers, options); err != nil && result == nil {
		result = &testResult{false, output.String(), expected, err.Error()}
	}
	if result == nil {
		result = &testResult{false, output.String(), expected, "Test did not produce a result"}
	}
	return *result
}

func reportFailure(t *testing.T, r testResult) {
	t.Helper()
	if r.err != "" {
		t.Errorf("error: %s", r.err)
	}
	if line, got, need := firstDifference(r.expected, r.actual); line != -1 {
		t.Errorf("unexpected output at line %d\n  got: %s\n need: %s", line+1, got, need)
	}
}

func TestFiles(t *testing.T) {
	loreline.TranslationFormat("po", true)
	loreline.TranslationFormat("xliff", true)
	loreline.TranslationFormat("csv", true)

	files := collectTestFiles(t, testDir())
	if len(files) == 0 {
		t.Fatal("no test files found")
	}

	for _, filePath := range files {
		data, err := os.ReadFile(filePath)
		if err != nil {
			t.Fatal(err)
		}
		raw := string(data)
		items := extractTests(raw)
		if len(items) == 0 {
			continue
		}

		t.Run(filepath.Base(filePath), func(t *testing.T) {
			for _, crlf := range []bool{false, true} {
				mode := "LF"
				newline := "\n"
				if crlf {
					mode = "CRLF"
					newline = "\r\n"
				}

				for i, item := range items {
					t.Run(fmt.Sprintf("%s/%d", mode, i), func(t *testing.T) {
						if r := runTest(filePath, raw, item, crlf); !r.passed {
							reportFailure(t, r)
						}
					})
				}

				t.Run(mode+"/roundtrip", func(t *testing.T) {
					content := setLineEndings(raw, crlf)
					script1, err := loreline.ParseWithImports(content, filePath, loreline.ReadFile)
					if err != nil {
						t.Fatal(err)
					}
					print1 := script1.Print("  ", newline)
					script2, err := loreline.ParseWithImports(print1, filePath, loreline.ReadFile)
					if err != nil {
						t.Fatalf("failed to parse printed script: %v", err)
					}
					if print2 := script2.Print("  ", newline); print1 != print2 {
						t.Fatal("printer output not idempotent")
					}
					for _, item := range items {
						if r := runTest(filePath, print1, item, crlf); !r.passed {
							reportFailure(t, r)
							return
						}
					}
				})

				t.Run(mode+"/json-roundtrip", func(t *testing.T) {
					script, err := loreline.ParseWithImports(setLineEndings(raw, crlf), filePath, loreline.ReadFile)
					if err != nil {
						t.Fatal(err)
					}
					json1 := script.ToJSON(false)
					script2, err := loreline.ScriptFromJSON(json1)
					if err != nil {
						t.Fatal(err)
					}
					if json1 != script2.ToJSON(false) {
						t.Fatal("JSON mismatch after roundtrip")
					}
				})
			}
		})
	}
}

const spawnScript = `state
  gold: 0

beat Main
  gold = gold + 1

  Main gold $gold

  Main where $current_beat() host $who()

beat Side
  new state
    local: 5

  gold = gold + 10

  Side gold $gold local $local

  Side where $current_beat() host $who()
`

func TestSpawn(t *testing.T) {
	var log []string
	pending := map[string]func(){}

	nameOf := func(it *loreline.Interpreter) string {
		if it.Key() != "" {
			return it.Key()
		}
		return "root"
	}

	handlers := loreline.Handlers{
		Dialogue: func(it *loreline.Interpreter, character string, text string, tags []loreline.TextTag, advance func()) {
			prefix := ""
			if character != "" {
				prefix = character + ": "
			}
			log = append(log, nameOf(it)+": "+prefix+text)
			pending[nameOf(it)] = advance
		},
		Choice: func(it *loreline.Interpreter, options []loreline.ChoiceOption, choose func(int)) {},
		Finish: func(it *loreline.Interpreter) {},
	}

	next := func(name string) {
		advance, ok := pending[name]
		if !ok {
			t.Fatalf("no pending dialogue for %s", name)
		}
		delete(pending, name)
		advance()
	}

	options := &loreline.Options{Functions: map[string]loreline.Function{
		"who": func(it *loreline.Interpreter, args []any) any { return nameOf(it) },
	}}

	script, err := loreline.Parse(spawnScript)
	if err != nil {
		t.Fatal(err)
	}
	root, err := script.Play(handlers, options)
	if err != nil {
		t.Fatal(err)
	}
	npc, err := root.Spawn("npc", handlers)
	if err != nil {
		t.Fatal(err)
	}
	if err := npc.Start("Side"); err != nil {
		t.Fatal(err)
	}
	next("root")

	if npc.Key() != "npc" || root.Key() != "" {
		t.Errorf("keys: %q %q", npc.Key(), root.Key())
	}
	if npc.IsRoot() || !root.IsRoot() {
		t.Error("IsRoot")
	}

	save, err := npc.Save()
	if err != nil {
		t.Fatal(err)
	}
	rootSave, _ := root.Save()
	for _, s := range []string{save, rootSave} {
		var data struct {
			Children []any `json:"children"`
		}
		if err := json.Unmarshal([]byte(s), &data); err != nil || len(data.Children) != 1 {
			t.Errorf("save does not include both playheads: %v", err)
		}
	}

	pending = map[string]func(){}
	restored, err := script.Resume(handlers, save, options)
	if err != nil {
		t.Fatal(err)
	}
	if keys := restored.ResumableSpawnKeys(); len(keys) != 1 || keys[0] != "npc" {
		t.Errorf("ResumableSpawnKeys: %v", keys)
	}
	child, err := restored.ResumeSpawn("npc", handlers)
	if err != nil {
		t.Fatal(err)
	}
	if err := child.Resume(); err != nil {
		t.Fatal(err)
	}
	next("npc")

	expected := []string{
		"root: Main gold 1",
		"npc: Side gold 11 local 5",
		"root: Main where Main host root",
		"root: Main where Main host root",
		"npc: Side gold 11 local 5",
		"npc: Side where Side host npc",
	}
	if strings.Join(log, "\n") != strings.Join(expected, "\n") {
		t.Errorf("log:\n%s", strings.Join(log, "\n"))
	}
}

func TestSeedRandom(t *testing.T) {
	var log []string
	var pending []func()
	handlers := loreline.Handlers{
		Dialogue: func(it *loreline.Interpreter, character string, text string, tags []loreline.TextTag, advance func()) {
			log = append(log, text)
			pending = append(pending, advance)
		},
		Choice: func(it *loreline.Interpreter, options []loreline.ChoiceOption, choose func(int)) {},
		Finish: func(it *loreline.Interpreter) {},
	}

	script, err := loreline.Parse("beat Main\n  seed_random(7)\n  First $random(1, 1000000000)\n\n  Second $random(1, 1000000000)\n")
	if err != nil {
		t.Fatal(err)
	}
	root, err := script.Play(handlers, nil)
	if err != nil {
		t.Fatal(err)
	}
	save, err := root.Save()
	if err != nil {
		t.Fatal(err)
	}
	restored, err := script.Resume(handlers, save, nil)
	if err != nil {
		t.Fatal(err)
	}
	restored.SeedRandom(7)
	pending[len(pending)-1]()

	if len(log) < 3 || strings.Fields(log[0])[1] != strings.Fields(log[2])[1] {
		t.Errorf("expected the same draw after reseeding, got %s", strings.Join(log, " / "))
	}
}

func TestWhenStrategy(t *testing.T) {
	var summary []string
	var log []string
	options := &loreline.Options{Functions: map[string]loreline.Function{
		"chooser": func(it *loreline.Interpreter, args []any) any {
			var parts []string
			last := -1
			for _, record := range args[0].([]any) {
				fields := record.(map[string]any)
				index := fields["index"].(int)
				eligible := fields["eligible"].(bool)
				parts = append(parts, fmt.Sprintf("%d:%t", index, eligible))
				if eligible {
					last = index
				}
			}
			summary = append(summary, strings.Join(parts, " "))
			return last
		},
	}}
	handlers := loreline.Handlers{
		Dialogue: func(it *loreline.Interpreter, character string, text string, tags []loreline.TextTag, advance func()) {
			log = append(log, text)
			advance()
		},
	}

	script, err := loreline.Parse("state\n  ready: true\n\nbeat Start\n  when chooser\n    ready\n      Zero.\n    not ready\n      One.\n    true\n      Two.\n  End.\n")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := script.Play(handlers, options); err != nil {
		t.Fatal(err)
	}
	if strings.Join(summary, "|") != "0:true 1:false 2:true" || strings.Join(log, ",") != "Two.,End." {
		t.Errorf("records %v, log %v", summary, log)
	}
}

func TestErrors(t *testing.T) {
	if _, err := loreline.Parse("beat Main\n  choice\n    \"A\" ->\n  if (\n"); err == nil {
		t.Error("expected a parse error")
	}

	script, err := loreline.Parse("beat Main\n  Hello\n")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := script.Play(loreline.Handlers{}, &loreline.Options{Beat: "Missing"}); err == nil {
		t.Error("expected an error for a missing beat")
	}
}

var failingFunctions = &loreline.Options{Functions: map[string]loreline.Function{
	"fail": func(it *loreline.Interpreter, args []any) any { panic("boom") },
}}

func TestAsyncChooseError(t *testing.T) {
	script, err := loreline.Parse("beat Main\n  choice\n    Go\n      Result $fail()\n")
	if err != nil {
		t.Fatal(err)
	}

	var choose func(int)
	var reported error
	it, err := script.Play(loreline.Handlers{
		Choice: func(it *loreline.Interpreter, options []loreline.ChoiceOption, pick func(int)) {
			choose = pick
		},
		Error: func(it *loreline.Interpreter, err error) {
			reported = err
		},
	}, failingFunctions)
	if err != nil {
		t.Fatal(err)
	}

	choose(0)

	if reported == nil || it.Err() == nil {
		t.Fatalf("expected the script error to be reported, got %v / %v", reported, it.Err())
	}
	t.Log("async error:", reported)
}

func TestSyncAdvanceError(t *testing.T) {
	script, err := loreline.Parse("beat Main\n  Hello\n  Result $fail()\n")
	if err != nil {
		t.Fatal(err)
	}

	_, err = script.Play(loreline.Handlers{
		Dialogue: func(it *loreline.Interpreter, character string, text string, tags []loreline.TextTag, advance func()) {
			advance()
		},
	}, failingFunctions)
	if err == nil {
		t.Fatal("expected Play to return the script error")
	}
	t.Log("sync error:", err)
}

func TestNodesAndState(t *testing.T) {
	script, err := loreline.Parse("state\n  coins: 3\n\ncharacter barista\n  name: Alex\n\nbeat Main\n  barista: Hello $coins\n")
	if err != nil {
		t.Fatal(err)
	}
	if script.Type() != "Script" || script.Line() != 1 {
		t.Errorf("script node: %s line %d", script.Type(), script.Line())
	}
	node, err := loreline.NodeFromJSON(script.ToJSON(false))
	if err != nil || node.Type() != "Script" {
		t.Errorf("NodeFromJSON: %v", err)
	}

	var current *loreline.Node
	it, err := script.Play(loreline.Handlers{
		Dialogue: func(it *loreline.Interpreter, character string, text string, tags []loreline.TextTag, advance func()) {
			current = it.CurrentNode()
		},
	}, nil)
	if err != nil {
		t.Fatal(err)
	}
	if current == nil || current.Type() != "Dialogue" {
		t.Errorf("CurrentNode during dialogue: %v", current)
	}
	if it.StateField("coins") != 3.0 || it.TopLevelStateField("coins") != 3.0 {
		t.Errorf("coins: %v", it.StateField("coins"))
	}
	it.SetTopLevelStateField("coins", 7)
	if it.StateField("coins") != 7 {
		t.Errorf("coins after set: %v", it.StateField("coins"))
	}
	if it.Character("barista")["name"] != "Alex" || it.CharacterField("barista", "name") != "Alex" {
		t.Errorf("character: %v", it.Character("barista"))
	}
}
