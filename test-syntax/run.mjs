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
// Writes an HTML report to build/syntax-test/index.html: every file rendered like
// with the Loreline themes, decorations and line wrapping, scopes on
// hover, failing lines marked. The decorations come from haxe/SyntaxDecorations.hx,
// built against the current sources with ./haxe.

import { createHighlighter } from 'shiki';
import oneDarkTheme from './themes/one-dark-theme.js';
import githubLightTheme from './themes/github-light-theme.js';
import fs from 'node:fs';
import path from 'node:path';
import { execFile, execFileSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.dirname(here);
const grammarPath = path.join(root, 'language', 'loreline.tmLanguage.json');
const reportDir = path.join(root, 'build', 'syntax-test');

const args = process.argv.slice(2);
const openReport = args.includes('--open');
const filters = args.filter(a => !a.startsWith('--'));

const ASSERTION = /^\/\/\s*(\^|<-)/;

const DARK = oneDarkTheme.name;
const LIGHT = githubLightTheme.name;

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
        theme: DARK,
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

// Hanging indent for wrapped lines: each line's content after its indentation
// goes in a `.lw` box, so a wrapped line continues under its own text instead
// of the left edge.
const INDENT_RE = /^ */;

function hastText(node) {
    if (node.type === 'text') return node.value;
    return (node.children || []).map(hastText).join('');
}

function splitHastAt(nodes, offset) {
    const before = [], after = [];
    let remaining = offset;
    for (const node of nodes) {
        if (remaining <= 0) { after.push(node); continue; }
        const len = hastText(node).length;
        if (len <= remaining) { before.push(node); remaining -= len; continue; }
        if (node.type === 'text') {
            before.push({ ...node, value: node.value.slice(0, remaining) });
            after.push({ ...node, value: node.value.slice(remaining) });
        }
        else {
            const [b, a] = splitHastAt(node.children || [], remaining);
            before.push({ ...node, children: b });
            after.push({ ...node, children: a });
        }
        remaining = 0;
    }
    return [before, after];
}

function wrapLineIndent(node) {
    const text = hastText(node);
    const indent = text.match(INDENT_RE)[0].length;
    if (indent === text.length) return;
    const [before, after] = splitHastAt(node.children, indent);
    node.children = [...before, {
        type: 'element',
        tagName: 'span',
        properties: { class: 'lw', style: `--indent:${indent}` },
        children: after
    }];
}

function forEachLine(node, fn) {
    for (const child of node.children || []) {
        if (child.type !== 'element') continue;
        const cls = child.properties?.class;
        const names = Array.isArray(cls) ? cls : String(cls || '').split(/\s+/);
        if (names.includes('line')) fn(child);
        else forEachLine(child, fn);
    }
}

// In `pre`, which runs after Shiki's decorations are placed: reshaping lines
// earlier makes decorations fail to resolve their offsets.
const wrapIndentTransformer = {
    name: 'loreline-wrap-indent',
    pre(node) {
        node.properties.class = ((node.properties.class || '') + ' lor-wrap').trim();
        forEachLine(node, wrapLineIndent);
    }
};

/**
 * Decorations drawn over the grammar (text, choices, plural pipes...), computed by
 * haxe/SyntaxDecorations.hx built against the current sources. Null if it can't
 * be built: the report then only shows the grammar coloring.
 */
function loadDecorations() {
    const out = path.join(reportDir, 'syntax-decorations.cjs');
    const haxe = path.join(root, process.platform === 'win32' ? 'haxe.cmd' : 'haxe');
    try {
        fs.mkdirSync(reportDir, { recursive: true });
        execFileSync(haxe, [
            '-cp', path.join(root, 'src'),
            '-cp', path.join(here, 'haxe'),
            '--main', 'SyntaxDecorations',
            '--js', out,
            '-D', 'js-es=6',
            '-D', 'loreline_use_js_types',
            '-D', 'loreline_node_id_class'
        ], { cwd: root, stdio: 'pipe' });
        return createRequire(import.meta.url)(out).SyntaxDecorations;
    }
    catch (e) {
        console.log(`\x1b[33m  Decorations disabled, SyntaxDecorations could not be built: ${String(e.stderr ?? e.message).trim()}\x1b[0m`);
        return null;
    }
}

function decorationsOf(helper, code) {
    if (helper == null) return [];
    try {
        return helper.getDecorations(code).map(d => ({
            start: d.offset,
            end: d.offset + d.length,
            properties: { class: 'lor-' + d.kind }
        }));
    }
    catch (e) {
        return [];
    }
}

function renderReport(highlighter, helper, results) {
    const passed = results.filter(r => r.failures.length === 0 && r.parseErrors.length === 0).length;
    const sections = results.map(result => {
        const name = path.basename(result.file);
        const failingLines = new Set(result.failures.map(f => f.assertion.codeIndex + 1));
        const code = result.code.map(l => l.text).join('\n');
        const html = highlighter.codeToHtml(code, {
            lang: 'loreline',
            themes: { dark: DARK, light: LIGHT },
            defaultColor: 'dark',
            includeExplanation: true,
            decorations: decorationsOf(helper, code),
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
            }, wrapIndentTransformer]
        });
        const parseErrors = result.parseErrors.map(e =>
            `<li><b>${escapeHtml(name)}:${e.line}</b>, column ${e.column}: not valid Loreline: ${escapeHtml(e.message)}</li>`
        ).join('');
        const failing = result.failures.length > 0 || result.parseErrors.length > 0;
        const failures = parseErrors + result.failures.map(f =>
            `<li><b>${escapeHtml(name)}:${f.assertion.sourceLine}</b>, column ${f.column}: ${escapeHtml(f.problem)}` +
            `<pre>${escapeHtml(f.codeLine.text)}\n${escapeHtml(f.assertion.text)}</pre>` +
            `actual: <code>${escapeHtml(f.actual.join(' ') || '(no scope)')}</code></li>`
        ).join('');
        return `<section class="${failing ? 'fail' : 'pass'}">
<h2>${failing ? 'FAIL' : 'PASS'} ${escapeHtml(name)} <small>${result.assertions.length} assertions</small></h2>
${failures ? `<ul>${failures}</ul>` : ''}
${html}
</section>`;
    }).join('\n');

    return `<!doctype html>
<html data-theme="dark">
<head>
<meta charset="utf-8">
<title>Loreline syntax tests</title>
<script>
  // Theme of the system, unless one was picked with the buttons
  let theme = null;
  try { theme = localStorage.getItem('syntax-test-theme'); } catch (e) {}
  if (theme !== 'light' && theme !== 'dark') theme = matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark';
  document.documentElement.dataset.theme = theme;
  function setTheme(value) {
    document.documentElement.dataset.theme = value;
    try { localStorage.setItem('syntax-test-theme', value); } catch (e) {}
  }
</script>
<style>
  body { font-family: -apple-system, system-ui, sans-serif; margin: 24px; background: #181818; color: #dddddd; }
  [data-theme="light"] body { background: #ffffff; color: #24292e; }
  html[data-theme="dark"] { color-scheme: dark; }
  html[data-theme="light"] { color-scheme: light; }
  h1 { font-size: 20px; }
  h2 { font-size: 15px; margin: 28px 0 8px; }
  h2 small { font-weight: normal; opacity: .6; }
  section.fail h2 { color: #ff7b72; }
  section.pass h2 { color: #3fb950; }
  [data-theme="light"] section.fail h2 { color: #cf222e; }
  [data-theme="light"] section.pass h2 { color: #1a7f37; }
  .themes { float: right; }
  .themes button { font: inherit; font-size: 13px; padding: 3px 10px; border-radius: 4px; border: 1px solid rgba(127, 127, 127, .4); background: transparent; color: inherit; cursor: pointer; }
  [data-theme="dark"] .themes .dark, [data-theme="light"] .themes .light { background: rgba(127, 127, 127, .25); }
  ul { font-size: 13px; }
  ul pre { margin: 4px 0; }

  /* Code blocks */
  pre.shiki { padding: 12px 0; border: 1px solid rgba(127, 127, 127, .25); border-radius: 6px; font-size: 13px; line-height: 1.5; font-variant-ligatures: none; }
  /* Line numbers stay plain even when a decoration covers the whole line */
  pre.shiki .line::before { content: attr(data-line); display: inline-block; width: 3.5em; padding-right: 1em; text-align: right; font-style: normal; color: #6e7681 !important; background: none !important; }
  pre.shiki .line.failing { background: rgba(207, 34, 46, .2); }
  pre.shiki span[title]:hover { outline: 1px solid rgba(127, 127, 127, .6); }
  [data-theme="light"] .shiki { color: var(--shiki-light) !important; background-color: #ffffff !important; }
  [data-theme="light"] .shiki span { color: var(--shiki-light) !important; }

  /* Wrapped lines */
  :root { --lor-wrap-indent: 1ch; }
  .shiki.lor-wrap code { white-space: pre-wrap; }
  .shiki.lor-wrap .lw {
    display: inline-block;
    vertical-align: top;
    white-space: pre-wrap;
    box-sizing: border-box;
    max-width: calc(100% - 4.5em - var(--indent, 0) * 1ch);
    padding-left: var(--lor-wrap-indent, 0);
    text-indent: calc(var(--lor-wrap-indent, 0) * -1);
  }

  /* Loreline code decorations */
  .lor-choice-option { background: rgba(255, 255, 255, 0.06); border-radius: 4px; padding: 1px 0; }
  [data-theme="light"] .shiki .lor-choice-option { background-color: rgba(0, 0, 0, 0.03) !important; }
  .lor-choice-text, .lor-choice-text span { color: rgba(255, 255, 255, 0.84) !important; }
  [data-theme="light"] .shiki .lor-choice-text, [data-theme="light"] .shiki .lor-choice-text span { color: rgba(0, 0, 0, 0.84) !important; }
  .lor-text-statement { font-style: italic; }
  .lor-text-content, .lor-text-content span { color: #59bec3 !important; }
  [data-theme="light"] .shiki .lor-text-content, [data-theme="light"] .shiki .lor-text-content span { color: #0b7285 !important; }
  .lor-plural-pipe, .lor-plural-pipe span { color: #dcdcaa !important; }
  [data-theme="light"] .shiki .lor-plural-pipe, [data-theme="light"] .shiki .lor-plural-pipe span { color: #986801 !important; }
  .lor-text-content .lor-plural-pipe, .lor-text-content .lor-plural-pipe span,
  .lor-choice-text .lor-plural-pipe, .lor-choice-text .lor-plural-pipe span { color: #dcdcaa !important; }
  [data-theme="light"] .shiki .lor-text-content .lor-plural-pipe, [data-theme="light"] .shiki .lor-text-content .lor-plural-pipe span,
  [data-theme="light"] .shiki .lor-choice-text .lor-plural-pipe, [data-theme="light"] .shiki .lor-choice-text .lor-plural-pipe span { color: #986801 !important; }
  .shiki .lor-choice-once-style { font-style: italic; }
  .shiki .lor-choice-once-prefix { color: rgba(255, 255, 255, 0.4) !important; }
  [data-theme="light"] .shiki .lor-choice-once-prefix { color: rgba(0, 0, 0, 0.4) !important; }
  .lor-when-rule { background: rgba(255, 255, 255, 0.06); border-radius: 4px; padding: 1px 0; }
  [data-theme="light"] .shiki .lor-when-rule { background-color: rgba(0, 0, 0, 0.03) !important; }
  .shiki .lor-when-once-style { font-style: italic; }
  .shiki .lor-when-once-prefix { color: rgba(255, 255, 255, 0.4) !important; }
  [data-theme="light"] .shiki .lor-when-once-prefix { color: rgba(0, 0, 0, 0.4) !important; }
</style>
</head>
<body>
<div class="themes"><button class="dark" onclick="setTheme('dark')">Dark</button> <button class="light" onclick="setTheme('light')">Light</button></div>
<h1>Loreline syntax tests: ${passed} of ${results.length} files pass</h1>
${sections}
</body>
</html>
`;
}

const grammar = JSON.parse(fs.readFileSync(grammarPath, 'utf8'));
const highlighter = await createHighlighter({
    themes: [oneDarkTheme, githubLightTheme],
    langs: [{ ...grammar, name: 'loreline' }]
});

const files = fs.readdirSync(here)
    .filter(f => f.endsWith('.lor'))
    .filter(f => filters.length === 0 || filters.some(filter => f.includes(filter)))
    .sort()
    .map(f => path.join(here, f));

const helper = loadDecorations();

/**
 * Parser errors of a test file, on the lines of the file. Empty when the helper
 * can't be built.
 */
function parseErrorsOf(result) {
    if (helper == null) return [];
    const source = result.code.map(l => l.text).join('\n');
    return helper.getErrors(source).map(e => ({
        message: e.message,
        line: result.code[e.line - 1]?.sourceLine ?? e.line,
        column: e.column
    }));
}

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
    result.parseErrors = result.error ? [] : parseErrorsOf(result);
    results.push(result);
    assertionCount += result.assertions.length;
    const name = path.basename(file);
    if (result.error || result.failures.length > 0 || result.parseErrors.length > 0) {
        failed++;
        console.log(`\x1b[1m\x1b[31mFAIL\x1b[0m - \x1b[90m${name}\x1b[0m`);
        if (result.error) console.log(`  ${result.error}`);
        for (const e of result.parseErrors) {
            console.log(`  > ${name}:${e.line}, column ${e.column}: not valid Loreline: ${e.message}`);
        }
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
fs.writeFileSync(reportPath, renderReport(highlighter, helper, results.filter(r => !r.error)));

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
