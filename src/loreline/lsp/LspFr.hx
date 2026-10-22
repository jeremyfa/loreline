package loreline.lsp;

import loreline.i18n.I18n;

/**
 * The French of the public language server: hovers, completion, symbols and
 * its own diagnostics. The errors of Loreline are in `loreline.i18n.Fr`.
 */
@:build(loreline.i18n.I18nMacro.table('fr', 'lsp'))
class LspFr {

    /** Makes these translations available to `I18n` in French */
    public static function register():Void {
        I18n.register('fr', TABLE);
    }

    public static final TABLE:Map<String, String> = [

        // Diagnostics

        'Unknown beat: {name}' => 'Beat inconnu : {name}',
        'Unknown character: {name}' => 'Personnage inconnu : {name}',
        'Error in {file}{line}: {message}' => 'Erreur dans {file}{line} : {message}',

        // Completion

        'Object field' => "Champ d'objet",
        'Character field' => 'Champ de personnage',
        'Metadata' => 'Métadonnées',
        'Metadata§key' => 'Métadonnée',
        'Local variable' => 'Variable locale',
        'State field' => "Champ d'état",
        'Character' => 'Personnage',
        'Function' => 'Fonction',
        'Operator, like {symbol}' => 'Opérateur, comme {symbol}',
        'Beat' => 'Beat',
        'Tag' => 'Tag',
        'Used {n} time' => 'Utilisé {n} fois',
        'Used {n} times' => 'Utilisé {n} fois',
        'When strategy' => 'Stratégie when',
        'When strategy (function)' => 'Stratégie when (fonction)',

        // Hover titles

        'Text' => 'Texte',
        'Choice option' => 'Option de choix',
        'Dialogue' => 'Réplique',
        'of {name}' => 'dite par {name}',
        'End' => 'Fin',
        'Top level' => 'Niveau principal',
        'Transition' => 'Transition',
        'Insertion' => 'Insertion',
        'Beat call' => 'Appel de beat',
        'Number' => 'Nombre',
        'Boolean' => 'Booléen',
        'Null' => 'Null',
        'Array' => 'Liste',
        'Object' => 'Objet',
        'Expression' => 'Expression',
        'Condition' => 'Condition',
        'Alternative' => 'Alternative',
        'Choice' => 'Choix',
        'When' => 'When',
        'When rule' => 'Règle when',
        'Temporary state' => 'État temporaire',
        'State' => 'État',
        'Constant' => 'Constante',
        'Name' => 'Nom',
        'Variable' => 'Variable',
        'Parentheses' => 'Parenthèses',
        'Block' => 'Bloc',
        'Field' => 'Champ',
        'Binary operation' => 'Opération binaire',
        'Unary operation' => 'Opération unaire',
        'Loop' => 'Boucle while',
        'For loop' => 'Boucle for',
        'Break' => 'Break',
        'Continue' => 'Continue',
        'Return' => 'Return',
        'Array access' => 'Élément de liste',
        'New' => 'New',
        'Throw' => 'Throw',
        'Try' => 'Try',
        'Ternary operation' => 'Opération ternaire',
        'Switch' => 'Switch',
        'Do... while' => 'Do... while',
        'Type' => 'Type',

        // What a name is

        'operator' => 'opérateur',
        'choice option' => 'option de choix',
        'import' => 'import',
        'metadata' => 'métadonnée',
        'beat' => 'beat',
        'public beat' => 'beat public',
        'character' => 'personnage',
        'function' => 'fonction',
        'function provided by the app' => "fonction fournie par l'application",
        'built-in function' => 'fonction intégrée',
        'parameter' => 'paramètre',
        'field' => 'champ',
        'state field' => "champ d'état",
        'local' => 'variable locale',
        'text method' => 'fonction de texte',
        'list method' => 'fonction de liste',
        'map method' => 'fonction de dictionnaire',
        'beat method' => 'fonction de beat',
        'translation tag' => 'tag de traduction',
        'in the state of {owner}' => "dans l'état de {owner}",
        'in the state' => "dans l'état",
        'local in {owner}' => 'variable locale de {owner}',
        '{kind} of {owner}' => '{kind} de {owner}',

        // Hover contents

        'defaults to {value}' => 'vaut {value} par défaut',
        'Defaults to {value}' => 'Vaut {value} par défaut',
        '{name} (object)' => '{name} (objet)',
        'Parameters' => 'Paramètres',
        'Fields' => 'Champs',
        'Characters' => 'Personnages',
        'State§group' => 'État',
        'Flow' => 'Enchaînement',
        'the top level' => 'le niveau principal',
        'From {list}' => 'Depuis {list}',
        'To {list}' => 'Vers {list}',
        'Calls {list}' => 'Appelle {list}',
        'Always applies' => "S'applique toujours",
        '{n} condition' => '{n} condition',
        '{n} conditions' => '{n} conditions',
        'Played only once' => 'Jouée une seule fois',
        'Brings in the rules of the first when block of the inserted beat.' => 'Reprend les règles du premier bloc when du beat inséré.',
        'Brings in the rules of the first when block of the inserted beat. Its condition only decides whether they are brought in.' => 'Reprend les règles du premier bloc when du beat inséré. Sa condition décide seulement si elles sont reprises.',
        'Plays the most specific rule that applies, and takes turns between equally specific ones.' => "Joue la règle la plus spécifique qui s'applique, et alterne en cas d'égalité.",
        'Plays the first rule that applies, from top to bottom. Useful for thresholds.' => "Joue la première règle qui s'applique, de haut en bas. Pratique pour des seuils.",
        'Plays one of the rules that apply, at random.' => "Joue au hasard l'une des règles qui s'appliquent.",
        'Lets the function `{name}` choose the rule to play.' => 'Laisse la fonction `{name}` choisir la règle à jouer.',
        '`a and b` is true when both `a` and `b` are true, like `a && b`.' => '`a and b` est vrai quand `a` et `b` sont vrais tous les deux, comme `a && b`.',
        '`a or b` is true when `a` or `b` is true, like `a || b`.' => '`a or b` est vrai quand `a` ou `b` est vrai, comme `a || b`.',
        '`a is b` is true when `a` equals `b`, like `a == b`.' => '`a is b` est vrai quand `a` est égal à `b`, comme `a == b`.',
        '`a is not b` is true when `a` differs from `b`, like `a != b`. `is not` is always read as one operator: to compare with a negation, write `a is (not b)`.' => '`a is not b` est vrai quand `a` est différent de `b`, comme `a != b`. `is not` se lit toujours comme un seul opérateur : pour comparer avec une négation, écrivez `a is (not b)`.',
        '`not a` is true when `a` is false, like `!a`. It applies to what follows it directly: `not a is b` reads `(not a) is b`, so write `not (a is b)` to negate a comparison.' => '`not a` est vrai quand `a` est faux, comme `!a`. Il porte sur ce qui le suit directement : `not a is b` se lit `(not a) is b`, écrivez donc `not (a is b)` pour inverser une comparaison.',

        // Symbols

        'condition' => 'condition',
        '{n} field' => '{n} champ',
        '{n} fields' => '{n} champs',
        '{n} option' => '{n} option',
        '{n} options' => '{n} options',
        '{n} rule' => '{n} règle',
        '{n} rules' => '{n} règles',
        '{n} item' => '{n} élément',
        '{n} items' => '{n} éléments',
        'item {n}' => 'élément {n}',

        // Metadata keys

        'The title of the story.' => "Le titre de l'histoire.",
        'Who wrote the story: a name, or a list of names.' => "Qui a écrit l'histoire : un nom, ou une liste de noms.",
        'The language of the story, as a code like `en`, `fr` or `pt-BR`.' => "Le code de la langue de l'histoire, comme `en`, `fr` ou `pt-BR`.",
        'The version of the story.' => "La version de l'histoire.",
        'The identifier of the story in interactive fiction archives: a UUID in capitals.' => "L'identifiant de l'histoire dans les archives de fiction interactive : un UUID en majuscules.",
        'A short line shown under the title, like "An interactive mystery".' => 'Une courte accroche sous le titre, comme "Un mystère interactif".',
        'What the story is about, in a few sentences.' => "De quoi parle l'histoire, en quelques phrases.",
        'When the story was first published: a year, or a date like `2026-03-14`.' => "L'année ou la date de première publication, comme `2026` ou `2026-03-14`.",
        'The genre of the story.' => "Le genre de l'histoire.",
        'The series the story belongs to.' => "La série dont l'histoire fait partie.",
        'The number of the story in its series.' => "Le numéro de l'histoire dans sa série.",
        'The web page of the story.' => "La page web de l'histoire.",

    ];

}
