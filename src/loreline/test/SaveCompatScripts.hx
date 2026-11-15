package loreline.test;

import loreline.Interpreter;
import loreline.Loreline;
import loreline.Script;

/**
 * Scripts of SaveCompatTests and the runs that make and restore their saves. Kept
 * apart from the tests so the recorder of SaveCompatData can be built with the
 * code of before a change of the save format or of the maps behind it.
 */
@:keep
class SaveCompatScripts {

    /** Output of a run, one line per dialogue or choice. */
    static function transcript(lines:Array<String>, options:Array<ChoiceOption>):Void {
        for (option in options) lines.push((option.enabled ? '+ ' : '- ') + option.text);
    }

    /**
     * Plays the script, answering with `choices`, and calls `onSave` with the save
     * made when the choice of index `saveAt` is presented, before answering it.
     */
    public static function playAndSave(script:Script, choices:Array<Int>, saveAt:Int, onSave:(saveJson:String)->Void):Array<String> {
        final lines:Array<String> = [];
        var choiceIndex = 0;
        Loreline.play(script,
            (interp, character, text, tags, callback) -> {
                lines.push((character != null ? character + ': ' : '') + text);
                callback();
            },
            (interp, options, callback) -> {
                transcript(lines, options);
                if (choiceIndex == saveAt) onSave(haxe.Json.stringify(interp.save()));
                if (choiceIndex < choices.length) callback(choices[choiceIndex++]);
            },
            interp -> lines.push('(end)')
        );
        return lines;
    }

    /**
     * Restores a save, answers the presented choice and the following ones with
     * `choices` from index `saveAt`, and returns the output plus the save made as
     * soon as the restored choice is presented again.
     */
    public static function resumeFrom(script:Script, saveJson:String, choices:Array<Int>, saveAt:Int):{lines:Array<String>, saveJson:String} {
        final lines:Array<String> = [];
        var choiceIndex = saveAt;
        var resaved:String = null;
        Loreline.resume(script,
            (interp, character, text, tags, callback) -> {
                lines.push((character != null ? character + ': ' : '') + text);
                callback();
            },
            (interp, options, callback) -> {
                transcript(lines, options);
                if (resaved == null) resaved = haxe.Json.stringify(interp.save());
                if (choiceIndex < choices.length) callback(choices[choiceIndex++]);
            },
            interp -> lines.push('(end)'),
            haxe.Json.parse(saveJson)
        );
        return {lines: lines, saveJson: resaved};
    }

    public static function scriptOf(name:String):Script {
        final source = switch name {
            case 'shop': SHOP;
            case 'nested': NESTED;
            case 'rooms': rooms();
            case _: throw 'unknown script ' + name;
        }
        final script = Loreline.parse(source);
        if (script == null) throw 'Failed to parse $name: ' + Loreline.lastError();
        return script;
    }

    public static final SCRIPTS:Array<{name:String, choices:Array<Int>}> = [
        {name: 'shop', choices: [0, 2, 1, 3]},
        {name: 'nested', choices: [0, 1, 1, 2]},
        {name: 'rooms', choices: [0, 0, 1]}
    ];

    static final SHOP = '
state
  gold: 0

beat Shop
  state
    visits: 0
  visits += 1
  gold += 5
  sequence
    Welcome.
  --
    Back again.
  --
    You again, visit $$visits.
  choice
    - Coffee
        cycle
          Hot.
        --
          Warm.
        -> Shop
    - Tea
        -> Shop
    Look around
        Room()
        -> Shop
    Leave
        Bye with $$gold gold.

beat Room
  state
    seen: 0
  seen += 1
  once
    A dusty room.
  --
    The same room ($$seen).
';

    static final NESTED = '
state
  total: 0

beat Main
  state
    rounds: 0
  rounds += 1
  beat Step
    state
      n: 0
    n += 1
    total += n
    cycle
      Step one ($$n).
    --
      Step two ($$n).
  Step()
  Step()
  choice
    - Once more
        -> Main
    More
        -> Main
    End
        Total $$total after $$rounds rounds.
';

    /** 40 beats with a state and a once block each: more node states than the first sizes of the map. */
    static function rooms():String {
        final buffer = new StringBuf();
        buffer.add('state\n  steps: 0\n\nbeat Start\n');
        for (i in 0...40) buffer.add('  Room' + i + '()\n');
        buffer.add('  choice\n    Again\n        steps += 1\n        -> Start\n    Stop\n        Done after $$steps.\n\n');
        for (i in 0...40) {
            buffer.add('beat Room' + i + '\n  state\n    seen: 0\n  seen += 1\n');
            buffer.add('  once\n    Room ' + i + ' first.\n  --\n    Room ' + i + ' again ($$seen).\n\n');
        }
        return buffer.toString();
    }

}
