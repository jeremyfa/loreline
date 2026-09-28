import type { Interpreter, Script, Node, TextTag, ChoiceOption, InterpreterOptions, DialogueHandler, ChoiceHandler, FinishHandler, ImportsFileHandler, Translations } from './loreline.js';
import { readFileSync, readdirSync, statSync } from 'fs';
import { join, dirname } from 'path';
import { parse as parseYaml } from 'yaml';

const useMin = process.argv.includes('--min');
const lorelinePath = useMin ? './loreline.min.js' : './loreline.js';
const lorelineModule = await import(lorelinePath);
const { Loreline } = lorelineModule;
const ScriptClass = lorelineModule.Script as { fromJson(json: any): Script };
const NodeClass = lorelineModule.Node as { fromJson(json: any): Node };

if (useMin) {
    console.log(`Using minified build: ${lorelinePath}\n`);
}

// Get test directory from command line args
const testDir: string = process.argv.filter(a => a !== '--min')[2];
if (!testDir) {
    console.error('Usage: npx tsx js/test-runner.ts <test-directory> [--min]');
    process.exit(1);
}

let passCount: number = 0;
let failCount: number = 0;
let fileCount: number = 0;
let fileFailCount: number = 0;

interface TestItem {
    choices?: number[];
    beat?: string;
    saveAtChoice?: number | number[];
    saveAtDialogue?: number | number[];
    expected: string;
    translation?: string;
    restoreFile?: string;
}

interface TestResult {
    passed: boolean;
    actual: string;
    expected: string;
    error?: string;
}

// Collect all .lor test files (skip imports/, modified/ subdirs and translation files like .fr.lor)
function collectTestFiles(dir: string): string[] {
    const files: string[] = [];
    for (const entry of readdirSync(dir)) {
        const fullPath: string = join(dir, entry);
        if (statSync(fullPath).isDirectory()) {
            if (entry !== 'imports' && entry !== 'modified') {
                files.push(...collectTestFiles(fullPath));
            }
        } else if (entry.endsWith('.lor') && !entry.match(/\.\w{2}\.lor$/)) {
            files.push(fullPath);
        }
    }
    return files.sort();
}

// File handler for imports
const handleFile: ImportsFileHandler = (path: string, callback: (data: string) => void): void => {
    try {
        const content: string = readFileSync(path, 'utf-8');
        callback(content);
    } catch (e) {
        callback(null as unknown as string);
    }
};

// Insert tags into text (replicates TestRunner.insertTagsInText)
function insertTagsInText(text: string, tags: TextTag[], multiline: boolean): string {
    const offsetsWithTags: Set<number> = new Set();
    for (const tag of tags) {
        offsetsWithTags.add(tag.offset);
    }

    const chars: string[] = [...text];
    const len: number = chars.length;
    let result: string = '';

    for (let i = 0; i < len; i++) {
        if (offsetsWithTags.has(i)) {
            for (const tag of tags) {
                if (tag.offset === i) {
                    result += '<<';
                    if (tag.closing) result += '/';
                    result += tag.value;
                    result += '>>';
                }
            }
        }
        const c: string = chars[i];
        if (multiline && c === '\n') {
            result += '\n  ';
        } else {
            result += c;
        }
    }

    // Tags at end of text
    for (const tag of tags) {
        if (tag.offset >= len) {
            result += '<<';
            if (tag.closing) result += '/';
            result += tag.value;
            result += '>>';
        }
    }

    return result.trimEnd();
}

// Compare output, return -1 if match, or line index of first difference
function compareOutput(expected: string, actual: string): number {
    const expectedLines: string[] = expected.replace(/\r\n/g, '\n').trim().split('\n');
    const actualLines: string[] = actual.replace(/\r\n/g, '\n').trim().split('\n');
    const minLen: number = Math.min(expectedLines.length, actualLines.length);
    const maxLen: number = Math.max(expectedLines.length, actualLines.length);

    for (let i = 0; i < minLen; i++) {
        if (expectedLines[i] !== actualLines[i]) return i;
    }
    if (minLen < maxLen) return minLen;
    return -1;
}

// Canonical host-registered functions used by test/Functions-Custom.lor to verify
// the custom-function contract: each receives (interpreter, args), where args is an
// array and the interpreter can read/write runtime state.
const customTestFunctions = {
    custom_echo: (_interp: Interpreter, args: any[]): string => args.join(','),
    custom_arg_count: (_interp: Interpreter, args: any[]): number => args.length,
    custom_set_state: (interp: Interpreter, args: any[]): null => { interp.setStateField(args[0], args[1]); return null; },
    custom_get_state: (interp: Interpreter, args: any[]): any => interp.getStateField(args[0]),
};

// Run a single test case
function runTest(filePath: string, content: string, testItem: TestItem, crlf: boolean): Promise<TestResult> {
    return new Promise((resolve: (result: TestResult) => void) => {
        // Normalize line endings
        if (crlf) {
            content = content.replace(/\r\n/g, '\n').replace(/\n/g, '\r\n');
        } else {
            content = content.replace(/\r\n/g, '\n');
        }

        const choices: number[] | null = testItem.choices ? [...testItem.choices] : null;
        const beatName: string | undefined = testItem.beat || undefined;
        const saveAtChoice: number[] = saveIndices(testItem.saveAtChoice);
        const saveAtDialogue: number[] = saveIndices(testItem.saveAtDialogue);
        const expected: string = testItem.expected;
        let output: string = '';
        let choiceCount: number = 0;
        let dialogueCount: number = 0;
        // Set after a save: the event re-presented by the restore is not counted,
        // so that save indices refer to the events of an uninterrupted run
        let replayingDialogue: boolean = false;
        let replayingChoice: boolean = false;
        let parsedScript: Script | null = null;

        // Translations are built after parsing the main script so that
        // loadLocale can walk the import tree and merge per-file `.<locale>.lor`
        // siblings. See the parse block below.
        let options: InterpreterOptions = { functions: customTestFunctions };

        // Load restoreFile content if specified
        let restoreInput: string | null = null;
        if (testItem.restoreFile) {
            const restorePath: string = join(dirname(filePath), testItem.restoreFile);
            restoreInput = readFileSync(restorePath, 'utf-8');
            if (crlf) {
                restoreInput = restoreInput.replace(/\r\n/g, '\n').replace(/\n/g, '\r\n');
            } else {
                restoreInput = restoreInput.replace(/\r\n/g, '\n');
            }
        }

        const handleFinish: FinishHandler = (_interpreter: Interpreter): void => {
            const result: number = compareOutput(expected, output);
            resolve({ passed: result === -1, actual: output, expected });
        };

        const handleDialogue: DialogueHandler = (_interpreter: Interpreter, character: string | null, text: string, tags: TextTag[], callback: () => void): void => {
            const multiline: boolean = text.includes('\n');
            if (character != null) {
                const charName: string = _interpreter.getCharacterField(character, 'name') ?? character;
                const taggedText: string = insertTagsInText(text, tags, multiline);
                if (multiline) {
                    output += charName + ':\n  ' + taggedText + '\n\n';
                } else {
                    output += charName + ': ' + taggedText + '\n\n';
                }
            } else {
                const taggedText: string = insertTagsInText(text, tags, multiline);
                output += '~ ' + taggedText + '\n\n';
            }

            if (replayingDialogue) {
                replayingDialogue = false;
                callback();
                return;
            }

            // Save/restore test at dialogue
            if (saveAtDialogue.includes(dialogueCount)) {
                dialogueCount++;
                replayingDialogue = true;
                // Through JSON, like a host storing the save
                const saveData = JSON.parse(JSON.stringify(_interpreter.save()));

                if (restoreInput != null) {
                    const restoreScript: Script | null = Loreline.parse(restoreInput, filePath, handleFile);
                    if (restoreScript) {
                        Loreline.resume(restoreScript, handleDialogue, handleChoice, handleFinish, saveData, undefined, options);
                    } else {
                        resolve({ passed: false, actual: output, expected, error: 'Error parsing restoreInput script' });
                    }
                } else {
                    Loreline.resume(parsedScript!, handleDialogue, handleChoice, handleFinish, saveData, undefined, options);
                }
                return;
            }

            dialogueCount++;
            callback();
        };

        const handleChoice: ChoiceHandler = (_interpreter: Interpreter, choiceOptions: ChoiceOption[], callback: (index: number) => void): void => {
            for (const opt of choiceOptions) {
                const prefix: string = opt.enabled ? '+' : '-';
                const multiline: boolean = opt.text.includes('\n');
                const taggedText: string = insertTagsInText(opt.text, opt.tags, multiline);
                output += prefix + ' ' + taggedText + '\n';
            }
            output += '\n';

            // Save/restore test (the re-presented choice is not counted)
            const replayed: boolean = replayingChoice;
            if (replayingChoice) {
                replayingChoice = false;
            } else if (saveAtChoice.includes(choiceCount)) {
                choiceCount++;
                replayingChoice = true;
                const saveData = JSON.parse(JSON.stringify(_interpreter.save()));

                if (restoreInput != null) {
                    const restoreScript: Script | null = Loreline.parse(restoreInput, filePath, handleFile);
                    if (restoreScript) {
                        Loreline.resume(restoreScript, handleDialogue, handleChoice, handleFinish, saveData, undefined, options);
                    } else {
                        resolve({ passed: false, actual: output, expected, error: 'Error parsing restoreInput script' });
                    }
                } else {
                    Loreline.resume(parsedScript!, handleDialogue, handleChoice, handleFinish, saveData, undefined, options);
                }
                return;
            }

            if (!replayed) {
                choiceCount++;
            }

            if (!choices || choices.length === 0) {
                handleFinish(_interpreter);
            } else {
                const index: number = choices.shift()!;
                callback(index);
            }
        };

        try {
            const script: Script | null = Loreline.parse(content, filePath, handleFile);
            if (!script) {
                resolve({ passed: false, actual: output, expected, error: 'Error parsing script' });
                return;
            }
            parsedScript = script;

            if (testItem.translation) {
                const lang: string = testItem.translation;
                const translations: Translations | null = Loreline.loadLocale(lang, script, filePath, handleFile);
                if (translations) {
                    options = { functions: customTestFunctions, translations };
                }
            }

            Loreline.play(script, handleDialogue, handleChoice, handleFinish, beatName, options);
        } catch (e) {
            resolve({ passed: false, actual: output, expected, error: (e as Error).toString() });
        }
    });
}

// Reads a saveAtChoice / saveAtDialogue value: absent, one index, or a list of indices
function saveIndices(raw: unknown): number[] {
    if (raw == null) return [];
    if (typeof raw === 'number') return [raw];
    if (Array.isArray(raw) && raw.every(v => typeof v === 'number')) return raw as number[];
    throw new Error('Invalid save indices: ' + JSON.stringify(raw));
}

// Extract test items from a .lor file
function extractTests(content: string): TestItem[] {
    const tests: TestItem[] = [];
    const regex: RegExp = /<test>([\s\S]*?)<\/test>/g;
    let match: RegExpExecArray | null;
    while ((match = regex.exec(content)) !== null) {
        const yamlContent: string = match[1].trim();
        const parsed: unknown = parseYaml(yamlContent);
        if (Array.isArray(parsed)) {
            tests.push(...(parsed as TestItem[]));
        }
    }
    return tests;
}

// Main
async function main(): Promise<void> {
    const testFiles: string[] = collectTestFiles(testDir);

    if (testFiles.length === 0) {
        console.error('No test files found in', testDir);
        process.exit(1);
    }

    // Test fixtures exercise every supported translation format.
    Loreline.translationFormat('po', true);
    Loreline.translationFormat('xliff', true);
    Loreline.translationFormat('csv', true);

    for (const filePath of testFiles) {
        const rawContent: string = readFileSync(filePath, 'utf-8');
        const testItems: TestItem[] = extractTests(rawContent);

        if (testItems.length === 0) continue;

        fileCount++;
        const failBefore: number = failCount;

        for (const item of testItems) {
            for (const crlf of [false, true]) {
                const modeLabel: string = crlf ? 'CRLF' : 'LF';
                const choicesLabel: string = item.choices ? ` ~ [${item.choices.join(',')}]` : '';
                const label: string = `${filePath} ~ ${modeLabel}${choicesLabel}`;

                const result: TestResult = await runTest(filePath, rawContent, item, crlf);

                if (result.passed) {
                    passCount++;
                    console.log(`\x1b[1m\x1b[32mPASS\x1b[0m - \x1b[90m${label}\x1b[0m`);
                } else {
                    failCount++;
                    console.log(`\x1b[1m\x1b[31mFAIL\x1b[0m - \x1b[90m${label}\x1b[0m`);
                    if (result.error) {
                        console.log(`  Error: ${result.error}`);
                    }

                    // Show diff
                    const expectedLines: string[] = result.expected.replace(/\r\n/g, '\n').trim().split('\n');
                    const actualLines: string[] = result.actual.replace(/\r\n/g, '\n').trim().split('\n');
                    const minLen: number = Math.min(expectedLines.length, actualLines.length);

                    for (let i = 0; i < minLen; i++) {
                        if (expectedLines[i] !== actualLines[i]) {
                            console.log(`  > Unexpected output at line ${i + 1}`);
                            console.log(`  >  got: ${actualLines[i]}`);
                            console.log(`  > need: ${expectedLines[i]}`);
                            break;
                        }
                    }
                    if (minLen < Math.max(expectedLines.length, actualLines.length)) {
                        if (minLen < actualLines.length) {
                            console.log(`  > Unexpected output at line ${minLen + 1}`);
                            console.log(`  >  got: ${actualLines[minLen]}`);
                            console.log(`  > need: (empty)`);
                        } else {
                            console.log(`  > Unexpected output at line ${minLen + 1}`);
                            console.log(`  >  got: (empty)`);
                            console.log(`  > need: ${expectedLines[minLen]}`);
                        }
                    }
                }
            }
        }

        // Roundtrip tests for each mode (LF, CRLF)
        for (const crlf of [false, true]) {
            const modeLabel: string = crlf ? 'CRLF' : 'LF';
            const label: string = `${filePath} ~ ${modeLabel} ~ roundtrip`;
            const newline: string = crlf ? '\r\n' : '\n';

            try {
                // Normalize content for this mode
                let content: string = rawContent.replace(/\r\n/g, '\n');
                if (crlf) {
                    content = content.replace(/\n/g, '\r\n');
                }

                // Parse original
                const script1: Script | null = Loreline.parse(content, filePath, handleFile);
                if (!script1) {
                    failCount++;
                    console.log(`\x1b[1m\x1b[31mFAIL\x1b[0m - \x1b[90m${label}\x1b[0m`);
                    console.log(`  Error: Failed to parse original script`);
                    continue;
                }

                // Structural check: print -> parse -> print must be stable
                const print1: string = Loreline.print(script1, '  ', newline);
                const script2: Script | null = Loreline.parse(print1, filePath, handleFile);
                if (!script2) {
                    failCount++;
                    console.log(`\x1b[1m\x1b[31mFAIL\x1b[0m - \x1b[90m${label}\x1b[0m`);
                    console.log(`  Error: Failed to parse printed script`);
                    continue;
                }
                const print2: string = Loreline.print(script2, '  ', newline);

                if (print1 !== print2) {
                    failCount++;
                    console.log(`\x1b[1m\x1b[31mFAIL\x1b[0m - \x1b[90m${label}\x1b[0m`);
                    const lines1: string[] = print1.replace(/\r\n/g, '\n').split('\n');
                    const lines2: string[] = print2.replace(/\r\n/g, '\n').split('\n');
                    const ml: number = Math.min(lines1.length, lines2.length);
                    for (let i = 0; i < ml; i++) {
                        if (lines1[i] !== lines2[i]) {
                            console.log(`  > Printer output not idempotent at line ${i + 1}`);
                            console.log(`  >  print1: ${lines1[i]}`);
                            console.log(`  >  print2: ${lines2[i]}`);
                            break;
                        }
                    }
                    if (lines1.length !== lines2.length) {
                        console.log(`  > Line count differs: print1=${lines1.length}, print2=${lines2.length}`);
                    }
                    continue;
                }

                // Behavioral check: run each test item on the printed content
                let allPassed: boolean = true;
                let firstError: string | undefined;
                let firstExpected: string | undefined;
                let firstActual: string | undefined;

                for (const item of testItems) {
                    const result: TestResult = await runTest(filePath, print1, item, crlf);
                    if (!result.passed) {
                        allPassed = false;
                        if (!firstError) {
                            firstError = result.error;
                            firstExpected = result.expected;
                            firstActual = result.actual;
                        }
                    }
                }

                if (allPassed) {
                    passCount++;
                    console.log(`\x1b[1m\x1b[32mPASS\x1b[0m - \x1b[90m${label}\x1b[0m`);
                } else {
                    failCount++;
                    console.log(`\x1b[1m\x1b[31mFAIL\x1b[0m - \x1b[90m${label}\x1b[0m`);
                    if (firstError) {
                        console.log(`  Error: ${firstError}`);
                    }
                    if (firstExpected && firstActual) {
                        const el: string[] = firstExpected.replace(/\r\n/g, '\n').trim().split('\n');
                        const al: string[] = firstActual.replace(/\r\n/g, '\n').trim().split('\n');
                        const ml: number = Math.min(el.length, al.length);
                        for (let i = 0; i < ml; i++) {
                            if (el[i] !== al[i]) {
                                console.log(`  > Unexpected output at line ${i + 1}`);
                                console.log(`  >  got: ${al[i]}`);
                                console.log(`  > need: ${el[i]}`);
                                break;
                            }
                        }
                    }
                }
            } catch (e) {
                failCount++;
                console.log(`\x1b[1m\x1b[31mFAIL\x1b[0m - \x1b[90m${label}\x1b[0m`);
                console.log(`  Error: ${(e as Error).toString()}`);
            }
        }

        // JSON roundtrip test
        for (const crlf of [false, true]) {
            const modeLabel: string = crlf ? 'CRLF' : 'LF';
            const label: string = `${filePath} ~ ${modeLabel} ~ json-roundtrip`;
            try {
                let content: string = rawContent.replace(/\r\n/g, '\n');
                if (crlf) content = content.replace(/\n/g, '\r\n');
                const script: Script | null = Loreline.parse(content, filePath, handleFile);
                if (!script) {
                    failCount++;
                    console.log(`\x1b[1m\x1b[31mFAIL\x1b[0m - \x1b[90m${label}\x1b[0m`);
                    console.log(`  Error: Failed to parse script`);
                } else {
                    const json1: string = JSON.stringify(script.toJson());
                    const script2: Script = ScriptClass.fromJson(JSON.parse(json1));
                    const json2: string = JSON.stringify(script2.toJson());

                    if (json1 === json2) {
                        passCount++;
                        console.log(`\x1b[1m\x1b[32mPASS\x1b[0m - \x1b[90m${label}\x1b[0m`);
                    } else {
                        failCount++;
                        console.log(`\x1b[1m\x1b[31mFAIL\x1b[0m - \x1b[90m${label}\x1b[0m`);
                        console.log(`  > JSON mismatch after roundtrip`);
                    }
                }
            } catch (e) {
                failCount++;
                console.log(`\x1b[1m\x1b[31mFAIL\x1b[0m - \x1b[90m${label}\x1b[0m`);
                console.log(`  Error: ${(e as Error).toString()}`);
            }
        }

        if (failCount > failBefore) fileFailCount++;
    }

    runSpawnTest();
    runCustomFieldsTest();
    runSeedRandomTest();

    const total: number = passCount + failCount;
    console.log('');
    if (failCount === 0) {
        console.log(`\x1b[1m\x1b[32m  All ${total} tests passed (${fileCount} files)\x1b[0m`);
    } else {
        console.log(`\x1b[1m\x1b[31m  ${failCount} of ${total} tests failed (${fileFailCount} of ${fileCount} files)\x1b[0m`);
        process.exit(1);
    }
}

// Child interpreters: same scenario in every binding runner. A child spawned from the
// root shares its state, gets host functions bound to itself, and both playheads are
// saved from any interpreter then continued after a restore with resumeSpawn().
const SPAWN_SCRIPT = [
    'state',
    '  gold: 0',
    '',
    'beat Main',
    '  gold = gold + 1',
    '',
    '  Main gold $gold',
    '',
    '  Main where $current_beat() host $who()',
    '',
    'beat Side',
    '  new state',
    '    local: 5',
    '',
    '  gold = gold + 10',
    '',
    '  Side gold $gold local $local',
    '',
    '  Side where $current_beat() host $who()',
    ''
].join('\n');

const SPAWN_EXPECTED = [
    'root: Main gold 1',
    'npc: Side gold 11 local 5',
    'root: Main where Main host root',
    'root: Main where Main host root',
    'npc: Side gold 11 local 5',
    'npc: Side where Side host npc'
];

function runSpawnTest(): void {
    const label = 'spawn: shared state, bound functions, save and resumeSpawn';
    try {
        const log: string[] = [];
        const pending = new Map<string, () => void>();
        const nameOf = (interp: Interpreter): string => interp.key ?? 'root';
        const dialogue: DialogueHandler = (interp, character, text, _tags, callback) => {
            log.push(`${nameOf(interp)}: ${character != null ? character + ': ' : ''}${text}`);
            pending.set(nameOf(interp), callback);
        };
        const choice: ChoiceHandler = () => {};
        const finish: FinishHandler = () => {};
        const next = (name: string): void => {
            const cb = pending.get(name);
            if (!cb) throw new Error(`No pending dialogue for ${name}`);
            pending.delete(name);
            cb();
        };
        const options: InterpreterOptions = {
            functions: { who: (interp: Interpreter, _args: any[]) => nameOf(interp) }
        };

        const script: Script = Loreline.parse(SPAWN_SCRIPT);
        const root: Interpreter = Loreline.play(script, dialogue, choice, finish, null, options);
        const npc = root.spawn('npc', dialogue, choice, finish);
        npc.start('Side');
        next('root');

        const checks: string[] = [];
        if (npc.key !== 'npc') checks.push(`child key: ${npc.key}`);
        if (root.key != null) checks.push(`root key: ${root.key}`);
        if (npc.isRoot() || !root.isRoot()) checks.push('isRoot');
        const fromChild = JSON.stringify(npc.save());
        if (fromChild !== JSON.stringify(root.save())) checks.push('save from child differs from save from root');

        pending.clear();
        const restored: Interpreter = Loreline.resume(script, dialogue, choice, finish, JSON.parse(fromChild), null, options);
        const keys = restored.resumableSpawnKeys();
        if (keys.join(',') !== 'npc') checks.push(`resumableSpawnKeys: ${keys.join(',')}`);
        restored.resumeSpawn('npc', dialogue, choice, finish).resume();
        next('npc');

        if (log.join('\n') !== SPAWN_EXPECTED.join('\n')) {
            checks.push('log:\n    ' + log.join('\n    '));
        }
        if (checks.length > 0) throw new Error(checks.join('; '));

        passCount++;
        console.log(`\x1b[1m\x1b[32mPASS\x1b[0m - \x1b[90m${label}\x1b[0m`);
    } catch (e) {
        failCount++;
        console.log(`\x1b[1m\x1b[31mFAIL\x1b[0m - \x1b[90m${label}\x1b[0m`);
        console.log(`  Error: ${(e as Error).toString()}`);
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
    ''
].join('\n');

function runSeedRandomTest(): void {
    const label = 'random: seedRandom after restore';
    try {
        const log: string[] = [];
        let pending: (() => void) | null = null;
        const dialogue: DialogueHandler = (_interp, _character, text, _tags, callback) => {
            log.push(text);
            pending = callback;
        };
        const script: Script = Loreline.parse(RANDOM_SCRIPT);
        const root: Interpreter = Loreline.play(script, dialogue, () => {}, () => {});
        const saved = JSON.stringify(root.save());

        const restored: Interpreter = Loreline.resume(script, dialogue, () => {}, () => {}, JSON.parse(saved));
        restored.seedRandom(7);
        pending!();

        const first = log[0].split(' ')[1];
        const second = log.length > 2 ? log[2].split(' ')[1] : '';
        if (second !== first) throw new Error(`expected ${first} after reseeding, got ${log.join(' / ')}`);

        passCount++;
        console.log(`\x1b[1m\x1b[32mPASS\x1b[0m - \x1b[90m${label}\x1b[0m`);
    } catch (e) {
        failCount++;
        console.log(`\x1b[1m\x1b[31mFAIL\x1b[0m - \x1b[90m${label}\x1b[0m`);
        console.log(`  Error: ${(e as Error).toString()}`);
    }
}

// The customCreateFields option: every fields object comes from the host factory,
// which receives the interpreter asking for it.
function runCustomFieldsTest(): void {
    const label = 'custom fields: factory used for state and characters';
    try {
        const script: Script = Loreline.parse([
            'character bob',
            '  name: Bob',
            '',
            'beat Main',
            '  bob.mood = "happy"',
            '',
            '  Hello',
            ''
        ].join('\n'));
        const created: any[] = [];
        const options: InterpreterOptions = {
            customCreateFields: (interp: Interpreter, type: string, node: Node) => {
                const fields = { __custom: true };
                created.push(interp);
                return fields;
            }
        };
        const root: Interpreter = Loreline.play(script, (_i, _c, _t, _tags, cb) => cb(), () => {}, () => {}, null, options);
        const bob = root.getCharacter('bob');
        const checks: string[] = [];
        if (!bob || bob.__custom !== true) checks.push('character bob not created by the factory');
        if (root.getCharacterField('bob', 'mood') !== 'happy') checks.push('bob.mood not written through the factory object');
        if (created.length === 0 || created.indexOf(root) === -1) checks.push('factory not called with the interpreter');
        if (checks.length > 0) throw new Error(checks.join('; '));

        passCount++;
        console.log(`\x1b[1m\x1b[32mPASS\x1b[0m - \x1b[90m${label}\x1b[0m`);
    } catch (e) {
        failCount++;
        console.log(`\x1b[1m\x1b[31mFAIL\x1b[0m - \x1b[90m${label}\x1b[0m`);
        console.log(`  Error: ${(e as Error).toString()}`);
    }
}

main();
