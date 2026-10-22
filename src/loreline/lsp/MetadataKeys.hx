package loreline.lsp;

import loreline.i18n.I18n;

/**
 * The keys of the `metadata` block that have a meaning of their own: those of
 * the bibliographic record of the Treaty of Babel, in Loreline's naming
 * (https://babel.ifarchive.org). Any other key is allowed too, and goes as is
 * to the app running the story.
 */
class MetadataKeys {

    /** Each known key, with what it means, in one line, in the language of the tools */
    public static final KEYS:Array<{key:String, meaning:()->String}> = [
        {key: 'title', meaning: () -> I18n.t('The title of the story.')},
        {key: 'author', meaning: () -> I18n.t('Who wrote the story: a name, or a list of names.')},
        {key: 'language', meaning: () -> I18n.t('The language of the story, as a code like `en`, `fr` or `pt-BR`.')},
        {key: 'version', meaning: () -> I18n.t('The version of the story.')},
        {key: 'ifid', meaning: () -> I18n.t('The identifier of the story in interactive fiction archives: a UUID in capitals.')},
        {key: 'headline', meaning: () -> I18n.t('A short line shown under the title, like "An interactive mystery".')},
        {key: 'description', meaning: () -> I18n.t('What the story is about, in a few sentences.')},
        {key: 'firstPublished', meaning: () -> I18n.t('When the story was first published: a year, or a date like `2026-03-14`.')},
        {key: 'genre', meaning: () -> I18n.t('The genre of the story.')},
        {key: 'series', meaning: () -> I18n.t('The series the story belongs to.')},
        {key: 'seriesNumber', meaning: () -> I18n.t('The number of the story in its series.')},
        {key: 'url', meaning: () -> I18n.t('The web page of the story.')}
    ];

    /** What a known key means, or null for any other key */
    public static function meaning(key:String):Null<String> {

        for (known in KEYS) {
            if (known.key == key) return known.meaning();
        }
        return null;

    }

}
