package loreline.lsp;

/**
 * The keys of the `metadata` block that have a meaning of their own: those of
 * the bibliographic record of the Treaty of Babel, in Loreline's naming
 * (https://babel.ifarchive.org). Any other key is allowed too, and goes as is
 * to the app running the story.
 */
class MetadataKeys {

    /** Each known key, with what it means, in one line */
    public static final KEYS:Array<{key:String, meaning:String}> = [
        {key: 'title', meaning: 'The title of the story.'},
        {key: 'author', meaning: 'Who wrote the story: a name, or a list of names.'},
        {key: 'language', meaning: 'The language of the story, as a code like `en`, `fr` or `pt-BR`.'},
        {key: 'version', meaning: 'The version of the story.'},
        {key: 'ifid', meaning: 'The identifier of the story in interactive fiction archives, a UUID in capitals.'},
        {key: 'headline', meaning: 'A short line shown under the title, like "An interactive mystery".'},
        {key: 'description', meaning: 'What the story is about, in a few sentences.'},
        {key: 'firstPublished', meaning: 'When the story was first published: a year, or a date like `2026-03-14`.'},
        {key: 'genre', meaning: 'The genre of the story.'},
        {key: 'series', meaning: 'The series the story belongs to.'},
        {key: 'seriesNumber', meaning: 'The number of the story in its series.'},
        {key: 'url', meaning: 'The web page of the story.'}
    ];

    /** What a known key means, or null for any other key */
    public static function meaning(key:String):Null<String> {

        for (known in KEYS) {
            if (known.key == key) return known.meaning;
        }
        return null;

    }

}
