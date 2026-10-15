package loreline;

import loreline.Arrays;
import loreline.Interpreter;
import loreline.Node.NBeatDecl;
import loreline.Objects;
import loreline.Random;

/**
 * All built-in functions available to Loreline scripts.
 *
 * Each public method corresponds to a function that script authors
 * can call directly. Use `bindAll()` to register every function
 * into a name-to-function map so the interpreter can look them up.
 */
class Functions {

    final interpreter:Interpreter;

    public function new(interpreter:Interpreter) {
        this.interpreter = interpreter;
    }

    /**
     * Registers all built-in functions into the given map, making them
     * callable by name from Loreline scripts.
     */
    public function bindAll(target:Map<String, Any>):Void {
        // Math
        target.set("floor", this.floor);
        target.set("ceil", this.ceil);
        target.set("round", this.round);
        target.set("abs", this.abs);
        target.set("min", this.min);
        target.set("max", this.max);
        target.set("clamp", this.clamp);
        target.set("pow", this.pow);
        // Random
        target.set("random", this.random);
        target.set("chance", this.chance);
        target.set("seed_random", this.seed_random);
        target.set("random_decimal", this.random_decimal);
        // Timing
        target.set("wait", this.wait);
        // Type conversion
        target.set("number", this.number);
        target.set("string", this.string_);
        target.set("bool", this.bool);
        target.set("type_of", this.type_of);
        // String
        target.set("string_length", this.string_length);
        target.set("string_upper", this.string_upper);
        target.set("string_lower", this.string_lower);
        target.set("string_contains", this.string_contains);
        target.set("string_replace", this.string_replace);
        target.set("string_split", this.string_split);
        target.set("string_trim", this.string_trim);
        target.set("string_index", this.string_index);
        target.set("string_sub", this.string_sub);
        target.set("string_starts", this.string_starts);
        target.set("string_ends", this.string_ends);
        target.set("string_repeat", this.string_repeat);
        // Text
        target.set("plural", this.plural);
        // Array
        target.set("array_length", this.array_length);
        target.set("array_add", this.array_add);
        target.set("array_pop", this.array_pop);
        target.set("array_prepend", this.array_prepend);
        target.set("array_shift", this.array_shift);
        target.set("array_remove", this.array_remove);
        target.set("array_index", this.array_index);
        target.set("array_has", this.array_has);
        target.set("array_sort", this.array_sort);
        target.set("array_reverse", this.array_reverse);
        target.set("array_join", this.array_join);
        target.set("array_pick", this.array_pick);
        target.set("array_shuffle", this.array_shuffle);
        target.set("array_copy", this.array_copy);
        // Map
        target.set("map_length", this.map_length);
        target.set("map_keys", this.map_keys);
        target.set("map_has", this.map_has);
        target.set("map_get", this.map_get);
        target.set("map_set", this.map_set);
        target.set("map_remove", this.map_remove);
        target.set("map_copy", this.map_copy);
        // Game state
        target.set("current_beat", this.current_beat);
        target.set("has_beat", this.has_beat);
        target.set("beat_visits", this.beat_visits);
        // Choice introspection
        target.set("choices", this.choices);
        target.set("choices_disabled", this.choices_disabled);
        target.set("choices_all", this.choices_all);
    }

    // -- Private helper ------------------------------------------------

    function rng():Float {
        // The generator lives in the context, shared by every interpreter spawned from the same root
        @:privateAccess final context = interpreter.context;
        if (context.random == null) {
            context.random = new Random();
        }
        return context.random.next();
    }

    // -- Math ----------------------------------------------------------

    /**
     * Rounds a number down to the nearest whole number.
     *
     * `floor(3.7)` returns `3`, `floor(-1.2)` returns `-2`.
     *
     * ```lor
     * val = floor(3.7)
     * You need $val gold coins to enter. // "You need 3 gold coins to enter."
     * ```
     */
    public function floor(n:Any):Float {
        return Math.ffloor(Values.numberArg(n, 'floor'));
    }

    /**
     * Rounds a number up to the nearest whole number.
     *
     * `ceil(3.2)` returns `4`, `ceil(-1.8)` returns `-1`.
     *
     * ```lor
     * days = ceil(hours / 24)
     * The journey takes at least $days days.
     * ```
     */
    public function ceil(n:Any):Float {
        return Math.fceil(Values.numberArg(n, 'ceil'));
    }

    /**
     * Rounds a number to the nearest whole number.
     *
     * `round(3.5)` returns `4`, `round(3.4)` returns `3`.
     *
     * ```lor
     * score = round(raw_score)
     * Your final score is $score.
     * ```
     */
    public function round(n:Any):Float {
        // Halves go up, -2.5 included: the same rule on every target
        return Math.ffloor(Values.numberArg(n, 'round') + 0.5);
    }

    /**
     * Returns the positive version of a number, removing any negative sign.
     *
     * `abs(-5)` returns `5`, `abs(3)` returns `3`.
     *
     * ```lor
     * diff = abs(your_score - target_score)
     * You were off by $diff points.
     * ```
     */
    public function abs(n:Any):Float {
        return Math.abs(Values.numberArg(n, 'abs'));
    }

    /**
     * Returns the smaller of two values.
     *
     * `min(3, 7)` returns `3`.
     *
     * ```lor
     * damage = min(attack_power, enemy_health)
     * ```
     */
    public function min(a:Any, b:Any):Float {
        return smaller(Values.numberArg(a, 'min'), Values.numberArg(b, 'min'));
    }

    /**
     * Returns the larger of two values.
     *
     * `max(3, 7)` returns `7`.
     *
     * ```lor
     * health = max(health - damage, 0)
     * ```
     */
    public function max(a:Any, b:Any):Float {
        return larger(Values.numberArg(a, 'max'), Values.numberArg(b, 'max'));
    }

    /**
     * Keeps a value within a given range. If the value is too low, returns the
     * minimum; if too high, returns the maximum; otherwise returns it unchanged.
     *
     * `clamp(10, 0, 5)` returns `5`, `clamp(3, 0, 5)` returns `3`.
     *
     * ```lor
     * health = clamp(health + healing, 0, max_health)
     * ```
     */
    public function clamp(v:Any, lo:Any, hi:Any):Float {
        return larger(Values.numberArg(lo, 'clamp'), smaller(Values.numberArg(hi, 'clamp'), Values.numberArg(v, 'clamp')));
    }

    // Math.min and Math.max differ between targets on NaN: NaN wins here
    static function smaller(a:Float, b:Float):Float {
        return Math.isNaN(a) || Math.isNaN(b) ? Math.NaN : (a < b ? a : b);
    }

    static function larger(a:Float, b:Float):Float {
        return Math.isNaN(a) || Math.isNaN(b) ? Math.NaN : (a > b ? a : b);
    }

    /**
     * Raises a number to the given power.
     *
     * `pow(2, 3)` returns `8` (2 x 2 x 2). `pow(9, 0.5)` returns `3` (square root).
     *
     * ```lor
     * area = pow(side_length, 2)
     * The room is $area square meters.
     * ```
     */
    public function pow(base:Any, exp:Any):Float {
        return power(Values.numberArg(base, 'pow'), Values.numberArg(exp, 'pow'));
    }

    /**
     * Math.pow with the results of IEEE 754 everywhere. On Python, math.pow
     * raises an error where IEEE gives NaN (a negative number to a decimal
     * power) or an infinity (0 to a negative power, a result too large).
     */
    static function power(base:Float, exponent:Float):Float {
        #if python
        if (base == 0 && exponent < 0) return Math.POSITIVE_INFINITY;
        if (base < 0 && Math.isFinite(exponent) && Math.ffloor(exponent) != exponent) return Math.NaN;
        try {
            return Math.pow(base, exponent);
        }
        catch (e:Dynamic) {
            // Too large: the sign of the result, an odd power of a negative number being negative
            final odd = Math.ffloor(exponent / 2) * 2 != exponent;
            return base < 0 && odd ? Math.NEGATIVE_INFINITY : Math.POSITIVE_INFINITY;
        }
        #else
        return Math.pow(base, exponent);
        #end
    }

    // -- Random --------------------------------------------------------

    /**
     * Returns a random whole number between min and max, including both ends.
     *
     * ```lor
     * roll = random(1, 6)
     * You rolled a $roll!
     * ```
     */
    public function random(min:Any, max:Any):Float {
        var lo = Values.numberArg(min, 'random');
        var hi = Values.numberArg(max, 'random');
        if (lo > hi) {
            final swap = lo;
            lo = hi;
            hi = swap;
        }
        // Whole bounds, inside the range given
        lo = Math.fceil(lo);
        hi = Math.ffloor(hi);
        if (hi < lo) hi = lo;
        return Math.ffloor(lo + rng() * (hi + 1 - lo));
    }

    /**
     * Returns `true` with a 1-in-n probability. Useful for occasional random events.
     *
     * `chance(3)` has roughly a 33% chance of being true.
     *
     * ```lor
     * if chance(4)
     *   You find a rare gem on the ground!
     * ```
     */
    /**
     * A whole number between `min` and `max` included, for the interpreter
     * itself (alternatives, the `pick` strategy). Draws as `random` does.
     */
    public function randomInt(min:Int, max:Int):Int {
        return Math.floor(min + rng() * (max + 1 - min));
    }

    public function chance(n:Any):Bool {
        final count = Values.numberArg(n, 'chance');
        // A number is drawn every time, so that what follows draws the same
        final roll = rng();
        return count <= 1 || Math.ffloor(roll * count) == 0;
    }

    /**
     * Sets the random seed so that all future random results follow a predictable
     * sequence. Calling `seed_random` with the same value always produces the same
     * results for `random`, `chance`, `random_decimal`, `array_pick`, and `array_shuffle`.
     *
     * ```lor
     * seed_random(42)
     * // From here, the sequence of random values is always the same.
     * ```
     *
     * The sequence is part of save data: after a restore, random results continue
     * exactly where they were. Calling `seed_random()` without a value starts a new,
     * unpredictable sequence instead.
     *
     * ```lor
     * seed_random()
     * // From here, random results differ from one playthrough to another.
     * ```
     */
    public function seed_random(?seed:Any):Dynamic {
        interpreter.seedRandom(seed == null ? null : Values.numberArg(seed, 'seed_random'));
        return null;
    }

    /**
     * Returns a random decimal number from `min` up to (but not including) `max`.
     *
     * `random_decimal(0, 1)` might return `0.7341...`.
     *
     * ```lor
     * temperature = round(random_decimal(15, 30))
     * It's $temperature degrees outside today.
     * ```
     */
    public function random_decimal(min:Any, max:Any):Float {
        final lo = Values.numberArg(min, 'random_decimal');
        final hi = Values.numberArg(max, 'random_decimal');
        return lo + rng() * (hi - lo);
    }

    // -- Timing --------------------------------------------------------

    /**
     * Pauses the script for the given number of seconds before continuing.
     *
     * ```lor
     * The ground begins to shake...
     * wait(2)
     * A massive boulder crashes through the wall!
     * ```
     */
    public function wait(delay:Any):Async {
        final seconds = Values.numberArg(delay, 'wait');
        return new Async(done -> {
            #if js
            haxe.Timer.delay(done, Std.int(seconds * 1000));
            #elseif sys
            if (Timer.deferredMode) Timer.register(seconds, done);
            else { Sys.sleep(seconds); done(); }
            #else
            done();
            #end
        });
    }

    // -- Type Conversion -----------------------------------------------

    /**
     * Converts a value to a number. A text written as a number is read as
     * comparisons read it (`"3.14"`, `" 5 "`, `"1e3"`); `true` becomes `1`,
     * `false` becomes `0`. Returns `0` if conversion fails.
     *
     * ```lor
     * price = number("9.99")
     * ```
     */
    public function number(value:Any):Dynamic {
        if (value == null) return 0.0;
        if (value is String) {
            final number = Values.numberOfText(value);
            return Math.isNaN(number) ? 0.0 : number;
        }
        final type = Type.typeof(value);
        return switch type {
            case TInt | TFloat: Values.numberOf(value, type);
            case TBool: (value : Bool) ? 1.0 : 0.0;
            case _: 0.0;
        }
    }

    /**
     * Converts any value to text.
     *
     * ```lor
     * label = string(42)   // "42"
     * ```
     */
    @:keep public function string_(value:Any):Dynamic {
        return Values.textOf(value, interpreter);
    }

    /**
     * Converts a value to `true` or `false`:
     * - Numbers: `0` is false, everything else is true
     * - Strings: empty `""` is false, non-empty is true
     * - Arrays: empty is false, non-empty is true
     * - `null`: false
     *
     * ```lor
     * if bool(item_count)
     *   You are carrying items.
     * ```
     */
    public function bool(value:Any):Bool {
        return Values.isTruthy(value);
    }

    /**
     * Tells what kind of value this is, as a word: `"number"`, `"text"`,
     * `"bool"`, `"array"`, `"object"`, `"beat"`, `"character"`, `"function"`
     * or `"null"`. Whole and decimal numbers are both `"number"`.
     *
     * ```lor
     * if type_of(gift) is "text"
     *   barista: A note? How sweet.
     * ```
     */
    public function type_of(value:Any):String {
        return Values.typeOf(value);
    }

    // -- String --------------------------------------------------------

    /**
     * Returns the number of characters in a string.
     *
     * ```lor
     * name = "Alice"
     * Your name has $string_length(name) letters.
     * ```
     */
    public function string_length(text:Any):Int {
        return Texts.length(Values.textArg(text, 'string_length'));
    }

    /**
     * Converts all letters to uppercase.
     *
     * `string_upper("hello")` returns `"HELLO"`.
     *
     * ```lor
     * title = string_upper(player_name)
     * The crowd chants: $title! $title!
     * ```
     */
    public function string_upper(text:Any):String {
        return Texts.upper(Values.textArg(text, 'string_upper'));
    }

    /**
     * Converts all letters to lowercase.
     *
     * `string_lower("HELLO")` returns `"hello"`.
     */
    public function string_lower(text:Any):String {
        return Texts.lower(Values.textArg(text, 'string_lower'));
    }

    /**
     * Checks if a string contains a given piece of text.
     *
     * `string_contains("hello world", "world")` returns `true`.
     *
     * ```lor
     * if string_contains(message, "help")
     *   Someone needs assistance!
     * ```
     */
    public function string_contains(text:Any, needle:Any):Bool {
        return StringTools.contains(Values.textArg(text, 'string_contains'), Values.textArg(needle, 'string_contains'));
    }

    /**
     * Replaces every occurrence of a piece of text with something else.
     *
     * `string_replace("hello world", "world", "there")` returns `"hello there"`.
     *
     * ```lor
     * censored = string_replace(message, "darn", "****")
     * ```
     */
    public function string_replace(text:Any, from:Any, to:Any):String {
        final source = Values.textArg(text, 'string_replace');
        final search = Values.textArg(from, 'string_replace');
        final replacement = Values.textArg(to, 'string_replace');
        // An empty search goes between the characters, whole ones
        if (search.length == 0) return Texts.chars(source).join(replacement);
        return StringTools.replace(source, search, replacement);
    }

    /**
     * Splits a string into an array of pieces at each occurrence of a separator.
     *
     * `string_split("a,b,c", ",")` returns `["a", "b", "c"]`.
     *
     * ```lor
     * words = string_split(sentence, " ")
     * The sentence has $length(words) words.
     * ```
     */
    public function string_split(text:Any, sep:Any):Array<String> {
        final source = Values.textArg(text, 'string_split');
        final separator = Values.textArg(sep, 'string_split');
        // An empty separator splits into characters, whole ones
        if (separator.length == 0) return Texts.chars(source);
        return source.split(separator);
    }

    /**
     * Removes any spaces or whitespace from the beginning and end of a string.
     *
     * `string_trim("  hello  ")` returns `"hello"`.
     */
    public function string_trim(text:Any):String {
        return StringTools.trim(Values.textArg(text, 'string_trim'));
    }

    /**
     * Finds where a piece of text first appears inside a string.
     * Returns the position (starting from `0`), or `-1` if not found.
     *
     * `string_index("hello", "ll")` returns `2`.
     *
     * ```lor
     * pos = string_index(clue, "treasure")
     * if pos >= 0
     *   The clue mentions a treasure!
     * ```
     */
    public function string_index(text:Any, needle:Any):Int {
        return Texts.indexOf(Values.textArg(text, 'string_index'), Values.textArg(needle, 'string_index'));
    }

    /**
     * Extracts a portion of a string starting at position `start` (0-based)
     * for `length` characters.
     *
     * `string_sub("ABCDEF", 0, 3)` returns `"ABC"`.
     * `string_sub("ABCDEF", 2, 3)` returns `"CDE"`.
     *
     * ```lor
     * code = "ABCDEF"
     * prefix = string_sub(code, 0, 3)
     * // prefix is "ABC"
     * ```
     */
    public function string_sub(text:Any, start:Any, ?len:Any):String {
        final source = Values.textArg(text, 'string_sub');
        final from = Std.int(Math.ffloor(Values.numberArg(start, 'string_sub')));
        if (len == null) return Texts.sub(source, from);
        return Texts.sub(source, from, Std.int(Math.ffloor(Values.numberArg(len, 'string_sub'))));
    }

    /**
     * Checks if a string begins with the given prefix.
     *
     * `string_starts("hello world", "hello")` returns `true`.
     *
     * ```lor
     * if string_starts(name, "Sir")
     *   You bow before the knight.
     * ```
     */
    public function string_starts(text:Any, prefix:Any):Bool {
        return StringTools.startsWith(Values.textArg(text, 'string_starts'), Values.textArg(prefix, 'string_starts'));
    }

    /**
     * Checks if a string ends with the given suffix.
     *
     * `string_ends("hello world", "world")` returns `true`.
     *
     * ```lor
     * if string_ends(reply, "?")
     *   It sounds like a question.
     * ```
     */
    public function string_ends(text:Any, suffix:Any):Bool {
        return StringTools.endsWith(Values.textArg(text, 'string_ends'), Values.textArg(suffix, 'string_ends'));
    }

    /**
     * Repeats the text the given number of times.
     *
     * `string_repeat("ab", 3)` returns `"ababab"`.
     *
     * ```lor
     * divider = string_repeat("-", 20)
     * // divider is "--------------------"
     * ```
     */
    public function string_repeat(text:Any, count:Any):String {
        final source = Values.textArg(text, 'string_repeat');
        final times = Math.ffloor(Values.numberArg(count, 'string_repeat'));
        var result = new StringBuf();
        var i = 0;
        while (i < times) {
            result.add(source);
            i++;
        }
        return result.toString();
    }

    // -- Text ----------------------------------------------------------

    /**
     * Returns `singular` when count is 1, `plural_form` otherwise.
     * Useful for both noun plurals and verb conjugation. The writer provides
     * both forms, so this works in any language.
     *
     * ```lor
     * items = 3
     * You found $items $plural(items, "coin", "coins").
     * // "You found 3 coins."
     *
     * boxes = 1
     * There $plural(boxes, "is", "are") $boxes $plural(boxes, "box", "boxes") here.
     * // "There is 1 box here."
     * ```
     */
    public function plural(count:Any, singular:Any, plural_form:Any):String {
        // Only the number one, or a text written as it, picks the singular:
        // any other value, a name included (`$name thing|things`), the plural
        final one = !(count is Bool) && Values.equals(count, 1);
        return one ? Values.textArg(singular, 'plural') : Values.textArg(plural_form, 'plural');
    }

    // -- Array ---------------------------------------------------------

    /**
     * Returns the number of elements in an array.
     *
     * ```lor
     * items = [1, 2, 3]
     * You carry $array_length(items) items.
     * ```
     */
    public function array_length(array:Any):Int {
        if (Arrays.isArray(array)) return Arrays.arrayLength(array);
        return 0;
    }

    /**
     * Adds an element to the end of an array.
     *
     * ```lor
     * items = ["sword", "shield"]
     * array_add(items, "potion")
     * // items is now ["sword", "shield", "potion"]
     * ```
     */
    public function array_add(array:Any, value:Any):Dynamic {
        if (Arrays.isArray(array)) {
            Arrays.arrayPush(array, value);
        }
        return null;
    }

    /**
     * Removes the last element from an array and returns it.
     * Returns `null` if the array is empty.
     *
     * ```lor
     * last = array_pop(items)
     * You drop the $last.
     * ```
     */
    public function array_pop(array:Any):Dynamic {
        if (Arrays.isArray(array)) {
            return Arrays.arrayPop(array);
        }
        return null;
    }

    /**
     * Adds an element to the beginning of an array.
     *
     * ```lor
     * queue = ["Bob", "Carol"]
     * array_prepend(queue, "Alice")
     * // queue is now ["Alice", "Bob", "Carol"]
     * ```
     */
    public function array_prepend(array:Any, value:Any):Dynamic {
        if (Arrays.isArray(array)) {
            Arrays.arrayInsert(array, 0, value);
        }
        return null;
    }

    /**
     * Removes the first element from an array and returns it.
     * Returns `null` if the array is empty.
     *
     * ```lor
     * next_in_line = array_shift(queue)
     * $next_in_line steps forward.
     * ```
     */
    public function array_shift(array:Any):Dynamic {
        if (Arrays.isArray(array)) {
            return Arrays.arrayShift(array);
        }
        return null;
    }

    /**
     * Finds and removes the first occurrence of a value from an array.
     * Returns `true` if the value was found and removed, `false` if not found.
     * Values compare like with `==`.
     *
     * ```lor
     * array_remove(inventory, "old key")
     * The old key crumbles to dust.
     * ```
     */
    public function array_remove(array:Any, value:Any):Bool {
        if (Arrays.isArray(array)) {
            final len = Arrays.arrayLength(array);
            for (i in 0...len) {
                if (Values.equals(Arrays.arrayGet(array, i), value)) {
                    Arrays.arrayRemoveAt(array, i);
                    return true;
                }
            }
        }
        return false;
    }

    /**
     * Finds the position of a value in an array (starting from `0`).
     * Returns `-1` if the value is not in the array.
     * Values compare like with `==`.
     *
     * ```lor
     * pos = array_index(suspects, "Butler")
     * ```
     */
    public function array_index(array:Any, value:Any):Int {
        if (Arrays.isArray(array)) {
            final len = Arrays.arrayLength(array);
            for (i in 0...len) {
                if (Values.equals(Arrays.arrayGet(array, i), value)) {
                    return i;
                }
            }
        }
        return -1;
    }

    /**
     * Checks if an array contains a given value.
     * Values compare like with `==`.
     *
     * ```lor
     * if array_has(inventory, "golden key")
     *   You unlock the ancient door.
     * else
     *   The door won't budge without the right key.
     * ```
     */
    public function array_has(array:Any, value:Any):Bool {
        if (Arrays.isArray(array)) {
            final len = Arrays.arrayLength(array);
            for (i in 0...len) {
                if (Values.equals(Arrays.arrayGet(array, i), value)) {
                    return true;
                }
            }
        }
        return false;
    }

    /**
     * Sorts the array in place and returns it.
     * Numbers come first, from smallest to largest, then texts in alphabetical
     * order, then any other value in its original order.
     *
     * ```lor
     * scores = [30, 10, 20]
     * array_sort(scores)
     * // scores is now [10, 20, 30]
     * ```
     */
    public function array_sort(array:Any):Dynamic {
        if (Arrays.isArray(array)) {
            // Each value is sorted with its original position, which settles the
            // ties: the order is the same whether the sort of the target is
            // stable or not
            final length = Arrays.arrayLength(array);
            final entries:Array<SortEntry> = [];
            for (i in 0...length) {
                final value:Any = Arrays.arrayGet(array, i);
                final type = Type.typeof(value);
                final rank = switch type {
                    case TInt | TFloat: 0;
                    case _: (value is String) ? 1 : 2;
                }
                entries.push({
                    value: value,
                    rank: rank,
                    number: rank == 0 ? Values.numberOf(value, type) : 0.0,
                    index: i
                });
            }
            entries.sort((a, b) -> {
                if (a.rank != b.rank) return a.rank < b.rank ? -1 : 1;
                if (a.rank == 0) {
                    if (a.number < b.number) return -1;
                    if (a.number > b.number) return 1;
                }
                if (a.rank == 1) {
                    final textA:String = a.value;
                    final textB:String = b.value;
                    if (textA != textB) return textA < textB ? -1 : 1;
                }
                return a.index < b.index ? -1 : (a.index > b.index ? 1 : 0);
            });
            for (i in 0...length) {
                Arrays.arraySet(array, i, entries[i].value);
            }
        }
        return array;
    }

    /**
     * Reverses the array in place and returns it.
     *
     * ```lor
     * steps = ["first", "second", "third"]
     * array_reverse(steps)
     * // steps is now ["third", "second", "first"]
     * ```
     */
    public function array_reverse(array:Any):Dynamic {
        if (Arrays.isArray(array)) {
            Arrays.arrayReverse(array);
        }
        return array;
    }

    /**
     * Combines all elements of an array into a single string, placing a separator
     * between each element.
     *
     * `array_join(["a", "b", "c"], ", ")` returns `"a, b, c"`.
     *
     * ```lor
     * guests = ["Alice", "Bob", "Carol"]
     * The guests are: $array_join(guests, ", ").
     * ```
     */
    public function array_join(array:Any, sep:Any):String {
        if (Arrays.isArray(array)) {
            final separator = Values.textArg(sep, 'array_join');
            final buf = new StringBuf();
            for (i in 0...Arrays.arrayLength(array)) {
                if (i > 0) buf.add(separator);
                buf.add(Values.textOf(Arrays.arrayGet(array, i), interpreter));
            }
            return buf.toString();
        }
        return "";
    }

    /**
     * Returns a random element from an array. Returns `null` if the array is empty.
     * Affected by `seed_random`.
     *
     * ```lor
     * greetings = ["Hello!", "Hey there!", "Welcome!"]
     * barista: $array_pick(greetings)
     * ```
     */
    public function array_pick(array:Any):Dynamic {
        if (Arrays.isArray(array)) {
            final len = Arrays.arrayLength(array);
            if (len == 0) return null;
            final idx = Math.floor(rng() * len);
            return Arrays.arrayGet(array, idx);
        }
        return null;
    }

    /**
     * Shuffles the array in place and returns it.
     * Affected by `seed_random`.
     *
     * ```lor
     * deck = ["Ace", "King", "Queen", "Jack"]
     * array_shuffle(deck)
     * You draw the $deck[0].
     * ```
     */
    public function array_shuffle(array:Any):Dynamic {
        if (Arrays.isArray(array)) {
            // Fisher-Yates shuffle
            var i = Arrays.arrayLength(array) - 1;
            while (i > 0) {
                final j = Math.floor(rng() * (i + 1));
                final tmp = Arrays.arrayGet(array, i);
                Arrays.arraySet(array, i, Arrays.arrayGet(array, j));
                Arrays.arraySet(array, j, tmp);
                i--;
            }
        }
        return array;
    }

    /**
     * Returns a shallow copy of the array.
     *
     * ```lor
     * original = [1, 2, 3]
     * backup = array_copy(original)
     * array_sort(original)
     * // original is now [1, 2, 3] sorted, backup is unchanged
     * ```
     */
    public function array_copy(array:Any):Dynamic {
        if (Arrays.isArray(array)) {
            return Arrays.arrayCopy(array);
        }
        return array;
    }

    // -- Map -----------------------------------------------------------

    /**
     * Returns the number of keys in a map.
     *
     * ```lor
     * state
     *   stats: { strength: 10, agility: 8 }
     * The map has $map_length(stats) entries.
     * ```
     */
    public function map_length(map:Any):Int {
        if (!Objects.isFields(map)) return 0;
        return Objects.getFields(interpreter, map).length;
    }

    /**
     * Returns an array containing all the keys of a map.
     *
     * ```lor
     * state
     *   stats: { strength: 10, agility: 8 }
     * all_stats = map_keys(stats)
     * // all_stats is ["strength", "agility"]
     * ```
     */
    public function map_keys(map:Any):Array<String> {
        if (!Objects.isFields(map)) return [];
        final fields = Objects.getFields(interpreter, map);
        fields.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
        return fields;
    }

    /**
     * Checks if a map contains a given key.
     *
     * ```lor
     * if map_has(inventory_counts, "potion")
     *   You have potions available.
     * ```
     */
    public function map_has(map:Any, key:Any):Bool {
        if (!Objects.isFields(map)) return false;
        return Objects.fieldExists(interpreter, map, Values.textArg(key, 'map_has'));
    }

    /**
     * Gets the value stored under a key in a map.
     * Returns `null` if the key doesn't exist.
     *
     * ```lor
     * count = map_get(inventory_counts, "arrows")
     * You have $count arrows left.
     * ```
     */
    public function map_get(map:Any, key:Any):Dynamic {
        if (!Objects.isFields(map)) return null;
        return Objects.getField(interpreter, map, Values.textArg(key, 'map_get'));
    }

    /**
     * Stores a value under a key in a map. Overwrites any previous value for that key.
     *
     * ```lor
     * map_set(inventory_counts, "arrows", 20)
     * ```
     */
    public function map_set(map:Any, key:Any, value:Any):Dynamic {
        if (Objects.isFields(map)) {
            Objects.setField(interpreter, map, Values.textArg(key, 'map_set'), value);
        }
        return null;
    }

    /**
     * Removes a key and its value from a map.
     * Returns `true` if the key was found and removed, `false` otherwise.
     *
     * ```lor
     * map_remove(inventory_counts, "broken_sword")
     * You discard the broken sword.
     * ```
     */
    public function map_remove(map:Any, key:Any):Bool {
        if (!Objects.isFields(map)) return false;
        final name = Values.textArg(key, 'map_remove');
        if (Objects.fieldExists(interpreter, map, name)) {
            return Objects.removeField(interpreter, map, name);
        }
        return false;
    }

    /**
     * Returns a shallow copy of a map.
     *
     * ```lor
     * state
     *   stats: { strength: 10, agility: 8 }
     * backup = map_copy(stats)
     * map_set(stats, "strength", 20)
     * // stats.strength is 20, backup.strength is still 10
     * ```
     */
    public function map_copy(map:Any):Dynamic {
        if (!Objects.isFields(map)) return null;
        final keys = Objects.getFields(interpreter, map);
        final copy = Objects.createFields(interpreter);
        for (key in keys) {
            Objects.setField(interpreter, copy, key, Objects.getField(interpreter, map, key));
        }
        return copy;
    }

    // -- Game State ----------------------------------------------------

    /**
     * Returns the name of the beat that is currently running.
     *
     * ```lor
     * beat TavernScene
     *   where = current_beat()
     *   // where is "TavernScene"
     * ```
     */
    public function current_beat():Dynamic {
        @:privateAccess var i = interpreter.stack.length - 1;
        while (i >= 0) {
            @:privateAccess final scope = interpreter.stack[i];
            if (scope.beat != null) {
                return scope.beat;
            }
            i--;
        }
        return null;
    }

    /**
     * Checks whether a beat with the given name exists and can be reached from
     * where you are. This includes nested beats defined inside the current beat
     * or any of its parent beats, as well as all top-level beats.
     *
     * ```lor
     * if has_beat("SecretEnding")
     *   choice
     *     Try the secret path -> SecretEnding
     * ```
     */
    public function has_beat(name:Any):Bool {
        if (RuntimeBeatRef.beatOf(name) != null) return true; // reachable, we resolved it
        final nameStr:String = cast name;
        // Walk the stack bottom-up, scanning each scope's beat body for nested beat declarations
        @:privateAccess var i = interpreter.stack.length - 1;
        while (i >= 0) {
            @:privateAccess final scope = interpreter.stack[i];
            if (scope.beat != null && scope.beat.body != null) {
                for (node in scope.beat.body) {
                    if (node is NBeatDecl) {
                        final beatDecl:NBeatDecl = cast node;
                        if (beatDecl.name == nameStr) {
                            return true;
                        }
                    }
                }
            }
            i--;
        }
        // Fall back to top-level beats
        @:privateAccess return interpreter.topLevelBeats.exists(nameStr);
    }

    /**
     * Returns how many times a beat has been entered.
     *
     * `beat_visits()` returns the visit count of the current beat.
     * `beat_visits("BeatName")` or `beat_visits(BeatName)` returns the visit count of the named beat.
     * `BeatName.visits()` is also supported via dot notation.
     *
     * ```lor
     * if beat_visits() == 1
     *   First time here
     * else
     *   You've been here before
     *
     * if beat_visits(Dungeon) >= 3
     *   You know this place well now
     * ```
     */
    public function beat_visits(?name:Any):Int {
        if (name == null) {
            // Current beat: find innermost beat scope on the stack
            @:privateAccess var i = interpreter.stack.length - 1;
            while (i >= 0) {
                @:privateAccess final scope = interpreter.stack[i];
                if (scope.beat != null) {
                    @:privateAccess return interpreter.getBeatVisitCount(scope.beat);
                }
                i--;
            }
            return 0;
        } else if (RuntimeBeatRef.beatOf(name) != null) {
            // Beat value or beat reference (from bareword or dot notation)
            @:privateAccess return interpreter.getBeatVisitCount(RuntimeBeatRef.beatOf(name));
        } else {
            // Named beat string: use scope-aware lookup
            @:privateAccess final beat = interpreter.resolveBeatByName(cast name);
            if (beat == null) return 0;
            @:privateAccess return interpreter.getBeatVisitCount(beat);
        }
    }

    // -- Choice introspection -------------------------------------------

    /**
     * Returns an array of text strings for all **enabled** choice options
     * evaluated so far (during option condition evaluation) or all enabled
     * options (inside the chosen option's body).
     *
     * Returns a new array each time (safe to modify in scripts).
     * Returns an empty array outside of a choice context.
     *
     * ```lor
     * choice
     *   - Ask about menu
     *   - Ask about specials
     *   Say something if !choices()
     * ```
     */
    public function choices():Array<Any> {
        @:privateAccess final texts = interpreter._choiceEvalTexts;
        @:privateAccess final enabled = interpreter._choiceEvalEnabled;
        final result:Array<Any> = [];
        for (i in 0...texts.length) {
            if (enabled[i]) result.push(texts[i]);
        }
        return result;
    }

    /**
     * Returns an array of text strings for all **disabled** choice options
     * evaluated so far (during option condition evaluation) or all disabled
     * options (inside the chosen option's body).
     *
     * Returns a new array each time (safe to modify in scripts).
     * Returns an empty array outside of a choice context.
     *
     * ```lor
     * choice
     *   Option A if someCondition
     *   Option B if array_length(choices_disabled()) > 0
     * ```
     */
    public function choices_disabled():Array<Any> {
        @:privateAccess final texts = interpreter._choiceEvalTexts;
        @:privateAccess final enabled = interpreter._choiceEvalEnabled;
        final result:Array<Any> = [];
        for (i in 0...texts.length) {
            if (!enabled[i]) result.push(texts[i]);
        }
        return result;
    }

    /**
     * Returns an array of text strings for **all** choice options evaluated
     * so far, in original order, regardless of enabled/disabled state.
     *
     * Returns a new array each time (safe to modify in scripts).
     * Returns an empty array outside of a choice context.
     *
     * ```lor
     * choice
     *   Option A
     *   Option B if array_length(choices_all()) > 0
     * ```
     */
    public function choices_all():Array<Any> {
        @:privateAccess final texts = interpreter._choiceEvalTexts;
        final result:Array<Any> = [];
        for (i in 0...texts.length) {
            result.push(texts[i]);
        }
        return result;
    }
}

/**
 * A value of an array being sorted by array_sort: its rank (0 for a number,
 * 1 for a text, 2 for anything else), its number, and its original position.
 */
private typedef SortEntry = {
    value:Any,
    rank:Int,
    number:Float,
    index:Int
}
