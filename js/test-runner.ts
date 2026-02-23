import type { Interpreter, Script, TextTag, ChoiceOption, InterpreterOptions, DialogueHandler, ChoiceHandler, FinishHandler, ImportsFileHandler, Translations } from './loreline.js';
import { readFileSync, readdirSync, statSync } from 'fs';
import { join, dirname } from 'path';
import { parse as parseYaml } from 'yaml';

const useMin = process.argv.includes('--min');
const lorelinePath = useMin ? './loreline.min.js' : './loreline.js';
const { Loreline } = await import(lorelinePath);

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

interface TestItem {
    choices?: number[];
    beat?: string;
    saveAtChoice?: number;
    saveAtDialogue?: number;
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
        const saveAtChoice: number = testItem.saveAtChoice != null ? testItem.saveAtChoice : -1;
        const saveAtDialogue: number = testItem.saveAtDialogue != null ? testItem.saveAtDialogue : -1;
        const expected: string = testItem.expected;
        let output: string = '';
        let choiceCount: number = 0;
        let dialogueCount: number = 0;
        let parsedScript: Script | null = null;

        // Build options
        let options: InterpreterOptions | undefined = undefined;
        if (testItem.translation) {
            const lang: string = testItem.translation;
            const basePath: string = filePath.substring(0, filePath.length - 4);
            const translationPath: string = basePath + '.' + lang + '.lor';
            let translationContent: string = readFileSync(translationPath, 'utf-8');
            if (crlf) {
                translationContent = translationContent.replace(/\r\n/g, '\n').replace(/\n/g, '\r\n');
            } else {
                translationContent = translationContent.replace(/\r\n/g, '\n');
            }
            const translationScript: Script | null = Loreline.parse(translationContent, translationPath, handleFile);
            if (translationScript) {
                const translations: Translations = Loreline.extractTranslations(translationScript);
                options = { translations };
            }
        }

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

            // Save/restore test at dialogue
            if (saveAtDialogue >= 0 && dialogueCount === saveAtDialogue) {
                dialogueCount++;
                const saveData = _interpreter.save();

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

            // Save/restore test
            if (saveAtChoice >= 0 && choiceCount === saveAtChoice) {
                choiceCount++;
                const saveData = _interpreter.save();

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

            choiceCount++;

            if (!choices || choices.length === 0) {
                handleFinish(_interpreter);
            } else {
                const index: number = choices.shift()!;
                callback(index);
            }
        };

        try {
            const script: Script | null = Loreline.parse(content, filePath, handleFile);
            if (script) {
                parsedScript = script;
                Loreline.play(script, handleDialogue, handleChoice, handleFinish, beatName, options);
            } else {
                resolve({ passed: false, actual: output, expected, error: 'Error parsing script' });
            }
        } catch (e) {
            resolve({ passed: false, actual: output, expected, error: (e as Error).toString() });
        }
    });
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

    for (const filePath of testFiles) {
        const rawContent: string = readFileSync(filePath, 'utf-8');
        const testItems: TestItem[] = extractTests(rawContent);

        if (testItems.length === 0) continue;

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

                // Structural check: print → parse → print must be stable
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
    }

    const total: number = passCount + failCount;
    console.log('');
    if (failCount === 0) {
        console.log(`\x1b[1m\x1b[32m  All ${total} tests passed\x1b[0m`);
    } else {
        console.log(`\x1b[1m\x1b[31m  ${failCount} of ${total} tests failed\x1b[0m`);
        process.exit(1);
    }
}

main();
