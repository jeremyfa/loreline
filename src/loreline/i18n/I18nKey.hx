package loreline.i18n;

/**
 * A word given as a parameter of a template that is itself translated, like
 * the kind of a value in an error: `I18n.key('character')`.
 */
class I18nKey {

    /** The English word, which is also its key in the tables */
    public final word:String;

    public function new(word:String) {
        this.word = word;
    }

    public function toString():String {
        return @:privateAccess I18n.translate(word, 'en');
    }

}
