package loreline;

@:keep
class Json {

    public static function stringify(value:Any, pretty:Bool = false) {
        return haxe.Json.stringify(value, null, pretty ? '  ' : null);
    }

    public static function parse(json:String) {
        return haxe.Json.parse(json);
    }

}
