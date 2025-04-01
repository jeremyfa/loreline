package loreline;

import haxe.ds.StringMap;
import yaml.Yaml as HxYaml;
import yaml.util.ObjectMap;

class Yaml {

    public static function parse(input:String):Dynamic {

        return yamlToLiteral(HxYaml.parse(input));

    }

    private static function yamlToLiteral(input:Dynamic):Dynamic {

        if (input is TObjectMap) {
            var map:TObjectMap<Any,Any> = cast input;
            var result:Dynamic = {};
            for (key in map.keys()) {
                Reflect.setField(result, Std.string(key), yamlToLiteral(map.get(key)));
            }
            return result;
        }
        else if (input is StringMap) {
            trace('B');
            var map:Map<Any,Any> = cast input;
            var result:Dynamic = {};
            for (key in map.keys()) {
                Reflect.setField(result, Std.string(key), yamlToLiteral(map.get(key)));
            }
            return result;
        }
        else if (input is Array) {
            var array:Array<Any> = cast input;
            var result:Array<Any> = [];
            for (item in array) {
                result.push(yamlToLiteral(item));
            }
            return result;
        }
        else {
            return input;
        }

    }

}
