package loreline.i18n;

/**
 * A template with its parameters, kept to be shown later in any locale: what
 * an error holds, so that the tools can show it in French while the game keeps
 * its English message.
 */
class I18nText {

    /** The English template, which is also its key in the tables */
    public final template:String;

    /** The values of its parameters, by name */
    public final params:Null<Dynamic>;

    public function new(template:String, ?params:Dynamic) {
        this.template = template;
        this.params = params;
    }

    /** The text in a locale, or the current one */
    public function format(?locale:String):String {
        return I18n.format(template, params, locale);
    }

    public function toString():String {
        return I18n.format(template, params, 'en');
    }

}
