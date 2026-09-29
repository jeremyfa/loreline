<?php

/**
 * Loreline PHP test runner.
 *
 * Follows the same test protocol as the JS, Python, C#, and C++ test runners:
 *   - Collects .lor files from the given directory
 *   - Extracts <test> YAML blocks from comments
 *   - Runs each test in LF and CRLF modes
 *   - Runs roundtrip (parse -> print -> parse -> print) stability checks
 *   - Runs JSON roundtrip checks
 *   - Reports pass/fail counts, exit code 1 on any failure
 *
 * Drives the PUBLIC Loreline\ wrapper (the same API a real user uses), so the
 * suite exercises the public wrapper layer end to end, including custom
 * functions and the native PHP array marshalling.
 *
 * Note: ast-print is intentionally only run by the CLI test runner.
 */

require __DIR__ . '/src/autoload.php';

use Loreline\Loreline;
use Loreline\Script;

$passCount = 0;
$failCount = 0;
$fileCount = 0;
$fileFailCount = 0;

// -- Helpers ----------------------------------------------------------------

function collectTestFiles(string $directory): array
{
    $files = [];
    $entries = scandir($directory);
    sort($entries);
    foreach ($entries as $entry) {
        if ($entry === '.' || $entry === '..') {
            continue;
        }
        $fullPath = $directory . DIRECTORY_SEPARATOR . $entry;
        if (is_dir($fullPath)) {
            if ($entry !== 'imports' && $entry !== 'modified') {
                $files = array_merge($files, collectTestFiles($fullPath));
            }
        } elseif (str_ends_with($entry, '.lor') && !preg_match('/\.\w{2}\.lor$/', $entry)) {
            $files[] = $fullPath;
        }
    }
    return $files;
}

$handleFile = function (string $path, $callback): void {
    $content = @file_get_contents($path);
    $callback($content === false ? null : $content);
};

function lorStr(mixed $value): string
{
    if ($value === null) {
        return 'null';
    }
    if (is_bool($value)) {
        return $value ? 'true' : 'false';
    }
    if (is_float($value) && is_finite($value) && $value === floor($value)) {
        return (string) (int) $value;
    }
    return (string) $value;
}

function insertTagsInText(string $text, array $tags, bool $multiline): string
{
    $chars = $text === '' ? [] : mb_str_split($text);
    $length = count($chars);
    $result = '';

    for ($i = 0; $i < $length; $i++) {
        foreach ($tags as $tag) {
            if ($tag->offset === $i) {
                $result .= '<<';
                if ($tag->closing) {
                    $result .= '/';
                }
                $result .= $tag->value . '>>';
            }
        }
        $c = $chars[$i];
        if ($multiline && $c === "\n") {
            $result .= "\n  ";
        } else {
            $result .= $c;
        }
    }

    foreach ($tags as $tag) {
        if ($tag->offset >= $length) {
            $result .= '<<';
            if ($tag->closing) {
                $result .= '/';
            }
            $result .= $tag->value . '>>';
        }
    }

    return rtrim($result);
}

function compareOutput(string $expected, string $actual): int
{
    $expectedLines = explode("\n", trim(str_replace("\r\n", "\n", $expected)));
    $actualLines = explode("\n", trim(str_replace("\r\n", "\n", $actual)));
    $minLen = min(count($expectedLines), count($actualLines));
    $maxLen = max(count($expectedLines), count($actualLines));

    for ($i = 0; $i < $minLen; $i++) {
        if ($expectedLines[$i] !== $actualLines[$i]) {
            return $i;
        }
    }
    return $minLen < $maxLen ? $minLen : -1;
}

function parseYamlValue(string $s): mixed
{
    $s = trim($s);
    if ($s === '') {
        return null;
    }
    if (str_starts_with($s, '[') && str_ends_with($s, ']')) {
        $inner = trim(substr($s, 1, -1));
        if ($inner === '') {
            return [];
        }
        return array_map(fn ($v) => parseYamlValue(trim($v)), explode(',', $inner));
    }
    if (preg_match('/^-?\d+$/', $s)) {
        return (int) $s;
    }
    if ($s === 'true') {
        return true;
    }
    if ($s === 'false') {
        return false;
    }
    if ($s === 'null' || $s === '~') {
        return null;
    }
    if (strlen($s) >= 2 && $s[0] === $s[strlen($s) - 1] && ($s[0] === '"' || $s[0] === "'")) {
        return substr($s, 1, -1);
    }
    return $s;
}

/**
 * Minimal YAML parser for test blocks. Supports the subset used by loreline
 * tests: a top level list of maps, scalar values, inline flow sequences and
 * literal block scalars introduced by "|".
 */
function parseSimpleYaml(string $text): array
{
    $lines = explode("\n", $text);
    $items = [];
    $current = null;
    $currentIndex = -1;
    $blockKey = null;
    $blockIndent = 0;
    $blockLines = [];
    $i = 0;
    $count = count($lines);

    $flushBlock = function () use (&$items, &$currentIndex, &$blockKey, &$blockLines): void {
        if ($blockKey !== null && $currentIndex >= 0) {
            while (count($blockLines) > 0 && $blockLines[count($blockLines) - 1] === '') {
                array_pop($blockLines);
            }
            $items[$currentIndex][$blockKey] = implode("\n", $blockLines) . "\n";
        }
        $blockKey = null;
        $blockLines = [];
    };

    while ($i < $count) {
        $line = $lines[$i];
        $stripped = rtrim($line);

        if ($blockKey !== null) {
            if ($stripped === '') {
                $blockLines[] = '';
                $i++;
                continue;
            }
            if (strlen($line) >= $blockIndent && substr($line, 0, $blockIndent) === str_repeat(' ', $blockIndent)) {
                $blockLines[] = rtrim(substr($line, $blockIndent));
                $i++;
                continue;
            }
            $flushBlock();
        }

        if (preg_match('/^- (\w+):\s*(.*)/', $stripped, $m)) {
            $items[] = [];
            $currentIndex = count($items) - 1;
            $key = $m[1];
            $value = $m[2];
            if ($value === '|') {
                $blockKey = $key;
                $blockIndent = 4;
                $blockLines = [];
            } else {
                $items[$currentIndex][$key] = parseYamlValue($value);
            }
            $i++;
            continue;
        }

        if ($currentIndex >= 0 && preg_match('/^  (\w+):\s*(.*)/', $stripped, $m)) {
            $key = $m[1];
            $value = $m[2];
            if ($value === '|') {
                $blockKey = $key;
                $blockIndent = 4;
                $blockLines = [];
            } else {
                $items[$currentIndex][$key] = parseYamlValue($value);
            }
            $i++;
            continue;
        }

        $i++;
    }

    $flushBlock();
    return $items;
}

function extractTests(string $content): array
{
    $tests = [];
    if (preg_match_all('/<test>([\s\S]*?)<\/test>/', $content, $matches)) {
        foreach ($matches[1] as $yamlContent) {
            $parsed = parseSimpleYaml(trim($yamlContent));
            foreach ($parsed as $item) {
                $tests[] = $item;
            }
        }
    }
    return $tests;
}

// Canonical host registered functions used by test/Functions-Custom.lor to
// verify the custom function contract via the PUBLIC API: each receives
// (Interpreter, array $args) where $args is a native PHP array.
$customTestFunctions = [
    'custom_echo' => fn ($interp, $args) => implode(',', array_map('lorStr', $args)),
    'custom_arg_count' => fn ($interp, $args) => count($args),
    'custom_set_state' => fn ($interp, $args) => $interp->setStateField($args[0], $args[1]),
    'custom_get_state' => fn ($interp, $args) => $interp->getStateField($args[0]),
];

// -- Test runner --------------------------------------------------------------

/**
 * Run a single test case.
 * Returns [passed(bool), actual(string), expected(string), error(?string)].
 */
function runTest(string $filePath, string $content, array $testItem, bool $crlf): array
{
    global $customTestFunctions, $handleFile;

    $content = str_replace("\r\n", "\n", $content);
    if ($crlf) {
        $content = str_replace("\n", "\r\n", $content);
    }

    $choices = $testItem['choices'] ?? [];
    if (!is_array($choices)) {
        $choices = [];
    }
    $beatName = $testItem['beat'] ?? null;
    $saveAtChoice = saveIndices($testItem['saveAtChoice'] ?? null);
    $saveAtDialogue = saveIndices($testItem['saveAtDialogue'] ?? null);
    $expected = $testItem['expected'];

    $output = '';
    $choiceCount = 0;
    $dialogueCount = 0;
    // Set after a save: the event re-presented by the restore is not counted,
    // so that save indices refer to the events of an uninterrupted run
    $replayingDialogue = false;
    $replayingChoice = false;
    $parsedScript = null;
    $result = null;

    try {
        $earlyScript = Loreline::parse($content, $filePath, $handleFile);
    } catch (\Throwable $e) {
        return [false, $output, $expected, $e->getMessage()];
    }

    $translations = null;
    $translationVal = $testItem['translation'] ?? null;
    if ($translationVal && $earlyScript !== null) {
        $translations = Loreline::loadLocale($translationVal, $earlyScript, $filePath, $handleFile);
    }

    $restoreInput = null;
    if (!empty($testItem['restoreFile'])) {
        $restorePath = dirname($filePath) . DIRECTORY_SEPARATOR . $testItem['restoreFile'];
        $restoreInput = file_get_contents($restorePath);
        $restoreInput = str_replace("\r\n", "\n", $restoreInput);
        if ($crlf) {
            $restoreInput = str_replace("\n", "\r\n", $restoreInput);
        }
    }

    $options = [
        'functions' => $customTestFunctions,
        'translations' => $translations,
    ];

    $onDialogue = null;
    $onChoice = null;
    $onFinish = null;
    $resume = null;

    $onFinish = function ($interp) use (&$output, $expected, &$result): void {
        $cmp = compareOutput($expected, $output);
        $result = [$cmp === -1, $output, $expected, null];
    };

    $resume = function ($script, $saveData) use (&$onDialogue, &$onChoice, &$onFinish, $options): void {
        Loreline::resume($script, $onDialogue, $onChoice, $onFinish, $saveData, null, $options);
    };

    $onDialogue = function ($interp, $character, $text, $tags, $advance) use (
        &$output, &$dialogueCount, &$replayingDialogue, &$result, &$parsedScript, &$resume,
        $saveAtDialogue, $restoreInput, $filePath, $expected, $handleFile
    ): void {
        $multiline = str_contains($text, "\n");
        $tags ??= [];
        if ($character !== null) {
            $charName = $interp->getCharacterField($character, 'name');
            if ($charName === null) {
                $charName = $character;
            }
            $taggedText = insertTagsInText($text, $tags, $multiline);
            if ($multiline) {
                $output .= $charName . ":\n  " . $taggedText . "\n\n";
            } else {
                $output .= $charName . ': ' . $taggedText . "\n\n";
            }
        } else {
            $taggedText = insertTagsInText($text, $tags, $multiline);
            $output .= '~ ' . $taggedText . "\n\n";
        }

        if ($replayingDialogue) {
            $replayingDialogue = false;
            $advance();
            return;
        }

        if (in_array($dialogueCount, $saveAtDialogue, true)) {
            $dialogueCount++;
            $replayingDialogue = true;
            $saveData = $interp->save();

            if ($restoreInput !== null) {
                $restoreScript = Loreline::parse($restoreInput, $filePath, $handleFile);
                if ($restoreScript !== null) {
                    $resume($restoreScript, $saveData);
                } else {
                    $result = [false, $output, $expected, 'Error parsing restoreInput script'];
                }
            } else {
                $resume($parsedScript, $saveData);
            }
            return;
        }

        $dialogueCount++;
        $advance();
    };

    $onChoice = function ($interp, $choiceOptions, $select) use (
        &$output, &$choiceCount, &$replayingChoice, &$choices, &$result, &$parsedScript, &$resume, &$onFinish,
        $saveAtChoice, $restoreInput, $filePath, $expected, $handleFile
    ): void {
        foreach ($choiceOptions as $opt) {
            $prefix = $opt->enabled ? '+' : '-';
            $multiline = str_contains($opt->text, "\n");
            $taggedText = insertTagsInText($opt->text, $opt->tags, $multiline);
            $output .= $prefix . ' ' . $taggedText . "\n";
        }
        $output .= "\n";

        // The re-presented choice is not counted
        $replayed = $replayingChoice;
        if ($replayingChoice) {
            $replayingChoice = false;
        } elseif (in_array($choiceCount, $saveAtChoice, true)) {
            $choiceCount++;
            $replayingChoice = true;
            $saveData = $interp->save();

            if ($restoreInput !== null) {
                $restoreScript = Loreline::parse($restoreInput, $filePath, $handleFile);
                if ($restoreScript !== null) {
                    $resume($restoreScript, $saveData);
                } else {
                    $result = [false, $output, $expected, 'Error parsing restoreInput script'];
                }
            } else {
                $resume($parsedScript, $saveData);
            }
            return;
        }

        if (!$replayed) {
            $choiceCount++;
        }

        if (count($choices) === 0) {
            $onFinish($interp);
        } else {
            $index = array_shift($choices);
            $select($index);
        }
    };

    try {
        $script = $earlyScript;
        if ($script !== null) {
            $parsedScript = $script;
            Loreline::play($script, $onDialogue, $onChoice, $onFinish, $beatName, $options);
        } else {
            $result = [false, $output, $expected, 'Error parsing script'];
        }
    } catch (\Throwable $e) {
        $result = [false, $output, $expected, $e->getMessage()];
    }

    if ($result === null) {
        $result = [false, $output, $expected, 'Test did not produce a result'];
    }

    return $result;
}

function printDiff(string $expected, string $actual): void
{
    $expectedLines = explode("\n", trim(str_replace("\r\n", "\n", $expected)));
    $actualLines = explode("\n", trim(str_replace("\r\n", "\n", $actual)));
    $minLen = min(count($expectedLines), count($actualLines));

    for ($i = 0; $i < $minLen; $i++) {
        if ($expectedLines[$i] !== $actualLines[$i]) {
            echo '  > Unexpected output at line ' . ($i + 1) . "\n";
            echo '  >  got: ' . $actualLines[$i] . "\n";
            echo '  > need: ' . $expectedLines[$i] . "\n";
            return;
        }
    }
    if ($minLen < max(count($expectedLines), count($actualLines))) {
        echo '  > Unexpected output at line ' . ($minLen + 1) . "\n";
        if ($minLen < count($actualLines)) {
            echo '  >  got: ' . $actualLines[$minLen] . "\n";
            echo "  > need: (empty)\n";
        } else {
            echo "  >  got: (empty)\n";
            echo '  > need: ' . $expectedLines[$minLen] . "\n";
        }
    }
}

// -- Main ---------------------------------------------------------------------

// Child interpreters: same scenario in every binding runner. A child spawned from the
// root shares its state, gets host functions bound to itself, and both playheads are
// saved from any interpreter then continued after a restore with resumeSpawn().
const SPAWN_SCRIPT = "state\n"
    . "  gold: 0\n"
    . "\n"
    . "beat Main\n"
    . "  gold = gold + 1\n"
    . "\n"
    . "  Main gold \$gold\n"
    . "\n"
    . "  Main where \$current_beat() host \$who()\n"
    . "\n"
    . "beat Side\n"
    . "  new state\n"
    . "    local: 5\n"
    . "\n"
    . "  gold = gold + 10\n"
    . "\n"
    . "  Side gold \$gold local \$local\n"
    . "\n"
    . "  Side where \$current_beat() host \$who()\n";

const SPAWN_EXPECTED = [
    'root: Main gold 1',
    'npc: Side gold 11 local 5',
    'root: Main where Main host root',
    'root: Main where Main host root',
    'npc: Side gold 11 local 5',
    'npc: Side where Side host npc',
];

function runSpawnTest(): void
{
    global $passCount, $failCount;
    $label = 'spawn: shared state, bound functions, save and resumeSpawn';
    try {
        $log = [];
        $pending = [];
        $nameOf = fn ($interp) => $interp->key() ?? 'root';
        $dialogue = function ($interp, $character, $text, $tags, $advance) use (&$log, &$pending, $nameOf): void {
            $log[] = $nameOf($interp) . ': ' . ($character !== null ? $character . ': ' : '') . $text;
            $pending[$nameOf($interp)] = $advance;
        };
        $choice = function ($interp, $options, $select): void {};
        $finish = function ($interp): void {};
        $next = function (string $name) use (&$pending): void {
            if (!isset($pending[$name])) {
                throw new \Exception("No pending dialogue for $name");
            }
            $cb = $pending[$name];
            unset($pending[$name]);
            $cb();
        };
        $options = ['functions' => ['who' => fn ($interp, $args) => $nameOf($interp)]];

        $script = Loreline::parse(SPAWN_SCRIPT);
        $root = Loreline::play($script, $dialogue, $choice, $finish, null, $options);
        $npc = $root->spawn('npc', $dialogue, $choice, $finish);
        $npc->start('Side');
        $next('root');

        $checks = [];
        if ($npc->key() !== 'npc') $checks[] = 'child key: ' . var_export($npc->key(), true);
        if ($root->key() !== null) $checks[] = 'root key: ' . var_export($root->key(), true);
        if ($npc->isRoot() || !$root->isRoot()) $checks[] = 'isRoot';
        $saveData = $npc->save();
        if ($saveData !== $root->save()) $checks[] = 'save from child differs from save from root';

        $pending = [];
        $restored = Loreline::resume($script, $dialogue, $choice, $finish, $saveData, null, $options);
        $keys = $restored->resumableSpawnKeys();
        if ($keys !== ['npc']) $checks[] = 'resumableSpawnKeys: ' . implode(',', $keys);
        $restored->resumeSpawn('npc', $dialogue, $choice, $finish)->resume();
        $next('npc');

        if ($log !== SPAWN_EXPECTED) {
            $checks[] = "log:\n    " . implode("\n    ", $log);
        }
        if (count($checks) > 0) {
            throw new \Exception(implode('; ', $checks));
        }

        $passCount++;
        echo "\033[1m\033[32mPASS\033[0m - \033[90m$label\033[0m\n";
    } catch (\Throwable $e) {
        $failCount++;
        echo "\033[1m\033[31mFAIL\033[0m - \033[90m$label\033[0m\n";
        echo "  Error: " . $e->getMessage() . "\n";
    }
}

// The random generator is saved, and seedRandom() reseeds it from the host: same
// scenario in every binding runner. After a restore at the first line, reseeding with
// the seed of the script makes the second line draw what the first one drew.
const RANDOM_SCRIPT = [
    'beat Main',
    '  seed_random(7)',
    '  First $random(1, 1000000000)',
    '',
    '  Second $random(1, 1000000000)',
    '',
];

function runSeedRandomTest(): void
{
    global $passCount, $failCount;
    $label = 'random: seedRandom after restore';
    try {
        $log = [];
        $pending = null;
        $dialogue = function ($interp, $character, $text, $tags, $advance) use (&$log, &$pending): void {
            $log[] = $text;
            $pending = $advance;
        };
        $choice = function ($interp, $options, $select): void {};
        $finish = function ($interp): void {};

        $script = Loreline::parse(implode("\n", RANDOM_SCRIPT));
        $root = Loreline::play($script, $dialogue, $choice, $finish);
        $saveData = $root->save();

        $restored = Loreline::resume($script, $dialogue, $choice, $finish, $saveData);
        $restored->seedRandom(7);
        $pending();

        $first = explode(' ', $log[0])[1];
        $second = isset($log[2]) ? explode(' ', $log[2])[1] : '';
        if ($second !== $first) {
            throw new \Exception("expected $first after reseeding, got " . implode(' / ', $log));
        }

        $passCount++;
        echo "\033[1m\033[32mPASS\033[0m - \033[90m$label\033[0m\n";
    } catch (\Throwable $e) {
        $failCount++;
        echo "\033[1m\033[31mFAIL\033[0m - \033[90m$label\033[0m\n";
        echo "  Error: " . $e->getMessage() . "\n";
    }
}

// The strategy of a when block can be a host function: it receives one record per
// rule and returns the index of the rule to play. Same scenario in every binding runner.
const WHEN_STRATEGY_SCRIPT = [
    'state',
    '  ready: true',
    '',
    'beat Start',
    '  when chooser',
    '    ready',
    '      Zero.',
    '    not ready',
    '      One.',
    '    always',
    '      Two.',
    '  End.',
    '',
];

function runWhenStrategyTest(): void
{
    global $passCount, $failCount;
    $label = 'when: host strategy';
    try {
        $summary = null;
        $log = [];
        $chooser = function ($interp, $args) use (&$summary) {
            $parts = [];
            $last = -1;
            foreach ($args[0] as $record) {
                $index = (int) $record['index'];
                $eligible = (bool) $record['eligible'];
                $parts[] = $index . ':' . ($eligible ? 'true' : 'false');
                if ($eligible) $last = $index;
            }
            $summary = implode(' ', $parts);
            return $last;
        };
        $dialogue = function ($interp, $character, $text, $tags, $advance) use (&$log): void {
            $log[] = $text;
            $advance();
        };
        $script = Loreline::parse(implode("\n", WHEN_STRATEGY_SCRIPT));
        Loreline::play($script, $dialogue, function ($i, $o, $s): void {}, function ($i): void {}, null, ['functions' => ['chooser' => $chooser]]);
        if ($summary !== '0:true 1:false 2:true' || implode(',', $log) !== 'Two.,End.') {
            throw new \Exception('records ' . var_export($summary, true) . ', log ' . implode(',', $log));
        }

        $passCount++;
        echo "\033[1m\033[32mPASS\033[0m - \033[90m$label\033[0m\n";
    } catch (\Throwable $e) {
        $failCount++;
        echo "\033[1m\033[31mFAIL\033[0m - \033[90m$label\033[0m\n";
        echo "  Error: " . $e->getMessage() . "\n";
    }
}

// A saveAtChoice / saveAtDialogue value: absent, one index, or a list of indices
function saveIndices(mixed $raw): array
{
    if ($raw === null) {
        return [];
    }
    if (is_int($raw)) {
        return [$raw];
    }
    if (is_array($raw) && count(array_filter($raw, 'is_int')) === count($raw)) {
        return array_values($raw);
    }
    throw new \Exception('Invalid save indices: ' . var_export($raw, true));
}

function main(): void
{
    global $argv, $passCount, $failCount, $fileCount, $fileFailCount, $handleFile;

    if (count($argv) < 2) {
        fwrite(STDERR, "Usage: php php/test-runner.php <test-directory>\n");
        exit(1);
    }

    $testDir = $argv[1];

    // Test fixtures exercise every supported translation format.
    Loreline::translationFormat('po', true);
    Loreline::translationFormat('xliff', true);
    Loreline::translationFormat('csv', true);

    $testFiles = collectTestFiles($testDir);

    if (count($testFiles) === 0) {
        fwrite(STDERR, "No test files found in $testDir\n");
        exit(1);
    }

    foreach ($testFiles as $filePath) {
        $rawContent = file_get_contents($filePath);

        $testItems = extractTests($rawContent);
        if (count($testItems) === 0) {
            continue;
        }

        $fileCount++;
        $failBefore = $failCount;

        foreach ($testItems as $item) {
            foreach ([false, true] as $crlf) {
                $modeLabel = $crlf ? 'CRLF' : 'LF';
                $choicesLabel = '';
                if (!empty($item['choices'])) {
                    $choicesLabel = ' ~ [' . implode(',', $item['choices']) . ']';
                }
                $label = "$filePath ~ $modeLabel$choicesLabel";

                [$passed, $actual, $expected, $error] = runTest($filePath, $rawContent, $item, $crlf);

                if ($passed) {
                    $passCount++;
                    echo "\033[1m\033[32mPASS\033[0m - \033[90m$label\033[0m\n";
                } else {
                    $failCount++;
                    echo "\033[1m\033[31mFAIL\033[0m - \033[90m$label\033[0m\n";
                    if ($error !== null) {
                        echo "  Error: $error\n";
                    }
                    printDiff($expected, $actual);
                }
            }
        }

        // Roundtrip tests for each mode
        foreach ([false, true] as $crlf) {
            $modeLabel = $crlf ? 'CRLF' : 'LF';
            $label = "$filePath ~ $modeLabel ~ roundtrip";
            $newline = $crlf ? "\r\n" : "\n";

            try {
                $content = str_replace("\r\n", "\n", $rawContent);
                if ($crlf) {
                    $content = str_replace("\n", "\r\n", $content);
                }

                $script1 = Loreline::parse($content, $filePath, $handleFile);
                if ($script1 === null) {
                    $failCount++;
                    echo "\033[1m\033[31mFAIL\033[0m - \033[90m$label\033[0m\n";
                    echo "  Error: Failed to parse original script\n";
                    continue;
                }

                // Structural check: print -> parse -> print must be stable
                $print1 = Loreline::print($script1, '  ', $newline);
                $script2 = Loreline::parse($print1, $filePath, $handleFile);
                if ($script2 === null) {
                    $failCount++;
                    echo "\033[1m\033[31mFAIL\033[0m - \033[90m$label\033[0m\n";
                    echo "  Error: Failed to parse printed script\n";
                    continue;
                }
                $print2 = Loreline::print($script2, '  ', $newline);

                if ($print1 !== $print2) {
                    $failCount++;
                    echo "\033[1m\033[31mFAIL\033[0m - \033[90m$label\033[0m\n";
                    $lines1 = explode("\n", str_replace("\r\n", "\n", $print1));
                    $lines2 = explode("\n", str_replace("\r\n", "\n", $print2));
                    $ml = min(count($lines1), count($lines2));
                    for ($i = 0; $i < $ml; $i++) {
                        if ($lines1[$i] !== $lines2[$i]) {
                            echo '  > Printer output not idempotent at line ' . ($i + 1) . "\n";
                            echo '  >  print1: ' . $lines1[$i] . "\n";
                            echo '  >  print2: ' . $lines2[$i] . "\n";
                            break;
                        }
                    }
                    if (count($lines1) !== count($lines2)) {
                        echo '  > Line count differs: print1=' . count($lines1) . ', print2=' . count($lines2) . "\n";
                    }
                    continue;
                }

                // Behavioral check: run each test item on the printed content
                $allPassed = true;
                $firstError = null;
                $firstExpected = null;
                $firstActual = null;

                foreach ($testItems as $item) {
                    [$passed, $actual, $expectedStr, $error] = runTest($filePath, $print1, $item, $crlf);
                    if (!$passed) {
                        $allPassed = false;
                        if ($firstError === null) {
                            $firstError = $error ?? '';
                            $firstExpected = $expectedStr;
                            $firstActual = $actual;
                        }
                    }
                }

                if ($allPassed) {
                    $passCount++;
                    echo "\033[1m\033[32mPASS\033[0m - \033[90m$label\033[0m\n";
                } else {
                    $failCount++;
                    echo "\033[1m\033[31mFAIL\033[0m - \033[90m$label\033[0m\n";
                    if ($firstError !== null && $firstError !== '') {
                        echo "  Error: $firstError\n";
                    }
                    if ($firstExpected !== null && $firstActual !== null) {
                        printDiff($firstExpected, $firstActual);
                    }
                }
            } catch (\Throwable $e) {
                $failCount++;
                echo "\033[1m\033[31mFAIL\033[0m - \033[90m$label\033[0m\n";
                echo '  Error: ' . $e->getMessage() . "\n";
            }
        }

        // JSON roundtrip test
        foreach ([false, true] as $crlf) {
            $modeLabel = $crlf ? 'CRLF' : 'LF';
            $jsonLabel = "$filePath ~ $modeLabel ~ json-roundtrip";
            try {
                $content = str_replace("\r\n", "\n", $rawContent);
                if ($crlf) {
                    $content = str_replace("\n", "\r\n", $content);
                }
                $script = Loreline::parse($content, $filePath, $handleFile);
                if ($script === null) {
                    $failCount++;
                    echo "\033[1m\033[31mFAIL\033[0m - \033[90m$jsonLabel\033[0m\n";
                    echo "  Error: Failed to parse script\n";
                } else {
                    $json1 = $script->toJson();
                    $script2 = Script::fromJson($json1);
                    $json2 = $script2->toJson();

                    if ($json1 === $json2) {
                        $passCount++;
                        echo "\033[1m\033[32mPASS\033[0m - \033[90m$jsonLabel\033[0m\n";
                    } else {
                        $failCount++;
                        echo "\033[1m\033[31mFAIL\033[0m - \033[90m$jsonLabel\033[0m\n";
                        echo "  > JSON mismatch after roundtrip\n";
                    }
                }
            } catch (\Throwable $e) {
                $failCount++;
                echo "\033[1m\033[31mFAIL\033[0m - \033[90m$jsonLabel\033[0m\n";
                echo '  Error: ' . $e->getMessage() . "\n";
            }
        }

        if ($failCount > $failBefore) {
            $fileFailCount++;
        }
    }

    runSpawnTest();
    runSeedRandomTest();
    runWhenStrategyTest();

    $total = $passCount + $failCount;
    echo "\n";
    if ($failCount === 0) {
        echo "\033[1m\033[32m  All $total tests passed ($fileCount files)\033[0m\n";
    } else {
        echo "\033[1m\033[31m  $failCount of $total tests failed ($fileFailCount of $fileCount files)\033[0m\n";
        exit(1);
    }
}

main();
