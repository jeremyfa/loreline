# Loreline

Loreline is a modern and open-source scripting language for writing interactive fictions.

https://loreline.app

## Development

### Prerequisites

Building Loreline from source requires [Node.js](https://nodejs.org/) (v18+).
The resulting outputs (JS library, C# library, native CLI) have no Node.js dependency.

```sh
npm install    # Install Node.js dependencies (esbuild, tsx, etc.)
```

### Building

```sh
node ./setup --js          # Build JavaScript library (js/loreline.js)
node ./setup --cs          # Export C# source files (cs/Loreline/)
node ./setup --cs --cs-dll # Export C# + build Loreline.dll
node ./setup --cpp         # Build native CLI (loreline / loreline.exe)
```

### Setting up samples

```sh
node ./setup --sample          # Set up all sample projects
node ./setup --sample web      # Set up loreline-web only
node ./setup --sample unity    # Set up loreline-unity only
```

This copies the built runtime and story files into the sample directories.
For loreline-web, run `--js` first. For loreline-unity, run `--cs` first.

### Testing

```sh
node run test ./test         # Run Neko tests only
node ./setup --test        # Run all test suites (Neko + C# + C# AOT + JS)
```

## License

MIT License

Copyright (c) 2025-2026 Jérémy Faivre

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
