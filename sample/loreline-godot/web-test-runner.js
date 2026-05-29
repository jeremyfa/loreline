#!/usr/bin/env node
//
// Run a Godot web export in headless Chromium and wait for required console
// markers. Used by CI and by local Mac/Linux developers to validate the
// Loreline WASM + JS-bridge code path of the Godot integration.
//
// Usage:
//   node web-test-runner.js --url <url> --markers "M1|M2|..." [--timeout 60000]
//
// Exit code: 0 if every marker appeared (and no "TEST FAILED:" line) before
// the timeout, 1 otherwise.
//
// Requires `playwright` to be installed in the working directory and the
// Chromium browser to be available (`npx playwright install chromium`).

'use strict';

function parseArgs(argv) {
    const args = {};
    for (let i = 0; i < argv.length; i++) {
        const a = argv[i];
        if (a.startsWith('--')) {
            const key = a.slice(2);
            const next = argv[i + 1];
            if (next === undefined || next.startsWith('--')) {
                args[key] = true;
            } else {
                args[key] = next;
                i++;
            }
        }
    }
    return args;
}

async function main() {
    const args = parseArgs(process.argv.slice(2));

    if (!args.url || !args.markers) {
        console.error('usage: web-test-runner.js --url <url> --markers "M1|M2|..." [--timeout ms]');
        process.exit(2);
    }

    const url = args.url;
    const markers = String(args.markers).split('|').map(s => s.trim()).filter(Boolean);
    const timeoutMs = parseInt(args.timeout || '60000', 10);

    let playwright;
    try {
        playwright = require('playwright');
    } catch (e) {
        console.error('error: playwright module not found. Run `npm install playwright && npx playwright install chromium` in this directory.');
        process.exit(2);
    }

    console.log(`==> url: ${url}`);
    console.log(`==> markers: ${markers.join(', ')}`);
    console.log(`==> timeout: ${timeoutMs}ms`);
    console.log();

    const browser = await playwright.chromium.launch({ headless: true });
    const context = await browser.newContext();
    const page = await context.newPage();

    let testFailed = null;
    const seen = new Set();
    const transcript = [];

    let resolveDone;
    const done = new Promise(r => { resolveDone = r; });

    const handleText = (label, text) => {
        transcript.push(`[${label}] ${text}`);
        process.stdout.write(`[${label}] ${text}\n`);

        if (text.includes('TEST FAILED:')) {
            testFailed = text;
            resolveDone();
            return;
        }
        for (const m of markers) {
            if (!seen.has(m) && text.includes(m)) {
                seen.add(m);
            }
        }
        if (seen.size === markers.length) {
            resolveDone();
        }
    };

    page.on('console', msg => handleText(msg.type(), msg.text()));
    page.on('pageerror', err => handleText('pageerror', String(err)));

    const timer = setTimeout(() => resolveDone('timeout'), timeoutMs);

    try {
        await page.goto(url, { waitUntil: 'load' });
    } catch (e) {
        clearTimeout(timer);
        await browser.close();
        console.error(`FAIL: navigation error: ${e.message}`);
        process.exit(1);
    }

    const result = await done;
    clearTimeout(timer);
    await browser.close();

    console.log();
    if (testFailed) {
        console.error(`FAIL: page reported "${testFailed}"`);
        process.exit(1);
    }
    if (result === 'timeout') {
        const missing = markers.filter(m => !seen.has(m));
        console.error(`FAIL: timed out after ${timeoutMs}ms`);
        console.error(`      missing markers: ${missing.join(', ')}`);
        process.exit(1);
    }

    console.log(`OK: all ${markers.length} markers found`);
    process.exit(0);
}

main().catch(err => {
    console.error('unexpected error:', err);
    process.exit(1);
});
