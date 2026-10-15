package loreline.macros;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.ExprTools;
#end

/**
 * Turns the character tables of Identifiers, written as text by
 * tools/identifier-tables.py, into arrays of integers at compile time: the
 * exported code holds the arrays themselves, nothing is decoded at runtime.
 */
class IdentifierTables {

    #if macro
    /** How many values each function fills, on the JVM */
    static final CHUNK_SIZE = 1000;

    /** How many helper classes were defined, on the JVM */
    static var tableCount = 0;
    #end

    /**
     * The array of a table written as hexadecimal code points separated by
     * spaces (a constant text, or constant texts joined with `+`).
     */
    public static macro function decode(text:ExprOf<String>):ExprOf<Array<Int>> {
        final values:Array<Expr> = [];
        for (hex in Std.string(ExprTools.getValue(text)).split(' ')) {
            if (hex != '') values.push(macro $v{Std.parseInt('0x' + hex)});
        }

        if (!Context.defined('jvm')) {
            return macro $a{values};
        }

        // On the JVM, a method holds at most 64 KB of bytecode, and a class
        // initializes all its static arrays in one method. The table is filled
        // instead by the static functions of a class defined here, each pushing
        // its part into the same array.
        final className = 'IdentifierTable' + (tableCount++);
        final fields:Array<Field> = [];
        final calls:Array<Expr> = [];
        var start = 0;
        while (start < values.length) {
            final end = Std.int(Math.min(start + CHUNK_SIZE, values.length));
            final pushes = [for (i in start...end) macro table.push(${values[i]})];
            final name = 'fill' + fields.length;
            fields.push({
                name: name,
                access: [APublic, AStatic],
                kind: FFun({args: [{name: 'table', type: macro :Array<Int>}], ret: macro :Void, expr: macro $b{pushes}}),
                pos: Context.currentPos()
            });
            calls.push(macro loreline.macros.$className.$name(table));
            start = end;
        }
        Context.defineType({
            pack: ['loreline', 'macros'],
            name: className,
            kind: TDClass(),
            fields: fields,
            pos: Context.currentPos()
        });
        return macro {
            final table:Array<Int> = [];
            $b{calls};
            table;
        };
    }

}
