# Loreline Interpreter — Technical Reference

This document describes how the Loreline interpreter works internally. It is
intended for anyone who wants to maintain the interpreter, fix bugs, or simply
understand the execution model in depth.

The interpreter lives in `src/loreline/Interpreter.hx` and is written in Haxe.
It takes a parsed AST (`Script` from `Node.hx`) and executes it interactively.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Runtime Data Structures](#2-runtime-data-structures)
3. [Continuation-Passing Style (CPS)](#3-continuation-passing-style-cps)
4. [The `wrapNext` Mechanism](#4-the-wrapnext-mechanism)
5. [Execution Stack and Scopes](#5-execution-stack-and-scopes)
6. [Core Evaluation Loop](#6-core-evaluation-loop)
7. [Beat Transitions and Subroutine Calls](#7-beat-transitions-and-subroutine-calls)
8. [The Choice System](#8-the-choice-system)
9. [The Insertion System](#9-the-insertion-system)
10. [Conditionals and Alternatives](#10-conditionals-and-alternatives)
11. [State Management](#11-state-management)
12. [Save System — Serialization](#12-save-system--serialization)
13. [Restore System — Deserialization](#13-restore-system--deserialization)
14. [Resume Dispatch — Rebuilding the Call Stack](#14-resume-dispatch--rebuilding-the-call-stack)
15. [Complex Scenarios: Insertions + Save/Restore](#15-complex-scenarios-insertions--saverestore)
16. [Handler Callbacks and the Host Application](#16-handler-callbacks-and-the-host-application)

---

## 1. Architecture Overview

The Loreline pipeline has four stages:

```
Source text  →  Lexer  →  Parser  →  AST  →  Interpreter
```

The **Lexer** (`Lexer.hx`) tokenizes source text. The **Parser** (`Parser.hx`)
produces an AST tree of `Node` objects (defined in `Node.hx`). The
**Interpreter** (`Interpreter.hx`) walks this AST at runtime, driving dialogue,
choices, state changes, and control flow.

The interpreter is designed to be **embeddable**. It does not render UI itself;
instead, it calls handler functions provided by the host application:

- `handleDialogue` — called when text needs to be displayed
- `handleChoice` — called when choices need to be presented
- `handleFinish` — called when execution ends

The host calls the handler's callback to advance execution, which makes the
interpreter naturally **asynchronous** — it can pause at any dialogue line or
choice and resume when the host is ready.

---

## 2. Runtime Data Structures

### `RuntimeScope`

Every time the interpreter enters a block (beat body, choice option body,
if-branch, etc.), it pushes a **scope** onto the execution stack.

```
RuntimeScope {
    id: Int              — unique scope identifier
    beat: NBeatDecl      — the parent beat this scope lives within
    node: AstNode        — the AST node this scope is attached to
    beats: Array         — nested beat declarations collected in this scope
    state: RuntimeState  — temporary state variables for this scope
    head: AstNode        — the current "reading position" within the body
    insertion: RuntimeInsertion  — insertion context, if any
}
```

The `head` field is critical for save/restore: it records which AST node
execution is currently at within this scope's body.

### `RuntimeInsertion`

When a choice option uses the insertion syntax (`+ BeatName`), the interpreter
creates a `RuntimeInsertion` to track the process:

```
RuntimeInsertion {
    id: Int                     — unique insertion identifier
    origin: NInsertion          — the AST node that triggered the insertion
    options: Array<ChoiceOption> — collected options (null while collecting)
    stack: Array<RuntimeScope>  — snapshot of the execution stack at collection time
}
```

The `options` field starts as `null` and is populated when the inserted beat's
choice block is reached. The `stack` field captures a shallow copy of the
execution stack at that moment, which is used later to restore context if one
of the inserted options is selected.

### `ChoiceOption`

Represents a single choice presented to the user:

```
ChoiceOption {
    text: String                — the display text
    tags: Array<TextTag>        — inline formatting tags
    enabled: Bool               — whether this option is selectable
    node: NChoiceOption         — the AST node (internal)
    insertion: RuntimeInsertion — linked insertion, if this option came from one
}
```

### `EvalNext`

A helper object used by `wrapNext` to manage sync/async callback execution:

```
EvalNext {
    sync: Bool      — whether we're still in the synchronous phase
    cb: () -> Void  — the callback to invoke
}
```

### `RuntimeState`

Holds field values for state variables:

```
RuntimeState {
    scope: Int          — if > 0, this state is temporary and tied to a scope
    fields: Any         — current field values (map or object)
    originalFields: Any — initial values from the script (for diff-based serialization)
}
```

---

## 3. Continuation-Passing Style (CPS)

The interpreter uses **continuation-passing style** throughout. Every evaluation
function takes a `next: () -> Void` parameter — the continuation to call when
that evaluation step is complete.

```haxe
function evalText(text:NTextStatement, next:()->Void) {
    final content = evaluateString(text.content);
    handleDialogue(this, null, content.text, content.tags, next);
}
```

Here, `next` is passed directly to the host's dialogue handler. The host calls
it when the player has seen the text. This single pattern enables the entire
interpreter to pause and resume at any point without threads or coroutines.

Execution flows like this:

```
evalBeatRun(beat, done)
  └─ evalNodeBody(beat, beat, beat.body, done)
       ├─ evalNode(child1, moveNext)
       │    └─ evalText(child1, moveNext)
       │         └─ handleDialogue(..., moveNext)   ← pauses here
       │              └─ moveNext()                  ← host resumes
       ├─ evalNode(child2, moveNext)
       │    └─ evalChoice(child2, moveNext)
       │         └─ handleChoice(..., callback)      ← pauses here
       │              └─ callback(index)             ← host resumes
       └─ done()                                     ← beat finishes
```

---

## 4. The `wrapNext` Mechanism

The `wrapNext` function solves a subtle problem: when a handler calls its
callback **synchronously** (before returning), naively executing the
continuation would cause deep recursive call stacks and potential stack
overflows.

```haxe
function wrapNext(cb:()->Void):EvalNext {
    final wrapped = new EvalNext();
    wrapped.sync = true;
    wrapped.cb = () -> {
        if (wrapped.sync) {
            // Called before sync=false was set → queue it
            syncCallbacks.push(wrapped.cb);
        } else {
            // Called after sync=false → execute normally
            cb();
            flush();
        }
    };
    return wrapped;
}
```

**Usage pattern:**

```haxe
final done = wrapNext(moveNext);
evalNode(childNode, done.cb);   // may call done.cb synchronously
done.sync = false;              // mark synchronous phase as over
```

If `done.cb` is called *during* `evalNode` (before `done.sync = false`), the
callback is **queued** in `syncCallbacks`. After `done.sync = false` is set,
`flush()` drains the queue iteratively, avoiding recursion.

If `done.cb` is called *later* (asynchronously, e.g., from a UI callback), it
just executes `cb()` directly and calls `flush()`.

### The `flush()` Function

`flush()` processes queued synchronous callbacks in a loop:

```haxe
function flush() {
    while (syncCallbacks.length > 0) {
        var cb = syncCallbacks.shift();
        cb();
        // Any new callbacks added during cb() get prepended
    }
}
```

This turns potentially deep recursion into flat iteration.

### The `finishTrigger`

When a beat starts executing, the interpreter creates a `wrapNext(finish)` and
stores it as `finishTrigger`. When that specific `EvalNext`'s callback fires
(meaning the entire execution chain has completed), `finish()` is called, which
invokes `handleFinish`.

---

## 5. Execution Stack and Scopes

The interpreter maintains an `Array<RuntimeScope>` called `stack`. Each scope
represents a nested execution context:

```
stack[0]  →  { node: NBeatDecl "Main",     head: NDialogueStatement "Hello" }
stack[1]  →  { node: NIfStatement,          head: NChoiceStatement }
stack[2]  →  { node: NChoiceStatement,      head: NChoiceOption "Leave" }
```

**push(scope)** adds a new scope, assigning it a unique `id`.

**pop()** removes the top scope.

**`currentScope`** is a property that returns `stack[stack.length - 1]`.

**`currentInsertion`** walks the stack from top to bottom and returns the first
non-null `insertion` found. This is important because insertion context
propagates up through nested scopes.

---

## 6. Core Evaluation Loop

### `evalNodeBody`

This is the heart of execution. It creates a new scope, then iterates through
the body nodes one by one:

```haxe
function evalNodeBody(beat, node, body, insertion, next) {
    push({ beat: beat, node: node, insertion: insertion });

    var index = 0;
    final currentInsertion = this.currentInsertion;

    moveNext = () -> {
        if (currentInsertion?.options != null) {
            // Insertion's options are collected → stop executing this body
            pop();
            next();
        }
        else if (index < body.length) {
            currentScope.head = body[index];
            index++;
            final done = wrapNext(moveNext);
            evalNode(body[index-1], done.cb);
            done.sync = false;
        }
        else {
            pop();
            next();
        }
    };
    moveNext();
}
```

Key behaviors:

1. **Sets `head`** before evaluating each node — this is how save/restore knows
   where execution is.
2. **Checks insertion state** at each iteration — if an insertion's options
   have been collected, it exits early because the body was being evaluated
   only to reach the choice block.
3. Uses `wrapNext` to handle sync/async callbacks correctly.

### `evalNode`

A type-switch dispatcher that routes each AST node to its specific handler:

| AST Node Type        | Handler              |
|----------------------|----------------------|
| `NBeatDecl`          | `evalBeatDecl`       |
| `NStateDecl`         | `evalStateDecl`      |
| `NTextStatement`     | `evalText`           |
| `NDialogueStatement` | `evalDialogue`       |
| `NChoiceStatement`   | `evalChoice`         |
| `NChoiceOption`      | `evalChoiceOption`   |
| `NIfStatement`       | `evalIf`             |
| `NAlternative`       | `evalAlternative`    |
| `NAssign`            | `evalAssignment`     |
| `NCall`              | `evalCall`           |
| `NTransition`        | `evalTransition`     |

---

## 7. Beat Transitions and Subroutine Calls

### Transitions (`->`)

A transition (`-> BeatName`) **replaces** the entire execution stack:

```haxe
function evalTransition(transition) {
    // Resolve beat name
    resolvedBeat = findBeat(transition.target);
    transitionToBeat(resolvedBeat);
}

function transitionToBeat(beat) {
    while (pop()) {};           // clear entire stack
    nextScopeId = 1;            // reset IDs
    nextInsertionId = 1;
    final done = wrapNext(finish);
    finishTrigger = done;       // new finish trigger
    evalBeatRun(beat, done.cb);
    done.sync = false;
}
```

Note that `evalTransition` does **not** receive a `next` callback. The
transition discards the current continuation entirely, starting fresh with a
new `finishTrigger`.

The special target `-> .` calls `finish()` directly, ending execution.

### Subroutine Calls (`BeatName()`)

A call like `Examine()` acts as a **subroutine** — it evaluates the target beat
and returns to the caller:

```haxe
function evalCall(call, next) {
    resolvedBeat = resolveBeatFromCall(call);
    if (resolvedBeat != null) {
        evalBeatRun(resolvedBeat, next);  // 'next' continues after the call
        return;
    }
    evaluateFunctionCall(call, next);  // try as regular function
}
```

The `next` callback is preserved, so when the called beat finishes, execution
continues after the call site.

---

## 8. The Choice System

### `evalChoice`

The choice system works in two phases:

**Phase 1 — Collect options** (`evalChoiceOptionsAndInsertions`):
Iterates through the choice's options. For each option:
- If it has `text`, create a `ChoiceOption` and add it to the results array.
- If it has an `insertion`, create a `RuntimeInsertion` and evaluate the
  inserted beat to collect its options.

**Phase 2 — Present and handle selection**:
After all options are collected:
- If we're inside an insertion context (i.e., this choice's options are being
  collected for a parent choice), store the options on the insertion and return.
- Otherwise, call `handleChoice` to present options to the user.

### `choiceCallback` — Handling the User's Selection

When the user selects an option:

```haxe
if (option.insertion != null) {
    // This option came from an insertion — restore its stack
    while (stack.length > 0) stack.pop();
    for (scope in option.insertion.stack) {
        scope.insertion = null;   // clear ALL insertion markers
        stack.push(scope);
    }
    // Push a scope for the selected option
    push({ beat: ..., node: parent, head: option.node });
    resumeFromLevel(scopeLevel, next);
} else {
    // Normal option — just evaluate its body
    evalChoiceOption(option.node, next);
}
```

For insertion-sourced options, the interpreter:
1. Replaces the current stack with the insertion's captured stack.
2. Clears **all** insertion markers from every scope (important for nested
   insertions — see Section 15).
3. Pushes a scope for the selected option.
4. Calls `resumeFromLevel` to rebuild the execution context.

---

## 9. The Insertion System

Insertions (`+ BeatName` in a choice block) allow one beat's choice options to
be flattened into another beat's choice.

### How Insertions Work

```
beat Start
  choice
    Option A
      ...
    + SubBeat         ← insertion: include SubBeat's options here
    Option B
      ...

beat SubBeat
  Some dialogue.     ← this runs during collection
  choice
    Sub Option 1     ← these get flattened into Start's choice
    Sub Option 2
  Epilogue text.     ← this runs after selection, if a sub option is chosen
```

### Collection Flow

1. `evalChoiceOptionsAndInsertions` encounters `+ SubBeat`.
2. Creates `RuntimeInsertion { origin: insertion_node, options: null }`.
3. Calls `evalInsertion` → `evalNodeBody(SubBeat, ..., insertion)`.
4. SubBeat's body executes. The `insertion` is set on the scope.
5. When SubBeat's choice block is reached, `evalChoice` detects
   `currentInsertion != null && currentInsertion.options == null`:
   - Captures the stack: `currentInsertion.stack = [].concat(stack)`
   - Stores the options: `currentInsertion.options = options`
   - Returns via `next()` — does **not** present the choice.
6. Back in `evalNodeBody`, the early-exit check fires:
   `currentInsertion?.options != null` → pops scope and returns.
7. Back in `evalChoiceOptionsAndInsertions`, the collected options are appended
   to the parent result array.

### Stack Capture

The line `currentInsertion.stack = [].concat(stack)` creates a **shallow copy**
of the stack array. The scope objects themselves are shared references, not
deep-copied. This is correct by design:

- The stack array itself is modified by push/pop, so a copy is needed.
- The scope objects are "settled" at capture time — their `head`, `node`,
  `beat`, and `insertion` fields will not be mutated by the parent execution
  (the parent is in a different scope frame).

### Nested Insertions

Insertions can nest: SubBeat's choice can itself contain `+ DeepBeat`. The
mechanism is recursive — each level creates its own `RuntimeInsertion` and
captures its own stack snapshot. When options are flattened upward, each
`ChoiceOption` carries a reference to the `RuntimeInsertion` it originated from.

When the user selects a deeply nested option, the stack is restored from that
option's specific insertion, ensuring execution resumes in the correct context
with proper epilogue handling.

---

## 10. Conditionals and Alternatives

### `evalIf`

Evaluates the condition, then executes the matching branch body:

```haxe
function evalIf(ifStmt, next) {
    final branch = evaluateCondition(ifStmt.condition)
        ? ifStmt.thenBranch
        : ifStmt.elseBranch;
    if (branch != null)
        evalNodeBody(currentScope.beat, branch, branch.body, next);
    else
        next();
}
```

### `evalAlternative`

Alternatives come in five modes. All use `nodeStates` to persist their visit
count across transitions:

| Mode       | Behavior |
|------------|----------|
| `Sequence` | First item, second item, ..., last item forever |
| `Cycle`    | Round-robin: wraps back to first after last |
| `Once`     | Like sequence, but produces nothing after all items shown |
| `Pick`     | Random selection each time |
| `Shuffle`  | All items in random order, sequentially |

The visit count is stored in `nodeStates` (keyed by the alternative's AST node
ID), which is included in save data. This ensures sequence/cycle/once
progression is preserved across save/restore.

---

## 11. State Management

Loreline has three categories of persistent data:

### Top-Level State (`state` blocks)

Declared at the script root. Stored in `topLevelState` (a `RuntimeState`).
Always serialized on save. Only fields that differ from their script-declared
initial values are included in save data (delta serialization).

### Character State (`character` blocks)

Declared at the script root. Each character has a `RuntimeCharacter` in
`topLevelCharacters`. Like state, uses delta serialization against
`originalFields`.

### Node States (`nodeStates`)

A `Map<NodeId, RuntimeState>` that stores per-node persistent data:
- Alternative visit counts (for sequence, cycle, once)
- Beat-local `state` blocks that aren't marked `temporary`

Node states are keyed by the AST node ID, which allows them to survive across
transitions and save/restore cycles.

### Temporary State

`state` blocks declared with `new state` are temporary — stored on
`RuntimeScope.state` and destroyed when the scope is popped (i.e., when
execution leaves the block). However, they **are** serialized as part of the
scope's save data. If a save happens while a temporary state is on the stack,
it will be included in the save and restored correctly. The "temporary" aspect
means it resets when the beat is re-entered (e.g., via a transition), not that
it's excluded from saves.

---

## 12. Save System — Serialization

`save()` produces a `SaveData` object:

```
SaveData {
    version: 1
    stack: Array<SaveDataScope>       — serialized execution stack
    state: SaveDataState              — top-level state fields (delta)
    characters: { name: SaveDataCharacter }  — character fields (delta)
    nodeStates: { id: SaveDataState }        — per-node persistent data
    insertions: { id: SaveDataInsertion }    — insertion data (if any)
}
```

### Scope Serialization

Each scope is serialized as:

```
SaveDataScope {
    id: Int
    beat: { id: "nodeId", path: "ParentBeat.ChildBeat" }  — beat path for lookup
    node: { id: "nodeId", type: "NChoiceStatement" }       — node reference
    head: { id: "nodeId", type: "NDialogueStatement" }     — current position
    state: SaveDataState     — temporary state, if any
    beats: Array             — nested beat references
    insertion: Int           — insertion ID reference
}
```

**Beat references** use a dotted path (`"Main"` or `"Parent.Child"`) for
resilience against script modifications. **Node references** use the node ID
plus type string for verification.

### Insertion Serialization

Insertions are serialized into a flat map (keyed by insertion ID) to handle
shared references and avoid circular structures:

```
SaveDataInsertion {
    origin: { id, type }                    — the NInsertion AST node
    options: Array<SaveDataChoiceOption>     — collected choice options
    stack: Array<SaveDataScope>             — captured stack snapshot
}
```

Each `SaveDataChoiceOption` includes the option text, tags, enabled state, the
AST node reference, and its own insertion ID (for nested insertions).

### Delta Serialization for Fields

`serializeFields` compares current field values against `originalFields` (the
initial script-declared values). Only changed fields are included in save data.
This keeps save files compact when most state hasn't changed.

---

## 13. Restore System — Deserialization

`restore(saveData)` performs these steps in order:

1. **Clear current state**: empties stack, resets `nodeStates`, resets ID
   counters.
2. **Restore top-level state**: applies saved field deltas onto the existing
   `topLevelState`.
3. **Restore character states**: applies saved field deltas onto existing
   characters (or creates new ones if a character was added to save data that
   no longer exists in the script).
4. **Restore node states**: rebuilds `nodeStates` map from saved data.
5. **Restore stack**: deserializes each scope, resolving AST node references.

### Node Resolution

Restoring a scope requires mapping serialized node references back to live AST
nodes. This uses `Lens`, a utility that indexes the AST by node ID:

```haxe
function restoreNode(savedNode, savedBeatId, beat) {
    // Compute offset in case the script was modified
    sectionOffset = beat.id.section - savedBeatId.section;
    nodeId = NodeId.fromString(savedNode.id);
    nodeId.section += sectionOffset;

    node = lens.getNodeById(nodeId);
    if (node != null && node.type() == savedNode.type)
        return node;
    return null;
}
```

This offset-based approach provides some resilience to script edits — if lines
were added above the beat, the section offset compensates.

Beat references use `lens.findBeatByPathFromNode(path, script)` which resolves
dotted paths like `"Parent.Child"`.

### Insertion Restoration

`restoreInsertion` handles the circular reference problem (an insertion's stack
contains scopes that reference the same insertion) by using a cache:

```haxe
function restoreInsertion(insertionId, savedInsertions, restoredInsertions) {
    if (restoredInsertions.exists(insertionId))
        return restoredInsertions.get(insertionId);  // cache hit

    insertion = new RuntimeInsertion(insertionId, origin);
    restoredInsertions.set(insertionId, insertion);   // cache BEFORE recursing

    // Now safely restore stack and options (which may reference this insertion)
    insertion.options = restoreOptions(...);
    insertion.stack = restoreStack(...);
    return insertion;
}
```

### Fallback Behavior

If stack restoration fails (e.g., the script was heavily modified), `restore()`
falls back to `restoreBeatToResume()`, which finds the outermost top-level beat
from the saved data. On `resume()`, if the stack is empty, it simply calls
`start()`, effectively restarting from the beginning of that beat.

---

## 14. Resume Dispatch — Rebuilding the Call Stack

After `restore()` reconstructs the stack data, `resume()` must rebuild the
*actual execution context* — the chain of Haxe method calls and closures that
would exist if execution had naturally reached the saved point.

### `resume()`

```haxe
public function resume() {
    if (stack.length == 0) { start(); return; }

    final done = wrapNext(finish);
    finishTrigger = done;
    resumeNode(stack[0].node, 0, done.cb);
    done.sync = false;
    flush();
}
```

This starts at stack level 0 and recursively descends through the stack,
recreating the call chain.

### `resumeNode` — The Dispatch Hub

`resumeNode(node, scopeLevel, next)` has two modes:

**Not the last level** (needs to recurse deeper):

| Node Type          | Handler              |
|--------------------|----------------------|
| `NBeatDecl`        | `resumeBeatRun`      |
| `NChoiceOption`    | `resumeChoiceOption` |
| `NChoiceStatement` | `resumeChoice`       |
| `NIfStatement`     | `resumeIf`           |
| `NAlternative`     | `resumeAlternative`  |
| `NCall` (beat)     | `resumeCall`         |

**Last level** (leaf — re-evaluate from this node):

| Node Type            | Handler            |
|----------------------|--------------------|
| `NCall` (function)   | `evalCall`         |
| `NChoiceStatement`   | `evalChoice`       |
| `NTextStatement`     | `evalText`         |
| `NDialogueStatement` | `evalDialogue`     |
| `NAlternative`       | `evalAlternative`  |

### `resumeNodeBody` — The Key Mechanism

This is where the magic happens. Given a body (array of AST nodes) and the
scope's `head` (the node where we were paused):

```haxe
function resumeNodeBody(node, scopeLevel, body, next) {
    currentScope = stack[scopeLevel];
    resumeIndex = body.indexOf(currentScope.head);

    moveNext = () -> {
        if (index == resumeIndex) {
            // This is the paused node — resume into it
            resumeNode(body[index], scopeLevel + 1, moveNext);
        }
        else if (index < body.length) {
            // Past the resume point — evaluate normally
            evalNode(body[index], moveNext);
        }
        else {
            pop();
            next();
        }
    };
    moveNext();
}
```

The critical insight: it **skips** all nodes before `head` (they were already
executed before the save) and **resumes** into the `head` node by calling
`resumeNode` at the next scope level. After the resumed node completes, it
continues evaluating remaining nodes **normally** using `evalNode`.

This means resume naturally picks up where it left off — executing any
remaining dialogue, choices, or statements that follow the saved position.

### Example: Resuming a 3-Level Subroutine Chain

Given this script:

```
beat Main
  Hello.
  Examine()          ← saved here, inside LevelTwo
  Goodbye.

beat Examine
  Looking around.
  LevelTwo()
  Done examining.

beat LevelTwo
  choice              ← save happened at this choice
    Option A
      ...
```

The saved stack would be:

```
stack[0] = { node: Main,     head: NCall(Examine) }
stack[1] = { node: Examine,  head: NCall(LevelTwo) }
stack[2] = { node: LevelTwo, head: NChoiceStatement }
```

Resume proceeds:

1. `resumeNode(Main, 0, finish)` → `resumeBeatRun(Main, 0, finish)`
2. `resumeNodeBody(Main, 0, Main.body, finish)` finds `head = NCall(Examine)`:
   - Skips "Hello." (already executed)
   - At NCall(Examine): calls `resumeNode(NCall, 1, moveNext)`
3. `resumeCall(NCall, 1, moveNext)` → resolves to Examine beat →
   `resumeBeatRun(Examine, 1, moveNext)`
4. `resumeNodeBody(Examine, 1, Examine.body, moveNext)` finds
   `head = NCall(LevelTwo)`:
   - Skips "Looking around."
   - At NCall(LevelTwo): calls `resumeNode(NCall, 2, moveNext2)`
5. `resumeCall(NCall, 2, moveNext2)` → resolves to LevelTwo →
   `resumeBeatRun(LevelTwo, 2, moveNext2)`
6. `resumeNodeBody(LevelTwo, 2, LevelTwo.body, moveNext2)` finds
   `head = NChoiceStatement`:
   - At NChoiceStatement: this is the last level → `evalChoice(choice, moveNext2)`
   - Choice is presented to the user.
7. After user picks, `moveNext2` fires → LevelTwo body is done → pops scope
8. Back in Examine: `moveNext2` → evaluates "Done examining." → pops scope
9. Back in Main: evaluates "Goodbye." → pops scope → `finish()`

**The interpreter has reconstructed the full call chain through actual method
calls**, not by storing closures. Each `resumeNodeBody` creates a real
`moveNext` closure that will execute remaining nodes after the resumed one
completes. This is what makes resume work seamlessly — it's as if execution
never stopped.

### `resumeChoice` — Special Cases

`resumeChoice` handles several situations depending on the scope state:

1. **`head == null`**: The choice hasn't been evaluated yet → `evalChoice`.
2. **`head` is `NChoiceOption`**: A choice was already made; resume the option's
   body evaluation.
3. **`insertion != null`**: Save happened during Phase 1 (option collection
   during insertion). Pop insertion scopes and re-evaluate the whole choice.
4. **`node` is `NChoiceOption`**: The choice is nested inside another choice
   option's body → `resumeNodeBody` on that option.
5. **`node` is `NBeatDecl`**: The choice is inside a beat body reached through
   an insertion context → `resumeNodeBody` on the beat.

Cases 4 and 5 handle deeply nested structures where a choice appears within
another choice's option body or within a beat being evaluated as part of an
insertion chain.

---

## 15. Complex Scenarios: Insertions + Save/Restore

### Scenario: Triple Nested Insertions with Save/Restore

```
beat Start
  choice
    Direct
      Picked direct.
    + Level1

beat Level1
  choice
    Level1 pick
      Picked level1.
    + Level2

beat Level2
  choice
    Level2 pick
      Picked level2.
    + Level3

beat Level3
  choice
    Level3 A
      Picked level3 A.
    Level3 B
      Picked level3 B.
```

**Without save/restore**, the user sees 5 flattened options:
`Direct | Level1 pick | Level2 pick | Level3 A | Level3 B`.

**With save at the choice point**, the save captures:
- The stack with all the nested evalNodeBody scopes from insertion collection
- Each insertion's captured stack and options

On restore + resume:
- The stack is rebuilt, the choice is re-evaluated
- Options are re-collected (insertions re-evaluated)
- The user sees the same 5 options again

When the user picks "Level3 A":
1. `option.insertion` points to the Level3 insertion's `RuntimeInsertion`
2. The current stack is replaced with `option.insertion.stack`
3. **All** insertion markers are cleared from every scope
4. A scope for the selected option is pushed
5. `resumeFromLevel` rebuilds the execution context

The clearing of **all** insertion markers (not just the innermost) is crucial.
Without this, outer insertions would retain stale `options` data, causing
`evalNodeBody` to short-circuit via the `currentInsertion?.options != null`
early-exit check.

### Scenario: Insertions with Epilogue Content

```
beat Start
  choice
    Direct
      Direct done.
    + Level1
  Back at start.

beat Level1
  choice
    Level1 option
      Level1 done.
    + Level2
  Back at level1.

beat Level2
  choice
    Level2 option
      Level2 done.
  Back at level2.
```

If the user picks "Level2 option":
1. Stack is restored from Level2's insertion
2. "Level2 done." is output
3. `evalNodeBody` for Level2 continues → "Back at level2." is output
4. Level2's evalNodeBody completes → pops scope
5. Back in Level1's body → "Back at level1." is output
6. Level1's evalNodeBody completes → pops scope
7. Back in Start's body → "Back at start." is output

This works because `resumeFromLevel` creates actual method call frames for each
level. When each level's `evalNodeBody` completes, its `next` callback fires,
which is the `moveNext` of the parent level — naturally continuing with the
remaining nodes.

---

## 16. Handler Callbacks and the Host Application

The interpreter communicates with the host through three handler functions:

### `DialogueHandler`

```haxe
(interpreter, character, text, tags, callback) -> Void
```

- `character`: `null` for narrator text, otherwise the character name
- `text`: the evaluated string content
- `tags`: inline formatting tags (bold, italic, etc.)
- `callback`: call this to advance execution

### `ChoiceHandler`

```haxe
(interpreter, options, callback) -> Void
```

- `options`: array of `ChoiceOption` objects
- `callback(index)`: call with the selected option's index to advance

The host can call `callback` synchronously or asynchronously. The `wrapNext`
mechanism handles both cases correctly. Disabled options (`enabled == false`)
are included in the array — the host decides whether to display or hide them.

### `FinishHandler`

```haxe
(interpreter) -> Void
```

Called when execution reaches the end of a beat with no transition and no more
nodes to execute, or when a `-> .` transition is encountered.

### Save/Restore API

From the host's perspective:

```haxe
// Save at any choice point
var saveData = interpreter.save();

// Later, to restore:
interpreter.restore(saveData);
interpreter.resume();  // re-enters the choice
```

The host typically saves when `handleChoice` is called and restores when the
user wants to load a previous state. After `resume()`, the interpreter calls
`handleChoice` again with the same options (re-collected), letting the user
make a different selection.
