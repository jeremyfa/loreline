<?php

namespace Loreline;

use Loreline\Internal\loreline\Arrays as HxArrays;
use Loreline\Internal\loreline\Json as HxJson;

/**
 * A running Loreline script interpreter.
 *
 * Provides methods to save/restore state and access character and state data.
 *
 * State values cross the boundary as native PHP arrays with snapshot
 * semantics: getters return an independent copy, and mutating that copy does
 * not change story state until it is written back through a setter. This is
 * the PHP projection of the cross platform contract (PHP arrays are value
 * types, so live views are not possible with genuine arrays).
 */
class Interpreter
{
    protected function __construct(protected mixed $internal)
    {
    }

    /**
     * Return the single Interpreter wrapper bound to a raw core interpreter.
     *
     * The wrapper is cached on the interpreter's own wrapper field so the
     * exact same instance is reused for every callback and custom function
     * call (and is the object returned by play()/resume()).
     */
    public static function of(mixed $rawInterpreter): ?Interpreter
    {
        if ($rawInterpreter === null) {
            return null;
        }
        $wrapper = $rawInterpreter->wrapper;
        if ($wrapper === null) {
            $wrapper = new Interpreter($rawInterpreter);
            $rawInterpreter->wrapper = $wrapper;
        }
        return $wrapper;
    }

    /**
     * The raw runtime handle backing this interpreter. Intended for internal use.
     */
    public function internal(): mixed
    {
        return $this->internal;
    }

    /**
     * Save the current interpreter state.
     *
     * Returns the full state serialized as a JSON string, ready to store in a
     * session, a file or a database, and accepted back by Loreline::resume()
     * or Interpreter::restore(). The format is the same across every Loreline
     * target, so a save made here can be resumed by another integration.
     */
    public function save(): string
    {
        return HxJson::stringify($this->internal->save(), false);
    }

    /**
     * Restore the interpreter to a previously saved state
     * (a JSON string returned by save()).
     */
    public function restore(string $saveData): void
    {
        $this->internal->restore(HxJson::parse($saveData));
    }

    /**
     * Resume execution after restoring state.
     */
    public function resume(): void
    {
        $this->internal->resume();
    }

    /**
     * Key of this interpreter when it was spawned from another one,
     * null for a root interpreter.
     */
    public function key(): ?string
    {
        return $this->internal->key;
    }

    /**
     * Whether this interpreter is a root interpreter (not spawned from another one).
     */
    public function isRoot(): bool
    {
        return $this->internal->isRoot();
    }

    /**
     * Spawn a child interpreter sharing everything with this one except the playhead.
     *
     * The child shares the script, state, characters and custom functions, and
     * is not started: call start() on it. Any live child using the same key is
     * disposed first, and a restored flow still pending for that key is
     * discarded (use resumeSpawn() to continue it instead). Calling save() on
     * any interpreter of the family saves the shared state and every playhead.
     *
     * A null handler reuses the one of this interpreter.
     */
    public function spawn(
        string $key,
        ?callable $handleDialogue = null,
        ?callable $handleChoice = null,
        ?callable $handleFinish = null
    ): Interpreter {
        [$dialogue, $choice, $finish] = Loreline::childBridges($handleDialogue, $handleChoice, $handleFinish);
        return Interpreter::of($this->internal->spawn($key, $dialogue, $choice, $finish));
    }

    /**
     * Rebuild a child interpreter from the flow saved under the given key,
     * after restore() on the root interpreter (or Loreline::resume()).
     * The child is not resumed yet: call resume() on it.
     *
     * A null handler reuses the one of this interpreter.
     */
    public function resumeSpawn(
        string $key,
        ?callable $handleDialogue = null,
        ?callable $handleChoice = null,
        ?callable $handleFinish = null
    ): Interpreter {
        [$dialogue, $choice, $finish] = Loreline::childBridges($handleDialogue, $handleChoice, $handleFinish);
        return Interpreter::of($this->internal->resumeSpawn($key, $dialogue, $choice, $finish));
    }

    /**
     * Keys of the saved children not resumed with resumeSpawn()
     * (nor replaced with spawn()) yet.
     *
     * @return string[]
     */
    public function resumableSpawnKeys(): array
    {
        $keys = $this->internal->resumableSpawnKeys();
        $result = [];
        $length = HxArrays::arrayLength($keys);
        for ($i = 0; $i < $length; $i++) {
            $result[] = HxArrays::arrayGet($keys, $i);
        }
        return $result;
    }

    /**
     * Reseed the random generator shared by this interpreter, its root and
     * every child. The generator is part of save data, so a restored game draws
     * the same random values as it would have without the save. Call this after
     * a restore to break that on purpose.
     *
     * @param float|null $seed The seed of the new sequence, or null for a seed taken from the clock
     */
    public function seedRandom(?float $seed = null): void
    {
        $this->internal->seedRandom($seed);
    }

    /**
     * Stop a child interpreter for good: its playhead is cleared, it is not
     * part of saves anymore, and callbacks it handed out become no-ops.
     * Throws on a root interpreter.
     */
    public function dispose(): void
    {
        $this->internal->dispose();
    }

    /**
     * Start or restart execution from a specific beat
     * (or the first beat when null).
     */
    public function start(?string $beatName = null): void
    {
        $this->internal->start($beatName);
    }

    /**
     * Get a character's fields by name, as a native PHP array snapshot,
     * or null if not found.
     */
    public function getCharacter(string $name): mixed
    {
        return Marshal::hxToPhp($this->internal->getCharacter($name), $this->internal);
    }

    /**
     * Get a specific field of a character, as a native PHP value snapshot.
     */
    public function getCharacterField(string $character, string $field): mixed
    {
        return Marshal::hxToPhp($this->internal->getCharacterField($character, $field), $this->internal);
    }

    /**
     * Set a specific field of a character. Arrays are deep copied into the story state.
     */
    public function setCharacterField(string $character, string $field, mixed $value): void
    {
        $this->internal->setCharacterField($character, $field, Marshal::phpToHx($value, $this->internal));
    }

    /**
     * Get a state field by name, resolving from the current scope outward,
     * as a native PHP value snapshot.
     */
    public function getStateField(string $name): mixed
    {
        return Marshal::hxToPhp($this->internal->getStateField($name), $this->internal);
    }

    /**
     * Set a state field by name, resolving from the current scope outward.
     * Arrays are deep copied into the story state.
     */
    public function setStateField(string $name, mixed $value): void
    {
        $this->internal->setStateField($name, Marshal::phpToHx($value, $this->internal));
    }

    /**
     * Get a field from the top-level state directly, as a native PHP value snapshot.
     */
    public function getTopLevelStateField(string $name): mixed
    {
        return Marshal::hxToPhp($this->internal->getTopLevelStateField($name), $this->internal);
    }

    /**
     * Set a field on the top-level state directly. Arrays are deep copied into the story state.
     */
    public function setTopLevelStateField(string $name, mixed $value): void
    {
        $this->internal->setTopLevelStateField($name, Marshal::phpToHx($value, $this->internal));
    }

    /**
     * Return the current node being executed, or null.
     *
     * During a dialogue callback, this returns the dialogue statement node.
     * During a choice callback, this returns the choice statement node.
     */
    public function currentNode(): ?Node
    {
        $node = $this->internal->currentNode();
        return $node !== null ? new Node($node) : null;
    }
}
