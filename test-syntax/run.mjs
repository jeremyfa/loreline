#!/usr/bin/env node

// Syntax coloring tests for language/loreline.tmLanguage.json, run with Shiki
// (the same Oniguruma engine as VS Code).
//
// Each .lor file of this folder holds Loreline code followed by assertion lines,
// in the style of vscode-tmgrammar-test:
//
//       Tell me if it is true.
//     //^^^^^^^^^^^^^^^^^^^^^^ string.unquoted
//     //          ^^ - keyword.control
//
// - An assertion line starts with `//` at column 0, then `^` markers under the
//   tested columns of the closest code line above it.
// - `// <---` tests the first columns instead (as many as there are `-`), which
//   the `//` itself hides.
// - Each scope after the markers must be in the scope stack of every tested
//   column. A scope matches by prefix: `string.unquoted` matches
//   `string.unquoted.dialogue.loreline`.
// - `- scope` means the scope must not be there.
//
// Assertion lines are taken out before tokenizing, so they can't change the
// coloring they check. Other comments are part of the code.
//
// Usage: node test-syntax/run.mjs [--open] [name filter...]
// Writes an HTML report to build/syntax-test/index.html: every file as Shiki
// renders it (light and dark), scopes on hover, failing lines marked.

import { createHighlighter } from 'shiki';
import fs from 'node:fs';
import path from 'node:path';
import { execFile } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.dirname(here);
const grammarPath = path.join(root, 'language', 'loreline.tmLanguage.json');
const reportDir = path.join(root, 'build', 'syntax-test');

const args = process.argv.slice(2);
const openReport = args.includes('--open');
const filters = args.filter(a => !a.startsWith('--'));

const ASSERTION = /^\/\/\s*(\^|<-)/;

/**
 * Splits a test file into the code to tokenize and its assertions.
 */
function parseTestFile(source) {
    const lines = source.replace(/\r\n/g, '\n').split('\n');
    const code = [];
    const assertions = [];
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        if (!ASSERTION.test(line)) {
            code.push({ text: line, sourceLine: i + 1 });
            continue;
        }
        if (code.length === 0) {
            throw new Error(`line ${i + 1}: assertion without a code line above it`);
        }
        let columns = [];
        let rest;
        const arrow = line.match(/^\/\/\s*<(-+)(.*)$/);
        if (arrow) {
            columns = Array.from({ length: arrow[1].length }, (_, c) => c);
            rest = arrow[2];
        }
        else {
            let c = 2;
            while (c < line.length && (line[c] === '^' || line[c] === ' ')) {
                if (line[c] === '^') columns.push(c);
                c++;
            }
            rest = line.slice(c);
        }
        rest = rest.trim();
        const negative = rest.startsWith('- ');
        const scopes = (negative ? rest.slice(2) : rest).trim().split(/\s+/).filter(s => s.length > 0);
        if (scopes.length === 0) {
            throw new Error(`line ${i + 1}: assertion without any scope`);
        }
        assertions.push({ codeIndex: code.length - 1, columns, scopes, negative, sourceLine: i + 1, text: line });
    }
    return { code, assertions };
}

/**
 * Scope stack of every column of every line, without the root scope.
 */
function scopesByColumn(highlighter, code) {
    const lines = highlighter.codeToTokensBase(code.map(l => l.text).join('\n'), {
        lang: 'loreline',
        theme: 'github-light',
        includeExplanation: true
    });
    return lines.map(tokens => {
        const columns = [];
        for (const token of tokens) {
            for (const part of token.explanation ?? []) {
                const scopes = part.scopes.map(s => s.scopeName).filter(s => s !== 'source.loreline');
                for (let k = 0; k < part.content.length; k++) columns.push(scopes);
            }
        }
        return columns;
    });
}

function hasScope(stack, expected) {
    return stack.some(s => s === expected || s.startsWith(expected + '.'));
}

function checkFile(highlighter, file) {
    const { code, assertions } = parseTestFile(fs.readFileSync(file, 'utf8'));
    const columns = scopesByColumn(highlighter, code);
    const failures = [];
    for (const assertion of assertions) {
        const line = code[assertion.codeIndex];
        const lineScopes = columns[assertion.codeIndex] ?? [];
        for (const c of assertion.columns) {
            const stack = lineScopes[c];
            let problem = null;
            if (stack === undefined) {
                problem = 'column is past the end of the line';
            }
            else {
                for (const scope of assertion.scopes) {
                    if (hasScope(stack, scope) === assertion.negative) {
                        problem = assertion.negative ? `has ${scope}` : `lacks ${scope}`;
                        break;
                    }
                }
            }
            if (problem != null) {
                failures.push({
                    assertion,
                    codeLine: line,
                    column: c,
                    problem,
                    actual: stack ?? []
                });
                // One failure per assertion is enough to point at it
                break;
            }
        }
    }
    return { file, code, assertions, failures };
}

function escapeHtml(s) {
    return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function renderReport(highlighter, results) {
    const passed = results.filter(r => r.failures.length === 0).length;
    const sections = results.map(result => {
        const name = path.basename(result.file);
        const failingLines = new Set(result.failures.map(f => f.assertion.codeIndex + 1));
        const html = highlighter.codeToHtml(result.code.map(l => l.text).join('\n'), {
            lang: 'loreline',
            themes: { light: 'github-light', dark: 'github-dark' },
            includeExplanation: true,
            transformers: [{
                line(node, line) {
                    node.properties['data-line'] = String(result.code[line - 1]?.sourceLine ?? line);
                    if (failingLines.has(line)) this.addClassToHast(node, 'failing');
                },
                span(node, line, col, lineElement, token) {
                    node.properties.title = (token.explanation ?? [])
                        .map(e => JSON.stringify(e.content) + '  ' + e.scopes.map(s => s.scopeName).filter(s => s !== 'source.loreline').join(' '))
                        .join('\n');
                }
            }]
        });
        const failures = result.failures.map(f =>
            `<li><b>${escapeHtml(name)}:${f.assertion.sourceLine}</b>, column ${f.column}: ${escapeHtml(f.problem)}` +
            `<pre>${escapeHtml(f.codeLine.text)}\n${escapeHtml(f.assertion.text)}</pre>` +
            `actual: <code>${escapeHtml(f.actual.join(' ') || '(no scope)')}</code></li>`
        ).join('');
        return `<section class="${result.failures.length ? 'fail' : 'pass'}">
<h2>${result.failures.length ? 'FAIL' : 'PASS'} ${escapeHtml(name)} <small>${result.assertions.length} assertions</small></h2>
${failures ? `<ul>${failures}</ul>` : ''}
${html}
</section>`;
    }).join('\n');

    return `<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>Loreline syntax tests</title>
<style>
  :root { color-scheme: light dark; }
  body { font-family: -apple-system, system-ui, sans-serif; margin: 24px; background: #fff; color: #24292e; }
  h1 { font-size: 20px; }
  h2 { font-size: 15px; margin: 28px 0 8px; }
  h2 small { font-weight: normal; opacity: .6; }
  section.fail h2 { color: #cf222e; }
  section.pass h2 { color: #1a7f37; }
  ul { font-size: 13px; }
  ul pre { margin: 4px 0; }
  pre.shiki { padding: 12px 0; border: 1px solid rgba(127, 127, 127, .25); border-radius: 6px; font-size: 13px; line-height: 1.5; overflow-x: auto; }
  pre.shiki .line { display: inline-block; min-width: 100%; }
  pre.shiki .line::before { content: attr(data-line); display: inline-block; width: 3.5em; padding-right: 1em; text-align: right; opacity: .35; }
  pre.shiki .line.failing { background: rgba(207, 34, 46, .15); }
  pre.shiki span[title]:hover { outline: 1px solid rgba(127, 127, 127, .6); }
  @media (prefers-color-scheme: dark) {
    body { background: #0d1117; color: #e6edf3; }
    .shiki, .shiki span { color: var(--shiki-dark) !important; background-color: var(--shiki-dark-bg) !important; }
    section.fail h2 { color: #ff7b72; }
    section.pass h2 { color: #3fb950; }
  }
</style>
</head>
<body>
<h1>Loreline syntax tests: ${passed} of ${results.length} files pass</h1>
<p>Hover a token to see its scopes. Line numbers are those of the test file.</p>
${sections}
</body>
</html>
`;
}

const grammar = JSON.parse(fs.readFileSync(grammarPath, 'utf8'));
const highlighter = await createHighlighter({
    themes: ['github-light', 'github-dark'],
    langs: [{ ...grammar, name: 'loreline' }]
});

const files = fs.readdirSync(here)
    .filter(f => f.endsWith('.lor'))
    .filter(f => filters.length === 0 || filters.some(filter => f.includes(filter)))
    .sort()
    .map(f => path.join(here, f));

const results = [];
let assertionCount = 0;
let failed = 0;
for (const file of files) {
    let result;
    try {
        result = checkFile(highlighter, file);
    }
    catch (e) {
        result = { file, code: [], assertions: [], failures: [], error: e.message };
    }
    results.push(result);
    assertionCount += result.assertions.length;
    const name = path.basename(file);
    if (result.error || result.failures.length > 0) {
        failed++;
        console.log(`\x1b[1m\x1b[31mFAIL\x1b[0m - \x1b[90m${name}\x1b[0m`);
        if (result.error) console.log(`  ${result.error}`);
        for (const f of result.failures) {
            console.log(`  > ${name}:${f.assertion.sourceLine}, column ${f.column}: ${f.problem}`);
            console.log(`    ${f.codeLine.text}`);
            console.log(`    ${f.assertion.text}`);
            console.log(`    actual: ${f.actual.join(' ') || '(no scope)'}`);
        }
    }
    else {
        console.log(`\x1b[1m\x1b[32mPASS\x1b[0m - \x1b[90m${name} (${result.assertions.length} assertions)\x1b[0m`);
    }
}

fs.mkdirSync(reportDir, { recursive: true });
const reportPath = path.join(reportDir, 'index.html');
fs.writeFileSync(reportPath, renderReport(highlighter, results.filter(r => !r.error)));

console.log('');
console.log(`\x1b[90m  Report: ${path.relative(process.cwd(), reportPath)}\x1b[0m`);
if (failed === 0) {
    console.log(`\x1b[1m\x1b[32m  All ${files.length} syntax test files passed (${assertionCount} assertions)\x1b[0m`);
}
else {
    console.log(`\x1b[1m\x1b[31m  ${failed} of ${files.length} syntax test files failed\x1b[0m`);
}

if (openReport) {
    execFile(process.platform === 'darwin' ? 'open' : process.platform === 'win32' ? 'explorer' : 'xdg-open', [reportPath]);
}
process.exitCode = failed === 0 ? 0 : 1;
