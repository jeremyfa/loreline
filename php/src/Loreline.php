<?php

namespace Loreline;

use Loreline\Internal\loreline\Arrays as HxArrays;
use Loreline\Internal\loreline\Loreline as HxLoreline;
use Loreline\Internal\loreline\Timer as HxTimer;
use Loreline\Internal\php\_Boot\HxAnon;

/**
 * Main public API for the Loreline interactive fiction runtime.
 *
 * All methods are static. Typical usage:
 *
 *     $script = Loreline::parse($source);
 *     $interpreter = Loreline::play($script, $onDialogue, $onChoice, $onFinish);
 *
 * Handler signatures:
 * - dialogue: function(Interpreter $interpreter, ?string $character, string $text, TextTag[] $tags, callable $advance): void
 * - choice: function(Interpreter $interpreter, ChoiceOption[] $options, callable $select): void
 * - finish: function(Interpreter $interpreter): void
 * - imports file handler: function(string $path, callable $callback): void
 */
final class Loreline
{
    /**
     * Parse a Loreline script string into a Script AST.
     *
     * $filePath enables import resolution and requires $handleFile.
     * $callback receives the parsed Script, useful when $handleFile resolves
     * asynchronously. Returns the parsed Script, or null when loading
     * asynchronously. Throws if the script contains syntax errors.
     */
    public static function parse(
        string $source,
        ?string $filePath = null,
        ?callable $handleFile = null,
        ?callable $callback = null
    ): ?Script {
        $wrappedCallback = null;
        if ($callback !== null) {
            $wrappedCallback = function ($internalScript) use ($callback) {
                $callback($internalScript !== null ? new Script($internalScript) : null);
            };
        }
        $result = HxLoreline::parse($source, $filePath, $handleFile, $wrappedCallback);
        return $result !== null ? new Script($result) : null;
    }

    /**
     * Start playing a parsed script.
     *
     * $options accepts an associative array with these keys:
     * - functions: map of name to function(Interpreter $interpreter, array $args): mixed
     * - strictAccess: bool, if true accessing undefined variables raises an error
     * - translations: a translations map from extractTranslations()/loadLocale()
     */
    public static function play(
        Script $script,
        callable $handleDialogue,
        callable $handleChoice,
        callable $handleFinish,
        ?string $beatName = null,
        ?array $options = null
    ): Interpreter {
        $internal = HxLoreline::play(
            $script->internal(),
            self::makeDialogueBridge($handleDialogue),
            self::makeChoiceBridge($handleChoice),
            self::makeFinishBridge($handleFinish),
            $beatName,
            self::makeOptions($options)
        );
        return Interpreter::of($internal);
    }

    /**
     * Resume a script from saved state.
     *
     * $saveData is the opaque value returned by Interpreter::save().
     * $options has the same shape as in play().
     */
    public static function resume(
        Script $script,
        callable $handleDialogue,
        callable $handleChoice,
        callable $handleFinish,
        mixed $saveData,
        ?string $beatName = null,
        ?array $options = null
    ): Interpreter {
        $internal = HxLoreline::resume(
            $script->internal(),
            self::makeDialogueBridge($handleDialogue),
            self::makeChoiceBridge($handleChoice),
            self::makeFinishBridge($handleFinish),
            $saveData,
            $beatName,
            self::makeOptions($options)
        );
        return Interpreter::of($internal);
    }

    /**
     * Extract translations from a parsed translation script (a .XX.lor file).
     *
     * Returns an opaque translations map to pass as the translations option
     * to play() or resume().
     */
    public static function extractTranslations(Script $script): mixed
    {
        return HxLoreline::extractTranslations($script->internal());
    }

    /**
     * Enable or disable runtime support for an alternate translation file
     * format. Known names: "po" (.po), "xliff" (.xliff, .xlf), "csv"
     * (.csv, .tsv). Unknown names are accepted silently.
     */
    public static function translationFormat(string $name, bool $enabled): void
    {
        HxLoreline::translationFormat($name, $enabled);
    }

    /**
     * Return the error from the most recent failed parse() or loadLocale()
     * call, or null on success.
     */
    public static function lastError(): mixed
    {
        return HxLoreline::lastError();
    }

    /**
     * Load translations for a specific locale, walking the script's full
     * import tree. Returns the merged translations map (synchronously, when
     * $handleFile is synchronous), also delivered through $callback.
     */
    public static function loadLocale(
        string $locale,
        Script $script,
        ?string $filePath = null,
        ?callable $handleFile = null,
        ?callable $callback = null
    ): mixed {
        return HxLoreline::loadLocale($locale, $script->internal(), $filePath, $handleFile, $callback);
    }

    /**
     * Print a parsed script back into Loreline source code.
     */
    public static function print(Script $script, string $indent = '  ', string $newline = "\n"): string
    {
        return HxLoreline::print($script->internal(), $indent, $newline);
    }

    /**
     * Tick pending wait() timers. Call from your game loop every frame.
     *
     * The first call enables non blocking deferred mode for wait(); before
     * this is called, wait() falls back to blocking sleep (correct for CLI tools).
     */
    public static function update(float $delta): void
    {
        HxTimer::update($delta);
    }

    private static function makeOptions(?array $options): HxAnon
    {
        $options ??= [];
        return new HxAnon([
            'functions' => self::wrapFunctions($options['functions'] ?? null),
            'strictAccess' => (bool) ($options['strictAccess'] ?? false),
            'translations' => $options['translations'] ?? null,
        ]);
    }

    private static function wrapFunctions(?array $functions): ?HxAnon
    {
        if ($functions === null) {
            return null;
        }
        $wrapped = [];
        foreach ($functions as $name => $fn) {
            $wrapped[$name] = function ($rawInterpreter, $args) use ($fn) {
                $phpArgs = [];
                $length = HxArrays::arrayLength($args);
                for ($i = 0; $i < $length; $i++) {
                    $phpArgs[] = Marshal::hxToPhp(HxArrays::arrayGet($args, $i), $rawInterpreter);
                }
                $result = $fn(Interpreter::of($rawInterpreter), $phpArgs);
                return Marshal::phpToHx($result, $rawInterpreter);
            };
        }
        return new HxAnon($wrapped);
    }

    private static function wrapTags(mixed $tags): array
    {
        $result = [];
        if ($tags === null) {
            return $result;
        }
        $length = HxArrays::arrayLength($tags);
        for ($i = 0; $i < $length; $i++) {
            $tag = HxArrays::arrayGet($tags, $i);
            $result[] = new TextTag($tag->value, $tag->offset, $tag->closing);
        }
        return $result;
    }

    private static function makeDialogueBridge(callable $handleDialogue): \Closure
    {
        return function ($rawInterpreter, $character, $text, $tags, $advance) use ($handleDialogue) {
            $handleDialogue(Interpreter::of($rawInterpreter), $character, $text, self::wrapTags($tags), $advance);
        };
    }

    private static function makeChoiceBridge(callable $handleChoice): \Closure
    {
        return function ($rawInterpreter, $options, $select) use ($handleChoice) {
            $wrappedOptions = [];
            $length = HxArrays::arrayLength($options);
            for ($i = 0; $i < $length; $i++) {
                $option = HxArrays::arrayGet($options, $i);
                $wrappedOptions[] = new ChoiceOption($option->text, self::wrapTags($option->tags), $option->enabled);
            }
            $handleChoice(Interpreter::of($rawInterpreter), $wrappedOptions, $select);
        };
    }

    private static function makeFinishBridge(callable $handleFinish): \Closure
    {
        return function ($rawInterpreter) use ($handleFinish) {
            $handleFinish(Interpreter::of($rawInterpreter));
        };
    }
}
