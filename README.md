# Loreline

Loreline is an open-source scripting language for writing interactive fictions.

Here's a most basic example of Loreline script:

```lor
The warm aroma of coffee fills the café.

barista: Hi there! How are you doing today?

choice {
    Having a great day {
        barista: Wonderful! Coffee will make it even better.
    }

    Need caffeine... {
        barista: Say no more! Let me help with that.
    }

    Your name is Alex, right? {
        barista: Oh, I didn't expect you'd remember it!
    }
}
```

Even if you've never seen such script before, you can probably understand what it does: it describes a scene in a café and gives the player choices that lead to different outcomes.

# Core concepts

Let's explore how Loreline helps you create interactive stories. We'll start with the basic building blocks and gradually build up to more complex features.

## Story structure and beats

Although you can write right at the beginning of a Loreline script, as your story becomes more complex, you'll want to organize it better. That's where Loreline "beats" come into play - sections that contain related scenes or moments. Think of beats as chapters or scenes in your story:

```lor
beat EnterCafe {
    The morning sun streams through the café windows.
    The aroma of freshly ground coffee fills the air.

    choice {
        Approach the counter {
            -> PlaceOrder
        }

        Look around first {
            -> ExploreSpace
        }
    }
}

beat ExploreSpace {
    A cozy seating area invites you to stay awhile.
    Students and remote workers tap away at their laptops.

    choice {
        Head to the counter {
            -> PlaceOrder
        }

        Leave for now {
            -> ExitCafe
        }
    }
}

beat PlaceOrder {
    The display case of pastries catches your eye as you approach.

    choice {
        Order coffee {
            -> CoffeeOptions
        }

        Order tea {
            -> TeaOptions
        }

        Step back {
            -> ExploreSpace
        }
    }
}
```

The arrow syntax (`->`) lets you move between beats, creating a branching storyline. Each beat can have its own narrative flow, choices, and consequences.

## Characters and dialogue

When writing dialogue, you can define your characters along with their properties:

```lor
character barista {
    name: Alex
    friendship: 0    // Track relationship with player
    shiftStarted: true
}

character customer {
    name: "Sam"
    visits: 0
    favoriteDrink: null
}
```

Once defined, characters can speak using a simple syntax - their identifier, followed by a colon:

```lor
barista: Welcome to Coffee Dreams! What can I get you today?
customer: Just a regular coffee, please.
barista: Coming right up!
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
state {
    coffeeBeans: 100   // Track inventory
    rushHour: false    // Is it busy?
    dayNumber: 1       // Which day of the story
}
```

You can change these values as your story progresses:

```lor
coffeeBeans -= 10    // Use some beans
rushHour = true      // Start rush hour
dayNumber += 1       // Move to next day
```

### Temporary state

Sometimes you want state that only exists within a specific beat. Use the `new` keyword to create temporary state that resets each time you enter the beat:

```lor
beat CoffeeTasting {
    // These values reset every time we enter CoffeeTasting
    new state {
        cupsTasted: 0
        currentRoast: "light"
        enjoymentLevel: 5
    }

    choice {
        Try another sip if (cupsTasted < 3) {
            cupsTasted += 1
            "Interesting notes in this one..."
        }

        Finish tasting {
            -> OrderDrink
        }
    }
}
```

In this example, `cupsTasted`, `currentRoast`, and `enjoymentLevel` reset to their initial values every time the player enters the CoffeeTasting beat.

## Making choices interactive

The heart of interactive fiction is letting readers make choices:

```lor
beat OrderDrink {
    choice {
        Order a cappuccino {
            coffeeBeans -= 15
            barista: <happy> One cappuccino coming right up!
            -> PrepareDrink
        }

        Ask about tea options {
            barista: We have a lovely selection of green and herbal teas.
            -> TeaMenu
        }

        Just browse the menu {
            You take your time reading through the extensive drink list.
            -> DrinkMenu
        }
    }
}
```

Choices can be conditional - only available when certain conditions are met:

```lor
beat SpecialMenu {
    choice {
        Order special roast if (coffeeBeans >= 20) {
            coffeeBeans -= 20
            barista: Excellent choice! Our Ethiopian blend is amazing.
            -> PrepareDrink
        }

        Chat with barista if (barista.friendship > 2) {
            barista: <friendly> Want to hear about my coffee journey?
            -> BaristaChat
        }
    }
}
```

## Dynamic text

Make your text responsive to the game state using the `$` symbol for variable interpolation:

```lor
beat CheckInventory {
    barista: We have $coffeeBeans beans left in stock.
    Your total comes to ${price * quantity} dollars.
}
```

Characters can also be referenced by their name property:

```lor
beat CloseShop {
    $barista begins cleaning up for the day.    // Will show "Alex begins cleaning up for the day"
    $customer waves goodbye as they leave.      // Will show "Sam waves goodbye as they leave"
}
```

## Comments and organization

Keep your script organized with comments:

```lor
// Track customer loyalty
customer.visits += 1

/* Check if we should
   trigger the special event */
if (customer.visits > 10) {
    -> LoyaltyReward
}
```

## Advanced features

Here's a complex example putting multiple features together:

```lor
beat CoffeeTasting {
    new state {
        cupsTasted: 0
        favoriteRoast: null
        lastImpression: ""
    }

    barista: <enthusiastic> Ready to explore our new roasts?

    choice {
        Try light roast if (cupsTasted < 3) {
            cupsTasted += 1
            lastImpression = "bright and citrusy"

            The bright, citrusy notes dance on your tongue.

            if (chance(3)) { // 1 in 3 chance
                favoriteRoast = "light"
                barista: <happy> I see that spark in your eyes!
                -> DiscussTaste
            }
        }

        Try medium roast if (cupsTasted < 3) {
            cupsTasted += 1
            lastImpression = "nutty and balanced"

            A pleasant nuttiness fills your mouth.
            -> DiscussTaste
        }

        Discuss coffee origins if (barista.friendship > 1) {
            barista: <passionate> Let me tell you about our farmers...
            -> CoffeeOrigins
        }

        Finish tasting if (cupsTasted > 0) {
            if (favoriteRoast != null) {
                -> OrderFavorite
            }
            else {
                -> RegularOrder
            }
        }
    }
}

beat DiscussTaste {
    barista: What do you think about the $lastImpression notes?

    choice {
        Express enthusiasm {
            barista.friendship += 1
            -> CoffeeTasting
        }

        Nod politely {
            -> CoffeeTasting
        }
    }
}
```

This syntax guide covered the main features of Loreline, but there's always more to discover as you write your own stories. Experiment with different combinations of these features to create rich narratives.

Happy writing!

# Write and play Loreline scripts

Loreline scripts are written in `.lor` files. See [CoffeeShop.lor](/test/CoffeeShop.lor) and [Minimal.lor](/test/Minimal.lor) as examples.

You can write these with any text editor, but the best option is using [Visual Studio Code](https://code.visualstudio.com/) along with the [Loreline Extension](https://marketplace.visualstudio.com/items?itemName=jeremyfa.loreline). This will make your editor support syntax highlighting of `.lor` files, which makes the content much more readable and easy to work with:

![Minimal example, syntax highlighted in VSCode](/minimal-screenshot.png)

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
    (_, character, text, tag, done) -> {
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
