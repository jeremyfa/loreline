package loreline.test;

// The benchmark needs Sys and haxe.Timer: it is not part of the GDScript build
#if !gdscript

import loreline.Interpreter;
import loreline.Loreline;
import loreline.Random;

/**
 * Parameters of a generated bark system.
 */
typedef WhenBenchmarkConfig = {

    /** Number of concepts (what is being reacted to). */
    var concepts:Int;

    /** Number of speakers. */
    var speakers:Int;

    /** Number of rules per speaker and concept. */
    var rules:Int;

    /** Number of barks requested. */
    var picks:Int;

    /** Seed of the generated script and of the facts of each pick. */
    var seed:Int;

    /** One of WhenBenchmark.VARIANTS. */
    var variant:String;

}

/**
 * Measures of one benchmark run. Times are in seconds.
 */
typedef WhenBenchmarkResult = {
    var config:WhenBenchmarkConfig;
    var ruleCount:Int;
    var insertionCount:Int;
    var parseTime:Float;
    var totalTime:Float;
    var medianPick:Float;
    var p95Pick:Float;
    var meanPick:Float;
    var barks:Int;
    var silent:Int;
    var hostCalls:Int;
    var checksum:Float;
}

/**
 * A bark system in the style of a rule-based dynamic dialog: every reply is a
 * rule with criteria on facts (the concept, the speaker, the map, the health...),
 * and the most specific eligible rule wins. The script is generated from a seed,
 * then played as a host would: facts set from outside, one `when` pick per
 * request. The checksum of the chosen lines tells whether a change of the
 * interpreter changed the picks.
 *
 * Variants arrange the same rules differently:
 * - `flat`: a single `when` block holding every rule;
 * - `nested`: insertions per concept, then per speaker (two levels);
 * - `calls`: nested, with a host function called in a fifth of the conditions;
 * - `first`: nested, with `when first` everywhere;
 * - `host`: nested, with a host strategy that reproduces the default one, so it
 *   must give the checksum of `nested`;
 * - `shadow`: nested, where every speaker beat has a local state shadowing a
 *   global fact, which forces the dynamic resolution of that name.
 */
class WhenBenchmark {

    public static final VARIANTS = ['flat', 'nested', 'calls', 'first', 'host', 'shadow'];

    public static final USAGE = 'benchmark-when [--variant ${VARIANTS.join("|")}|all] [--concepts N] [--speakers N] [--rules N] [--picks N] [--seed N] [--write file.lor]';

    static final MAPS = 5;

    static final MEMORIES = 5;

    public static function defaultConfig():WhenBenchmarkConfig {
        return {
            concepts: 50,
            speakers: 10,
            rules: 10,
            picks: 2000,
            seed: 1,
            variant: 'nested'
        };
    }

    /**
     * Runs the benchmark described by command line arguments and prints the
     * results. Returns false when the arguments are not understood.
     */
    public static function runFromArgs(args:Array<String>, print:(line:String)->Void):Bool {

        final config = defaultConfig();
        var writePath:String = null;
        var i = 0;
        while (i < args.length) {
            final arg = args[i];
            final value = i + 1 < args.length ? args[i + 1] : null;
            switch arg {
                case '--variant' if (value != null):
                    config.variant = value;
                case '--concepts' | '--speakers' | '--rules' | '--picks' | '--seed' if (value != null):
                    final n = Std.parseInt(value);
                    if (n == null || n < 1) return false;
                    switch arg {
                        case '--concepts': config.concepts = n;
                        case '--speakers': config.speakers = n;
                        case '--rules': config.rules = n;
                        case '--picks': config.picks = n;
                        case _: config.seed = n;
                    }
                case '--write' if (value != null):
                    writePath = value;
                case _:
                    return false;
            }
            i += 2;
        }

        final variants = config.variant == 'all' ? VARIANTS : [config.variant];
        for (variant in variants) {
            if (VARIANTS.indexOf(variant) == -1) return false;
        }

        if (writePath != null) {
            #if sys
            final written = [];
            for (variant in variants) {
                final cfg = Reflect.copy(config);
                cfg.variant = variant;
                final path = variants.length > 1 ? withVariantSuffix(writePath, variant) : writePath;
                sys.io.File.saveContent(path, generate(cfg));
                written.push(path);
            }
            print('Wrote ' + written.join(', '));
            #else
            print('--write needs a target with file access');
            return false;
            #end
        }

        for (variant in variants) {
            final cfg = Reflect.copy(config);
            cfg.variant = variant;
            for (line in format(run(cfg))) print(line);
        }
        return true;

    }

    static function withVariantSuffix(path:String, variant:String):String {
        final dot = path.lastIndexOf('.');
        final slash = path.lastIndexOf('/');
        return dot > slash ? path.substring(0, dot) + '-' + variant + path.substring(dot) : path + '-' + variant;
    }

    /**
     * Lines describing a result, for a terminal.
     */
    public static function format(result:WhenBenchmarkResult):Array<String> {
        final cfg = result.config;
        inline function us(seconds:Float):String {
            return Std.string(Math.round(seconds * 1000000 * 10) / 10) + ' us';
        }
        inline function ms(seconds:Float):String {
            return Std.string(Math.round(seconds * 1000 * 10) / 10) + ' ms';
        }
        return [
            'benchmark-when ${cfg.variant}: ${cfg.concepts} concepts x ${cfg.speakers} speakers x ${cfg.rules} rules (${result.ruleCount} rules, ${result.insertionCount} insertions), ${cfg.picks} picks, seed ${cfg.seed}',
            '  parse     ${ms(result.parseTime)}',
            '  per pick  median ${us(result.medianPick)}   p95 ${us(result.p95Pick)}   mean ${us(result.meanPick)}',
            '  total     ${ms(result.totalTime)}',
            '  barks ${result.barks}   silent ${result.silent}   host calls ${result.hostCalls}',
            '  checksum  ${Std.string(result.checksum)}'
        ];
    }

    /**
     * Generates the script, plays `config.picks` requests and measures them.
     */
    public static function run(config:WhenBenchmarkConfig):WhenBenchmarkResult {

        final source = generate(config);

        var t = haxe.Timer.stamp();
        final script = Loreline.parse(source);
        final parseTime = haxe.Timer.stamp() - t;

        var hostCalls = 0;
        var checksum:Float = 0;
        var barks = 0;
        var barkedThisPick = false;

        final functions:FunctionsMap = #if loreline_functions_map_dynamic_access {} #else new Map<String, Any>() #end;
        #if loreline_auto_wrap_functions
        functions.set('check', (interp:Interpreter, args:Array<Any>) -> { hostCalls++; return args[0]; });
        functions.set('choose', (interp:Interpreter, args:Array<Any>) -> { hostCalls++; return chooseLikeDefault(args[0]); });
        #else
        functions.set('check', (value:Any) -> { hostCalls++; return value; });
        functions.set('choose', (records:Any) -> { hostCalls++; return chooseLikeDefault(records); });
        #end

        final interpreter = new Interpreter(
            script,
            (interp, character, text, tags, advance) -> {
                barks++;
                barkedThisPick = true;
                // Float arithmetic on purpose: exact on every target (it stays well
                // below 2^53), and out of reach of the 31-bit ints of Neko
                for (i in 0...text.length) {
                    checksum = (checksum * 31.0 + text.charCodeAt(i)) % 1000000007.0;
                }
                advance();
            },
            (interp, options, select) -> {},
            interp -> {},
            ({functions: functions} : InterpreterOptions)
        );

        final facts = new Random(config.seed * 7919 + 1);
        final durations:Array<Float> = [];
        var silent = 0;
        final totalStart = haxe.Timer.stamp();

        for (_ in 0...config.picks) {
            interpreter.setStateField('concept', 'c' + facts.between(0, config.concepts));
            interpreter.setStateField('who', 's' + facts.between(0, config.speakers));
            interpreter.setStateField('map', 'm' + facts.between(0, MAPS));
            interpreter.setStateField('health', facts.between(0, 101));
            interpreter.setStateField('danger', facts.between(0, 4));
            interpreter.setStateField('allies', facts.between(0, 5));
            interpreter.setStateField('night', facts.next() < 0.5);
            interpreter.setStateField('wounded', facts.next() < 0.5);
            for (m in 0...MEMORIES) {
                interpreter.setStateField('memory_$m', facts.between(0, 10));
            }

            barkedThisPick = false;
            t = haxe.Timer.stamp();
            interpreter.start('Bark');
            durations.push(haxe.Timer.stamp() - t);
            if (!barkedThisPick) silent++;
        }

        final totalTime = haxe.Timer.stamp() - totalStart;

        durations.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
        var sum = 0.0;
        for (d in durations) sum += d;
        final counts = countRules(config);

        return {
            config: config,
            ruleCount: counts.rules,
            insertionCount: counts.insertions,
            parseTime: parseTime,
            totalTime: totalTime,
            medianPick: durations[Std.int(durations.length / 2)],
            p95Pick: durations[Std.int(Math.min(durations.length - 1, Math.floor(durations.length * 0.95)))],
            meanPick: sum / durations.length,
            barks: barks,
            silent: silent,
            hostCalls: hostCalls,
            checksum: checksum
        };

    }

    /**
     * The default strategy written as a host strategy: most criteria, then the
     * rule played least recently (never played first), then written order.
     */
    static function chooseLikeDefault(records:Any):Int {
        var best = -1;
        var bestCriteria = -1;
        var bestLastPlayed = 0;
        for (i in 0...Arrays.arrayLength(records)) {
            final record = Arrays.arrayGet(records, i);
            if (Objects.getField(null, record, 'eligible') != true) continue;
            final criteria:Int = Objects.getField(null, record, 'criteria');
            final lastPlayed:Int = Objects.getField(null, record, 'lastPlayed');
            if (best == -1 || criteria > bestCriteria || (criteria == bestCriteria && lastPlayed < bestLastPlayed)) {
                best = i;
                bestCriteria = criteria;
                bestLastPlayed = lastPlayed;
            }
        }
        return best;
    }

    static function countRules(config:WhenBenchmarkConfig):{rules:Int, insertions:Int} {
        final groups = config.concepts * config.speakers;
        return switch config.variant {
            case 'flat':
                // Every speaker rule, plus the concept rules, plus the final fallback
                {rules: groups * config.rules + config.concepts * 2 + 1, insertions: 0};
            case _:
                // Speaker rules and their fallbacks, concept rules, the final fallback
                {rules: groups * (config.rules + 1) + config.concepts * 2 + 1, insertions: config.concepts + groups};
        }
    }

    /**
     * The Loreline source of a bark system. The rules only depend on the seed and
     * the sizes, so every variant of a configuration holds the same rules.
     */
    public static function generate(config:WhenBenchmarkConfig):String {

        final rules = new Random(config.seed);
        final calls = new Random(config.seed * 31 + 7);
        final out = new StringBuf();
        final strategy = switch config.variant {
            case 'first': ' first';
            case 'host': ' choose';
            case _: '';
        }
        final flat = config.variant == 'flat';

        out.add('// Generated bark system: ${config.variant}, seed ${config.seed}\n\n');

        out.add('state\n');
        out.add('  concept: "c0"\n');
        out.add('  who: "s0"\n');
        out.add('  map: "m0"\n');
        out.add('  health: 50\n');
        out.add('  danger: 0\n');
        out.add('  allies: 0\n');
        out.add('  night: false\n');
        out.add('  wounded: false\n');
        for (m in 0...MEMORIES) out.add('  memory_$m: 0\n');
        out.add('\n');

        for (s in 0...config.speakers) {
            out.add('character s$s\n  name: Speaker $s\n\n');
        }

        // The rules of every group, generated first so that each variant arranges
        // the same rules
        final conceptRules:Array<Array<{condition:String, once:Bool, body:String}>> = [];
        final speakerRules:Array<Array<Array<{condition:String, once:Bool, body:String}>>> = [];
        for (c in 0...config.concepts) {
            conceptRules.push([for (k in 0...2) {
                condition: criteria(rules, 1 + k).join(' and '),
                once: false,
                body: 'Concept $c general $k.'
            }]);
            final perSpeaker = [];
            for (s in 0...config.speakers) {
                perSpeaker.push([for (k in 0...config.rules) {
                    var condition = criteria(rules, rules.between(1, 5)).join(' and ');
                    if (config.variant == 'calls' && calls.next() < 0.2) condition += ' and check(true)';
                    {
                        condition: condition,
                        once: k % 5 == 4,
                        body: 's$s: Bark $c.$s.$k ${WORDS[rules.between(0, WORDS.length)]} ${WORDS[rules.between(0, WORDS.length)]}.'
                    }
                }]);
            }
            speakerRules.push(perSpeaker);
        }

        inline function rule(indent:String, r:{condition:String, once:Bool, body:String}, prefix:String) {
            out.add(indent + (r.once ? '- ' : '') + prefix + r.condition + '\n');
            out.add(indent + '  ' + r.body + '\n');
        }

        if (flat) {
            out.add('beat Bark\n  when$strategy\n');
            for (c in 0...config.concepts) {
                for (s in 0...config.speakers) {
                    for (r in speakerRules[c][s]) rule('    ', r, 'concept is "c$c" and who is "s$s" and ');
                }
                for (r in conceptRules[c]) rule('    ', r, 'concept is "c$c" and ');
            }
            out.add('    true\n      Nothing to say.\n');
        }
        else {
            out.add('beat Bark\n  when$strategy\n');
            for (c in 0...config.concepts) out.add('    + Concept_$c if concept is "c$c"\n');
            out.add('    true\n      Nothing to say.\n\n');

            for (c in 0...config.concepts) {
                out.add('beat Concept_$c\n  when$strategy\n');
                for (s in 0...config.speakers) out.add('    + Speaker_${c}_$s if who is "s$s"\n');
                for (r in conceptRules[c]) rule('    ', r, '');
                out.add('\n');
                for (s in 0...config.speakers) {
                    out.add('beat Speaker_${c}_$s\n');
                    if (config.variant == 'shadow') {
                        // A local state shadowing the global map: the conditions on
                        // `map` of this beat read the local value
                        out.add('  state\n    map: "m${s % MAPS}"\n');
                    }
                    out.add('  when$strategy\n');
                    for (r in speakerRules[c][s]) rule('    ', r, '');
                    out.add('    true\n      s$s: Speaker $s has nothing on $c.\n\n');
                }
            }
        }

        return out.toString();

    }

    static final WORDS = ['again', 'quietly', 'now', 'maybe', 'there', 'carefully', 'twice', 'later', 'alone', 'together'];

    static final FACTS = ['map', 'health', 'danger', 'allies', 'night', 'wounded', 'memory'];

    /**
     * `count` criteria on distinct facts.
     */
    static function criteria(rnd:Random, count:Int):Array<String> {
        final pool = FACTS.copy();
        final result = [];
        for (_ in 0...count) {
            final fact = pool.splice(rnd.between(0, pool.length), 1)[0];
            result.push(switch fact {
                case 'map': 'map is "m${rnd.between(0, MAPS)}"';
                case 'health': rnd.next() < 0.5 ? 'health > ${rnd.between(10, 90)}' : 'health < ${rnd.between(10, 90)}';
                case 'danger': 'danger >= ${rnd.between(1, 4)}';
                case 'allies': 'allies == ${rnd.between(0, 5)}';
                case 'night': rnd.next() < 0.5 ? 'night' : 'not night';
                case 'wounded': rnd.next() < 0.5 ? 'wounded' : 'not wounded';
                case _: 'memory_${rnd.between(0, MEMORIES)} > ${rnd.between(0, 9)}';
            });
        }
        return result;
    }

}

#end
