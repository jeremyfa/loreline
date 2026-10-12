package loreline.i18n;

/**
 * Prints the French of the errors of Loreline as JSON, for the JavaScript
 * build to write `js/loreline-fr.js`, which a web page loads only when it
 * wants French errors: `haxe --class-path src --run loreline.i18n.ExportTables`.
 */
class ExportTables {

    static function main() {
        final table:Dynamic = {};
        for (key => value in Fr.TABLE) Reflect.setField(table, key, value);
        Sys.println(haxe.Json.stringify(table));
    }

}
