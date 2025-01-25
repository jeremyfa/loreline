package loreline;

enum abstract Quotes(Int) {

    var Unquoted = 0;

    var DoubleQuotes = 1;

    public function toString() {
        return switch abstract {
            case Unquoted: "Unquoted";
            case DoubleQuotes: "DoubleQuotes";
        }
    }

}
