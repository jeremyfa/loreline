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

    var _random:Random = null;

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
        target.set("random_float", this.random_float);
        // Timing
        target.set("wait", this.wait);
        // Type conversion
        target.set("float", this.float_);
        target.set("string", this.string_);
        target.set("bool", this.bool);
        // Generic
        target.set("length", this.length);
        // String
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
        target.set("map_keys", this.map_keys);
        target.set("map_has", this.map_has);
        target.set("map_get", this.map_get);
        target.set("map_set", this.map_set);
        target.set("map_remove", this.map_remove);
        target.set("map_copy", this.map_copy);
        // Game state
        target.set("current_beat", this.current_beat);
        target.set("has_beat", this.has_beat);
    }

    // ── Private helper ────────────────────────────────────────────────

    function rng():Float {
        if (_random == null) {
            _random = new Random();
        }
        return _random.next();
    }

    // ── Math ──────────────────────────────────────────────────────────

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
    public function floor(n:Float):Int {
        return Math.floor(n);
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
    public function ceil(n:Float):Int {
        return Math.ceil(n);
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
    public function round(n:Float):Int {
        return Math.round(n);
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
    public function abs(n:Float):Float {
        return Math.abs(n);
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
    public function min(a:Float, b:Float):Float {
        return Math.min(a, b);
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
    public function max(a:Float, b:Float):Float {
        return Math.max(a, b);
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
    public function clamp(v:Float, lo:Float, hi:Float):Float {
        return Math.max(lo, Math.min(hi, v));
    }

    /**
     * Raises a number to the given power.
     *
     * `pow(2, 3)` returns `8` (2 × 2 × 2). `pow(9, 0.5)` returns `3` (square root).
     *
     * ```lor
     * area = pow(side_length, 2)
     * The room is $area square meters.
     * ```
     */
    public function pow(base:Float, exp:Float):Float {
        return Math.pow(base, exp);
    }

    // ── Random ────────────────────────────────────────────────────────

    /**
     * Returns a random whole number between min and max, including both ends.
     *
     * ```lor
     * roll = random(1, 6)
     * You rolled a $roll!
     * ```
     */
    public function random(min:Int, max:Int):Int {
        return Math.floor(min + rng() * (max + 1 - min));
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
    public function chance(n:Int):Bool {
        return Math.floor(rng() * n) == 0;
    }

    /**
     * Sets the random seed so that all future random results follow a predictable
     * sequence. Calling `seed_random` with the same value always produces the same
     * results for `random`, `chance`, `random_float`, `array_pick`, and `array_shuffle`.
     *
     * ```lor
     * seed_random(42)
     * // From here, the sequence of random values is always the same.
     * ```
     */
    public function seed_random(seed:Float):Dynamic {
        _random = new Random(seed);
        return null;
    }

    /**
     * Returns a random decimal number from `min` up to (but not including) `max`.
     *
     * `random_float(0, 1)` might return `0.7341...`.
     *
     * ```lor
     * temperature = round(random_float(15, 30))
     * It's $temperature degrees outside today.
     * ```
     */
    public function random_float(min:Float, max:Float):Float {
        return min + rng() * (max - min);
    }

    // ── Timing ────────────────────────────────────────────────────────

    /**
     * Pauses the script for the given number of seconds before continuing.
     *
     * ```lor
     * The ground begins to shake...
     * wait(2)
     * A massive boulder crashes through the wall!
     * ```
     */
    public function wait(seconds:Float):Async {
        return new Async(done -> {
            #if sys
            Sys.sleep(seconds);
            done();
            #else
            done();
            #end
        });
    }

    // ── Type Conversion ───────────────────────────────────────────────

    /**
     * Converts a value to a number. Strings like `"3.14"` are parsed;
     * `true` becomes `1`, `false` becomes `0`. Returns `0` if conversion fails.
     *
     * ```lor
     * price = float("9.99")
     * ```
     */
    @:keep public function float_(value:Any):Dynamic {
        if (value is Float) return (value : Float);
        if (value is Int) return (value : Int) * 1.0;
        if (value is String) return Std.parseFloat(cast value);
        if (value is Bool) return (value : Bool) ? 1.0 : 0.0;
        return 0.0;
    }

    /**
     * Converts any value to text.
     *
     * ```lor
     * label = string(42)   // "42"
     * ```
     */
    @:keep public function string_(value:Any):Dynamic {
        if (value == null) return "null";
        if (value is String) return (value : String);
        return Std.string(value);
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
        if (value is Bool) return (value : Bool);
        if (value is String) return (value : String).length > 0;
        if (value is Array) return (value : Array<Any>).length > 0;
        if (value is Int) return (value : Int) != 0;
        if (value is Float) return (value : Float) != 0;
        return value != null;
    }

    // ── Generic ───────────────────────────────────────────────────────

    /**
     * Returns the number of characters in a string, or the number of elements
     * in an array.
     *
     * ```lor
     * name = "Alice"
     * items = [1, 2, 3]
     * Your name has $length(name) letters and you carry $length(items) items.
     * ```
     */
    public function length(value:Any):Int {
        if (value is String) return (value : String).length;
        if (Arrays.isArray(value)) return Arrays.arrayLength(value);
        return 0;
    }

    // ── String ────────────────────────────────────────────────────────

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
    public function string_upper(text:String):String {
        return text.toUpperCase();
    }

    /**
     * Converts all letters to lowercase.
     *
     * `string_lower("HELLO")` returns `"hello"`.
     */
    public function string_lower(text:String):String {
        return text.toLowerCase();
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
    public function string_contains(text:String, needle:String):Bool {
        return StringTools.contains(text, needle);
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
    public function string_replace(text:String, from:String, to:String):String {
        return StringTools.replace(text, from, to);
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
    public function string_split(text:String, sep:String):Array<String> {
        return text.split(sep);
    }

    /**
     * Removes any spaces or whitespace from the beginning and end of a string.
     *
     * `string_trim("  hello  ")` returns `"hello"`.
     */
    public function string_trim(text:String):String {
        return StringTools.trim(text);
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
    public function string_index(text:String, needle:String):Int {
        return text.indexOf(needle);
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
    public function string_sub(text:String, start:Any, len:Any):String {
        return text.substr(Std.int(start), Std.int(len));
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
    public function string_starts(text:String, prefix:String):Bool {
        return StringTools.startsWith(text, prefix);
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
    public function string_ends(text:String, suffix:String):Bool {
        return StringTools.endsWith(text, suffix);
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
    public function string_repeat(text:String, count:Int):String {
        var result = new StringBuf();
        var i = 0;
        while (i < count) {
            result.add(text);
            i++;
        }
        return result.toString();
    }

    // ── Text ──────────────────────────────────────────────────────────

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
    public function plural(count:Dynamic, singular:String, plural_form:String):String {
        var n:Float = 0;
        if (count is Int) n = (count : Int) * 1.0;
        else if (count is Float) n = (count : Float);
        return n == 1 ? singular : plural_form;
    }

    // ── Array ─────────────────────────────────────────────────────────

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
        Arrays.arrayPush(array, value);
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
                if (Arrays.arrayGet(array, i) == value) {
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
     *
     * ```lor
     * pos = array_index(suspects, "Butler")
     * ```
     */
    public function array_index(array:Any, value:Any):Int {
        if (Arrays.isArray(array)) {
            final len = Arrays.arrayLength(array);
            for (i in 0...len) {
                if (Arrays.arrayGet(array, i) == value) {
                    return i;
                }
            }
        }
        return -1;
    }

    /**
     * Checks if an array contains a given value.
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
                if (Arrays.arrayGet(array, i) == value) {
                    return true;
                }
            }
        }
        return false;
    }

    /**
     * Sorts the array in place and returns it.
     * Numbers are sorted from smallest to largest; other values are sorted
     * alphabetically.
     *
     * ```lor
     * scores = [30, 10, 20]
     * array_sort(scores)
     * // scores is now [10, 20, 30]
     * ```
     */
    public function array_sort(array:Any):Dynamic {
        if (Arrays.isArray(array)) {
            Arrays.arraySort(array, (a, b) -> {
                if (a is Float && b is Float) return (a : Float) < (b : Float) ? -1 : ((a : Float) > (b : Float) ? 1 : 0);
                if (a is Int && b is Int) return (a : Int) < (b : Int) ? -1 : ((a : Int) > (b : Int) ? 1 : 0);
                return Std.string(a) < Std.string(b) ? -1 : (Std.string(a) > Std.string(b) ? 1 : 0);
            });
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
    public function array_join(array:Any, sep:String):String {
        if (Arrays.isArray(array)) {
            return Arrays.arrayJoin(array, sep);
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

    // ── Map ───────────────────────────────────────────────────────────

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
        return Objects.getFields(interpreter, map);
    }

    /**
     * Checks if a map contains a given key.
     *
     * ```lor
     * if map_has(inventory_counts, "potion")
     *   You have potions available.
     * ```
     */
    public function map_has(map:Any, key:String):Bool {
        return Objects.fieldExists(interpreter, map, key);
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
    public function map_get(map:Any, key:String):Dynamic {
        return Objects.getField(interpreter, map, key);
    }

    /**
     * Stores a value under a key in a map. Overwrites any previous value for that key.
     *
     * ```lor
     * map_set(inventory_counts, "arrows", 20)
     * ```
     */
    public function map_set(map:Any, key:String, value:Any):Dynamic {
        Objects.setField(interpreter, map, key, value);
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
    public function map_remove(map:Any, key:String):Bool {
        if (Objects.fieldExists(interpreter, map, key)) {
            Objects.setField(interpreter, map, key, null);
            return true;
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
        final keys = Objects.getFields(interpreter, map);
        final copy = Objects.createFields(interpreter);
        for (key in keys) {
            Objects.setField(interpreter, copy, key, Objects.getField(interpreter, map, key));
        }
        return copy;
    }

    // ── Game State ────────────────────────────────────────────────────

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
                return scope.beat.name;
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
    public function has_beat(name:String):Bool {
        // Walk the stack bottom-up, scanning each scope's beat body for nested beat declarations
        @:privateAccess var i = interpreter.stack.length - 1;
        while (i >= 0) {
            @:privateAccess final scope = interpreter.stack[i];
            if (scope.beat != null && scope.beat.body != null) {
                for (node in scope.beat.body) {
                    if (node is NBeatDecl) {
                        final beatDecl:NBeatDecl = cast node;
                        if (beatDecl.name == name) {
                            return true;
                        }
                    }
                }
            }
            i--;
        }
        // Fall back to top-level beats
        @:privateAccess return interpreter.topLevelBeats.exists(name);
    }
}
