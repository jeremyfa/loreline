# Loreline

⚠️ _This project is not yet ready for production, consider this as a "preview" version. More to come soon!_

Loreline is an open-source scripting language for writing interactive fictions.

![Screenshot of the Loreline extension for VSCode](/vscode-screenshot.png)

Here's a most basic example of Loreline script:

```lor
The warm aroma of coffee fills the café.

barista: Hi there! How are you doing today?

choice
  Having a great day
    barista: Wonderful! Coffee will make it even better.

  Need caffeine...
    barista: Say no more! Let me help with that.

  Your name is Alex, right?
    barista: Oh, I didn't expect you'd remember it!
```

Even if you've never seen such script before, you can probably understand what it does: it describes a scene in a café and gives the player choices that lead to different outcomes.

# Core concepts

Let's explore how Loreline helps you create interactive stories. We'll start with the basic building blocks and gradually build up to more complex features.

## Story structure and beats

Although you can write right at the beginning of a Loreline script, as your story becomes more complex, you'll want to organize it better. That's where Loreline "beats" come into play - sections that contain related scenes or moments. Think of beats as chapters or scenes in your story:

```lor
beat EnterCafe
  The morning sun streams through the café windows as you step inside.

  barista: <friendly> Welcome! I don't think I've seen you here before.

  choice
    Just looking around
      barista: Take your time! I'm here when you're ready.
      -> ExploreMenu

    Actually, I could use some coffee
      barista: <happy> You're in the right place!
      -> TakeOrder

beat ExploreMenu
  Beside you, a regular customer sips her drink contentedly.

  sarah: Their lattes are amazing. I come here every morning.

  barista: <cheerful> Sarah's right! Want to try one?

  choice
    Sure, I'll have what she's having
      sarah: <pleased> Good choice!
      -> TakeOrder

    What else do you recommend?
      -> TakeOrder

beat TakeOrder
  barista: So, what can I get started for you?

  choice
    A latte sounds perfect
      barista: <excited> Coming right up! I'll make it special for your first visit.

      sarah: <smile> You won't regret it.
      -> EndVisit

    Just a regular coffee today
      barista: Sometimes the classics are the best choice!
      -> EndVisit

beat EndVisit
  You find a cozy spot to enjoy your drink.

  sarah: <friendly> Hope to see you around more often!
```

The arrow syntax (`->`) lets you move between beats, creating a branching storyline. Each beat can have its own narrative flow, choices, and consequences.

You can also end the story entirely using `-> .` (arrow to a dot):

```lor
beat EndVisit
  barista: Thanks for coming! See you next time.
  -> .
```

## Characters and dialogue

When writing dialogue, you can define your characters along with their properties:

```lor
character barista
  name: Alex
  friendship: 0  // Track relationship with player
  shiftStarted: true

character customer
  name: Sam
  visits: 0
  favoriteDrink: null
```

Once defined, characters can speak using a simple syntax - their identifier, followed by a colon:

```lor
barista: Welcome to Coffee Dreams! What can I get you today?
customer: Just a regular coffee, please.
barista: Coming right up!
```

Dialogue can also span multiple lines by placing the text on indented lines after the colon:

```lor
barista:
  Hey there, welcome to our cafe!
  Got a special brew for you today.
  Check out those limited edition Ethiopian coffee beans at the counter.
```

## Writing story text

In Loreline, you can write narrative text naturally, just as you would in a book. You don't need any special markers - just write:

```lor
The warm aroma of coffee fills the café. Sunlight streams through the windows, casting long shadows across the wooden floor.

A gentle murmur of conversation fills the space.
```

Tags enclosed in angle brackets (`<tag>`) can be used in any text - whether it's dialogue or narrative:

```lor
barista: <friendly> Welcome back! Your usual?
customer: <tired> Yes please, I really need it today.

The machine <whirs>hums to life</whirs> as steam <hiss>escapes with a sharp sound</hiss>.
```

These tags can be used to express character emotions or change how text is displayed, depending on what's possible in your game or application.

## Managing state

Interactive stories need to remember choices and track progress. Loreline uses state declarations for this. There are two types of state: persistent and temporary.

### Persistent state

Persistent state remains throughout your story:

```lor
state
  coffeeBeans: 100 // Track inventory
  rushHour: false  // Is it busy?
  dayNumber: 1     // Which day of the story
```

You can change these values as your story progresses:

```lor
coffeeBeans -= 10  // Use some beans
rushHour = true    // Start rush hour
dayNumber += 1     // Move to next day
```

State can also hold nested objects and arrays:

```lor
state
  menu:
    espresso: 3
    latte: 5
    cappuccino: 4
  dailySpecials: ["Ethiopian Roast", "Vanilla Cold Brew"]
```

### Beat-local state

You can declare state inside a beat. It persists across visits to the beat but is scoped to that beat, so it won't clash with a top-level variable of the same name:

```lor
state
  counter: 0  // Top-level counter

beat CoffeeShop
  state
    counter: 0  // Separate counter, local to this beat

  counter += 1
  barista: You've ordered $counter coffees in this shop!
```

### Temporary state

Sometimes you want state that only exists within a specific beat. Use the `new` keyword to create temporary state that resets each time you enter the beat:

```lor
beat CoffeeTasting
  // These values reset every time we enter CoffeeTasting
  new state
    cupsTasted: 0
    currentRoast: light
    enjoymentLevel: 5

  choice
    Try another sip if cupsTasted < 3
      cupsTasted += 1
      Interesting notes in this one...

    Finish tasting
      -> OrderDrink
```

In this example, `cupsTasted`, `currentRoast`, and `enjoymentLevel` reset to their initial values every time the player enters the CoffeeTasting beat.

## Making choices interactive

The heart of interactive fiction is letting readers make choices:

```lor
beat OrderDrink
  choice
    Order a cappuccino
      coffeeBeans -= 15
      barista: <happy> One cappuccino coming right up!
      -> PrepareDrink

    Ask about tea options
      barista: We have a lovely selection of green and herbal teas.
      -> TeaMenu

    Just browse the menu
      You take your time reading through the extensive drink list.
      -> DrinkMenu
```

Choices can be conditional - only available when certain conditions are met:

```lor
beat SpecialMenu
  choice
    Order special roast if coffeeBeans >= 20
      coffeeBeans -= 20
      barista: Excellent choice! Our Ethiopian blend is amazing.
      -> PrepareDrink

    Chat with barista if barista.friendship > 2
      barista: <friendly> Want to hear about my coffee journey?
      -> BaristaChat
```

When a choice simply transitions to another beat without any extra logic, you can write it on a single line:

```lor
choice
  Stay in the café -> CoffeeShop

  Call it a day -> EndDay

  Join $sarah if sarah.present -> SarahChat
```

Choices can also be nested. When a choice branch finishes without a `->` transition, execution continues after the choice block:

```lor
barista: What would you like?

choice
  A hot drink
    choice
      Espresso
        barista: One espresso, coming right up!
      Latte
        barista: Great choice! Milk preference?
        choice
          Oat milk
            barista: Our most popular option!
          Regular milk
            barista: Classic. Coming right up.

  A cold drink
    choice
      Iced coffee
        barista: Perfect for this weather!
      Lemonade
        barista: Fresh-squeezed, my favorite.

barista: I'll have that ready in just a moment.
```

The last line plays no matter which drink was chosen - all branches converge naturally after the outer choice block.

## Composing choices with insertions

As your story grows, you may want to reuse groups of choices across different beats. Choice insertions let you pull in choices from another beat using the `+` prefix:

```lor
beat CafeScene
  choice
    + SeasonalDrinks
    + RegularMenu
    Nothing for me, thanks
      barista: No worries, let me know if you change your mind.

beat SeasonalDrinks
  barista: Don't forget our seasonal specials!
  choice
    Hot spiced chocolate
      barista: A perfect choice for the season!
    Citrus tea
      barista: Excellent, it's our newest addition.

beat RegularMenu
  choice
    Espresso
      barista: One espresso, coming right up!
    Latte
      barista: Great choice!
```

When the player reaches the choice in `CafeScene`, they'll see the options from `SeasonalDrinks` and `RegularMenu` merged together with the "Nothing for me" option. Each inserted beat can also include dialogue that plays before its choices are shown.

## Calling beats as subroutines

You can call a beat like a function using parentheses. The called beat runs, and when it finishes, execution returns to where it was called:

```lor
character player
  name: null

beat Introspection
  if !player.name
    What is my name?
    ChooseName()
    -> Introspection
  else
    Oh, I remember, my name is $player.name!

beat ChooseName
  choice
    Alex
      player.name = "Alex"
    Sam
      player.name = "Sam"
    Jamie
      player.name = "Jamie"
```

Here, `ChooseName()` enters the `ChooseName` beat, lets the player pick a name, then returns to `Introspection` where execution continues.

## Dynamic text

Make your text responsive to the game state using the `$` symbol for variable interpolation:

```lor
barista: We have $coffeeBeans beans left in stock.
barista: That'll be ${coffeeBeans * 2} dollars for the lot!
```

Characters can also be referenced by their identifier, which will display their `name` property:

```lor
beat CloseShop
  $barista begins cleaning up for the day.  // Will show "Alex begins cleaning up for the day"
  $customer waves goodbye as they leave.    // Will show "Sam waves goodbye as they leave"
```

## Escaping special characters

Since `$` and `<` have special meaning in Loreline, you can escape them when you need the literal characters:

```lor
barista: That rare coffee is going to cost 9$$. Are you ok with that?
player: Damn, I only have 5\$ left...
```

Both `$$` and `\$` produce a literal `$` in the output.

You can also escape angle brackets to prevent them from being treated as tags:

```lor
That's a high \<price> tag :(
```

Use `\n` to insert a line break within a single line of dialogue:

```lor
player: Can I pay...\nthe rest...\ntomorrow?
```

This displays as three separate lines:

```
Can I pay...
the rest...
tomorrow?
```

If you need a literal `\n` in the output, escape the backslash with `\\n`.

## Functions

Loreline supports functions that can be called from expressions, text interpolation, or as standalone statements. A function is called by its name followed by parentheses. For example, `random` is a built-in function that returns a random number between two values:

```lor
barista: Your order will be ready in $random(2, 5) minutes!
// Will display a random number between 2 and 5
```

### Built-in functions

Loreline comes with a collection of built-in functions organized by category.

#### Math

- **`floor(n)`** — Rounds a number down to the nearest whole number. `floor(3.7)` returns `3`.
- **`ceil(n)`** — Rounds a number up to the nearest whole number. `ceil(3.2)` returns `4`.
- **`round(n)`** — Rounds a number to the nearest whole number. `round(3.5)` returns `4`.
- **`abs(n)`** — Returns the positive version of a number. `abs(-5)` returns `5`.
- **`min(a, b)`** — Returns the smaller of two values. `min(3, 7)` returns `3`.
- **`max(a, b)`** — Returns the larger of two values. `max(3, 7)` returns `7`.
- **`clamp(value, low, high)`** — Keeps a value within a range. `clamp(10, 0, 5)` returns `5`.
- **`pow(base, exp)`** — Raises a number to a power. `pow(2, 3)` returns `8`.

```lor
health = clamp(health + healing, 0, max_health)
damage = min(attack_power, enemy_health)
```

#### Random

- **`random(min, max)`** — Returns a random whole number between `min` and `max` (inclusive).
- **`chance(n)`** — Returns `true` with a 1-in-n probability. `chance(3)` has roughly a 33% chance of being true.
- **`seed_random(seed)`** — Sets the random seed for reproducible results. After calling this, all random functions produce the same sequence every time.
- **`random_float(min, max)`** — Returns a random decimal number from `min` up to (but not including) `max`.

```lor
roll = random(1, 6)
You rolled a $roll!

if chance(4)
  You find a rare gem on the ground!
```

#### Timing

- **`wait(seconds)`** — Pauses the script for the given number of seconds before continuing.

```lor
The ground begins to shake...
wait(2)
A massive boulder crashes through the wall!
```

#### Type conversion

- **`float(value)`** — Converts a value to a number. Strings like `"3.14"` are parsed. Returns `0` if conversion fails.
- **`string(value)`** — Converts any value to text. `string(42)` returns `"42"`.
- **`bool(value)`** — Converts a value to `true` or `false`. Zero, empty strings, empty arrays, and `null` are false; everything else is true.

#### Generic

- **`length(value)`** — Returns the number of characters in a string, or the number of elements in an array.

```lor
name = "Alice"
items = [1, 2, 3]
Your name has $length(name) letters and you carry $length(items) items.
```

#### Dot notation

All `string_`, `array_`, and `map_` functions can also be called using dot notation. Drop the prefix and call the function on the value directly — the first argument becomes the object before the dot, and the remaining arguments stay in parentheses:

| Function style | Dot notation |
|---|---|
| `string_upper(name)` | `name.upper()` |
| `string_contains(msg, "help")` | `msg.contains("help")` |
| `array_add(items, "sword")` | `items.add("sword")` |
| `array_join(items, ", ")` | `items.join(", ")` |
| `map_get(stats, "hp")` | `stats.get("hp")` |

This also works directly on literals and can be chained:

```lor
title = "hello".upper()
sorted = [3, 1, 2].sort().join(",")   // "1,2,3"
keys = { name: "Alice", age: 30 }.keys()
```

Both styles are equivalent — use whichever reads better in context.

#### String

These can also be called using [dot notation](#dot-notation) (e.g. `name.upper()`).

- **`string_upper(text)`** — Converts all letters to uppercase. `string_upper("hello")` returns `"HELLO"`.
- **`string_lower(text)`** — Converts all letters to lowercase. `string_lower("HELLO")` returns `"hello"`.
- **`string_contains(text, needle)`** — Checks if a string contains a piece of text. `string_contains("hello world", "world")` returns `true`.
- **`string_replace(text, from, to)`** — Replaces every occurrence of a piece of text. `string_replace("hello world", "world", "there")` returns `"hello there"`.
- **`string_split(text, separator)`** — Splits a string into an array. `string_split("a,b,c", ",")` returns `["a", "b", "c"]`.
- **`string_trim(text)`** — Removes whitespace from the beginning and end. `string_trim("  hello  ")` returns `"hello"`.
- **`string_index(text, needle)`** — Finds where a piece of text first appears (starting from `0`), or `-1` if not found. `string_index("hello", "ll")` returns `2`.
- **`string_sub(text, start, length)`** — Extracts a portion of a string. `string_sub("ABCDEF", 0, 3)` returns `"ABC"`.
- **`string_starts(text, prefix)`** — Checks if a string begins with the given prefix. `string_starts("hello world", "hello")` returns `true`.
- **`string_ends(text, suffix)`** — Checks if a string ends with the given suffix. `string_ends("hello world", "world")` returns `true`.
- **`string_repeat(text, count)`** — Repeats the text the given number of times. `string_repeat("ab", 3)` returns `"ababab"`.

```lor
if string_contains(message, "help")
  Someone needs assistance!

words = string_split(sentence, " ")
The sentence has $length(words) words.

if string_starts(name, "Sir")
  You bow before the knight.
```

#### Text

- **`plural(count, singular, plural)`** — Returns `singular` when count is 1, `plural` otherwise. Works for both noun plurals and verb conjugation in any language.

```lor
items = 3
You found $items $plural(items, "coin", "coins").
// "You found 3 coins."

boxes = 1
There $plural(boxes, "is", "are") $boxes $plural(boxes, "box", "boxes") here.
// "There is 1 box here."
```

#### Array

These can also be called using [dot notation](#dot-notation) (e.g. `items.add("sword")`).

- **`array_add(array, value)`** — Adds an element to the end of an array.
- **`array_pop(array)`** — Removes and returns the last element. Returns `null` if empty.
- **`array_prepend(array, value)`** — Adds an element to the beginning of an array.
- **`array_shift(array)`** — Removes and returns the first element. Returns `null` if empty.
- **`array_remove(array, value)`** — Finds and removes the first occurrence of a value. Returns `true` if found.
- **`array_index(array, value)`** — Finds the position of a value (starting from `0`), or `-1` if not found.
- **`array_has(array, value)`** — Checks if an array contains a given value.
- **`array_sort(array)`** — Sorts the array in place and returns it.
- **`array_reverse(array)`** — Reverses the array in place and returns it.
- **`array_join(array, separator)`** — Combines all elements into a string. `array_join(["a", "b", "c"], ", ")` returns `"a, b, c"`.
- **`array_pick(array)`** — Returns a random element. Affected by `seed_random`.
- **`array_shuffle(array)`** — Shuffles the array in place and returns it. Affected by `seed_random`.
- **`array_copy(array)`** — Returns a shallow copy of the array.

```lor
items = ["sword", "shield"]
array_add(items, "potion")

if array_has(inventory, "golden key")
  You unlock the ancient door.

greetings = ["Hello!", "Hey there!", "Welcome!"]
barista: $array_pick(greetings)
```

#### Map

These can also be called using [dot notation](#dot-notation) (e.g. `stats.get("hp")`).

- **`map_keys(map)`** — Returns an array of all keys in the map.
- **`map_has(map, key)`** — Checks if a key exists in the map.
- **`map_get(map, key)`** — Gets the value for a key. Returns `null` if the key doesn't exist.
- **`map_set(map, key, value)`** — Stores a value under a key.
- **`map_remove(map, key)`** — Removes a key and its value. Returns `true` if the key existed.
- **`map_copy(map)`** — Returns a shallow copy of the map.

```lor
map_set(inventory_counts, "arrows", 20)
count = map_get(inventory_counts, "arrows")
You have $count arrows left.
```

#### Story state

- **`current_beat()`** — Returns the name of the beat that is currently running.
- **`has_beat(name)`** — Checks whether a beat with the given name exists and can be reached from where you are. This includes nested beats and all top-level beats.

```lor
if has_beat("SecretEnding")
  choice
    Try the secret path -> SecretEnding
```

### Defining your own functions

You can define your own functions outside of beats. A function has a name, optional parameters, and a body written in a general-purpose scripting syntax:

```lor
function add(a, b)
  return a + b

state
  apples: 7
  oranges: 3

We have $apples apples and $oranges oranges, which makes a total of $add(apples, oranges) fruits!
```

Functions can access and modify state variables:

```lor
state
  fruits: 2

function getFruit()
  fruits = fruits + 1

You have $fruits fruits.

getFruit()

You have $fruits fruits.
```

Functions can use loops to build up results:

```lor
function enumerate(count, word)
  var result = ""
  for (i in 0...count)
    if i > 0
      result += ", "
    result += "$word ${i + 1}"
  return result

Here are all my items: $enumerate(3, "apple")
// Output: Here are all my items: apple 1, apple 2, apple 3
```

### External functions

You can also declare functions without a body. These act as hooks for your game engine or application - the script declares them, and the host environment provides the actual implementation:

```lor
function playExplosion()

sarah: What's this green diamond? Wait, let me touch it...
james: Nooo don't touch it!

playExplosion()

james: Sarah? Sarah!!
```

## Importing scripts

As your story grows, you can split it across multiple files using import statements:

```lor
import items
import characters/barista
import "scenes/intro.lor"
```

Imports load the contents of another `.lor` file into the current script. The `.lor` extension and quotes are optional - `import characters/barista` will look for `characters/barista.lor` in a `characters` subfolder.

## Alternative syntax: braces

Throughout this guide, all examples use indentation to define blocks. Loreline also supports curly braces as an alternative:

```lor
beat CoffeeShop {
  choice {
    Order espresso {
      barista: One espresso coming right up!
      -> ProcessOrder
    }

    Order latte if !rushHour {
      barista: Great choice! I'll make it extra foamy.
      -> ProcessOrder
    }

    Leave -> EndDay
  }
}
```

Both styles work everywhere blocks are used (beats, choices, state declarations, if/else). You can use whichever style you prefer, though indentation-based syntax tends to be more readable for narrative content.

## Comments and organization

Keep your script organized with comments:

```lor
// Track customer loyalty
customer.visits += 1

/* Check if we should
   trigger the special event */
if customer.visits > 10
  -> LoyaltyReward
```

## Advanced features

Here's a complex example putting multiple features together:

```lor
beat CoffeeTasting

  state
    cupsTasted: 0
    favoriteRoast: null
    lastImpression: ""

  barista: <enthusiastic> Ready to explore our new roasts?

  choice
    Try light roast if cupsTasted < 3
      cupsTasted += 1
      lastImpression = "bright and citrusy"

      The bright, citrusy notes dance on your tongue.

      if chance(3) // 1 in 3 chance
        favoriteRoast = light
        barista: <happy> I see that spark in your eyes!
        -> DiscussTaste

    Try medium roast if cupsTasted < 3
      cupsTasted += 1
      lastImpression = "nutty and balanced"

      A pleasant nuttiness fills your mouth.
      -> DiscussTaste

    Discuss coffee origins if barista.friendship > 1
      barista: <passionate> Let me tell you about our farmers...
      -> CoffeeOrigins

    Finish tasting if cupsTasted > 0
      if favoriteRoast != null
        -> OrderFavorite
      else
        -> RegularOrder

beat DiscussTaste
  barista: What do you think about the $lastImpression notes?

  choice
    Express enthusiasm
      barista.friendship += 1
      -> CoffeeTasting

    Nod politely
      -> CoffeeTasting
```

This syntax guide covered the main features of Loreline, but there's always more to discover as you write your own stories. Experiment with different combinations of these features to create rich narratives.

Happy writing!

# Write and play Loreline scripts

Loreline scripts are written in `.lor` files. See [CoffeeShop.lor](/test/CoffeeShop.lor) and [Minimal.lor](/test/Minimal.lor) as examples.

You can write these with any text editor, but the best option available for free is using [Visual Studio Code](https://code.visualstudio.com/) along with the [Loreline Extension](https://marketplace.visualstudio.com/items?itemName=jeremyfa.loreline). This will make your editor support syntax highlighting of `.lor` files, which makes the content much more readable and easy to work with:

![Screenshot of the Loreline extension for VSCode](/vscode-screenshot.png)

## Test using the command line interface

### Using official binary

A binary to run loreline can be downloaded for your platform in the [Releases page](https://github.com/jeremyfa/loreline/releases).

```bash
loreline play story.lor
```

### Using haxelib

Alternatively, you can use haxelib:

```bash
haxelib install loreline
```

```bash
haxelib run loreline play story.lor
```

## Embed loreline files in your game or application

Loreline runtime is written with the [Haxe programming language](https://haxe.org), so it can be transpiled to many target languages such as Javascript, C++, C#, Java bytecode, PHP, Python...

At the moment, it's still early days of this project, so you'll need to use Haxe if you want to integrate loreline in your code, although it is planned in the foreseeable future to make it work out of the box in more languages!

### Minimal haxe example

```haxe
// Load script content
final content = File.getContent('story.lor');

// Parse the script
final script = Loreline.parse(content);

// Play the story
Loreline.play(
  script,

  // Called to display a text
  (_, character, text, tags, done) -> {
    if (character != null) {
      Sys.println(character + ': ' + text);
    }
    else {
      Sys.println(text);
    }
    done(); // Call done() when finished
  },

  // Called to prompt a choice
  (_, options, callback) -> {
    for (i in 0...options.length) {
      Sys.println((i + 1) + '. ' + options[i].text);
    }

    // Let the user make a choice
    final choice:Int = ...;
    callback(choice); // Call back with the choice index
  },

  // Called when the execution has finished
  _ -> {
    // Finished script execution
  }
);
```

You can also take a look at [Cli.hx](/cli/loreline/Cli.hx) source code as another reference using Loreline.

## License

MIT License

Copyright (c) 2025 Jérémy Faivre

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
