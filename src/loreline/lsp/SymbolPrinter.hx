package loreline.lsp;

import Type as HxType;
import loreline.Node;
import loreline.Position;
import loreline.Printer;
import loreline.i18n.I18n;
import loreline.lsp.Protocol;

using StringTools;

/**
 * A printer that converts AST nodes into LSP document symbols.
 * Similar to the Printer class but outputs DocumentSymbol array.
 */
class SymbolPrinter {

    /** Reference to the document content for range calculations */
    final content:String;

    /** The server, whose position conversions the ranges use */
    final server:Server;

    /** Current parent symbol being built */
    var currentSymbol:DocumentSymbol;

    /**
     * Creates a new symbol printer.
     * @param server The server, for its position conversions
     * @param content Document content for range calculation
     */
    public function new(server:Server, content:String) {
        this.server = server;
        this.content = content;
    }

    /**
     * Main entry point for converting a node to document symbols.
     * @param node Root node to process
     * @return Array of document symbols
     */
    public function print(node:Node):Array<DocumentSymbol> {
        return switch HxType.getClass(node) {
            case Script: printScript(cast node);
            case _: [];
        }
    }

    /**
     * Process a complete script node.
     * @param script Script node to process
     * @return Array of document symbols for top-level declarations
     */
    function printScript(script:Script):Array<DocumentSymbol> {
        final symbols:Array<DocumentSymbol> = [];

        for (decl in script.body) {
            switch HxType.getClass(decl) {
                case NChoiceStatement:
                    symbols.push(printChoice(cast decl));
                case NIfStatement:
                    for (symbol in printIf(cast decl)) {
                        symbols.push(symbol);
                    }
                case NAlternative:
                    symbols.push(printAlternative(cast decl));
                case NWhenStatement:
                    symbols.push(printWhen(cast decl));
                case NStateDecl:
                    symbols.push(printStateDecl(cast decl));
                case NMetadataDecl:
                    symbols.push(printMetadataDecl(cast decl));
                case NBeatDecl:
                    symbols.push(printBeatDecl(cast decl));
                case NCharacterDecl:
                    symbols.push(printCharacterDecl(cast decl));
                case _:
                    // Skip other top-level nodes
            }
        }

        return symbols;
    }

    /**
     * Process a beat declaration.
     * @param beat Beat node to process
     * @return Document symbol for the beat
     */
    function printBeatDecl(beat:NBeatDecl):DocumentSymbol {
        final children:Array<DocumentSymbol> = [];

        for (node in beat.body) {
            switch HxType.getClass(node) {
                case NChoiceStatement:
                    children.push(printChoice(cast node));
                case NIfStatement:
                    for (symbol in printIf(cast node)) {
                        children.push(symbol);
                    }
                case NAlternative:
                    children.push(printAlternative(cast node));
                case NWhenStatement:
                    children.push(printWhen(cast node));
                case NStateDecl:
                    children.push(printStateDecl(cast node));
                case NBeatDecl:
                    children.push(printBeatDecl(cast node));
                case _:
                    // Skip other node types
            }
        }

        return {
            name: beat.name,
            detail: I18n.t('beat'),
            kind: SymbolKind.Class,
            deprecated: false,
            range: server.rangeFromLorelinePosition(beat.pos, content),
            selectionRange: server.rangeFromLorelinePosition(beat.pos, content),
            children: children
        };
    }

    /**
     * Process a character declaration.
     * @param char Character node to process
     * @return Document symbol for the character
     */
    function printCharacterDecl(char:NCharacterDecl):DocumentSymbol {
        final children:Array<DocumentSymbol> = [];

        for (prop in char.fields) {
            children.push({
                name: prop.name,
                detail: printValue(prop.value),
                kind: SymbolKind.Property,
                deprecated: false,
                range: server.rangeFromLorelinePosition(prop.pos, content),
                selectionRange: server.rangeFromLorelinePosition(prop.pos, content)
            });
        }

        return {
            name: char.name,
            detail: I18n.t('character'),
            kind: SymbolKind.Object,
            deprecated: false,
            range: server.rangeFromLorelinePosition(char.pos, content),
            selectionRange: server.rangeFromLorelinePosition(char.pos, content),
            children: children
        };
    }

    /**
     * Process the metadata block of a story.
     * @param metadata Metadata node to process
     * @return Document symbol for the block
     */
    function printMetadataDecl(metadata:NMetadataDecl):DocumentSymbol {
        final children:Array<DocumentSymbol> = [];

        for (field in metadata.fields) {
            children.push({
                name: field.name,
                detail: printValue(field.value),
                kind: SymbolKind.Property,
                deprecated: false,
                range: server.rangeFromLorelinePosition(field.pos, content),
                selectionRange: server.rangeFromLorelinePosition(field.pos, content)
            });
        }

        return {
            name: "metadata",
            detail: I18n.count(children.length, '{n} field', '{n} fields'),
            kind: SymbolKind.Namespace,
            deprecated: false,
            range: server.rangeFromLorelinePosition(metadata.pos, content),
            selectionRange: server.rangeFromLorelinePosition(metadata.pos, content),
            children: children
        };
    }

    /**
     * Process a state declaration.
     * @param state State node to process
     * @return Document symbol for the state
     */
    function printStateDecl(state:NStateDecl):DocumentSymbol {
        final children:Array<DocumentSymbol> = [];
        final fields = state.fields;

        for (field in (fields:Array<NObjectField>)) {
            children.push({
                name: field.name,
                detail: printValue(field.value),
                kind: SymbolKind.Variable,
                deprecated: false,
                range: server.rangeFromLorelinePosition(field.pos, content),
                selectionRange: server.rangeFromLorelinePosition(field.pos, content)
            });
        }

        return {
            name: state.temporary ? "new state" : "state",
            detail: I18n.count(children.length, '{n} field', '{n} fields'),
            kind: SymbolKind.Namespace,
            deprecated: false,
            range: server.rangeFromLorelinePosition(state.pos, content),
            selectionRange: server.rangeFromLorelinePosition(state.pos, content),
            children: children
        };
    }

    /**
     * Process a choice statement.
     * @param choice Choice node to process
     * @return Document symbol for the choice
     */
    function printChoice(choice:NChoiceStatement):DocumentSymbol {
        final children:Array<DocumentSymbol> = [];

        for (option in choice.options) {
            final label = switch (option.text) {
                case null: "(empty)";
                case text: printValue(text);
            }

            final optionSymbol:DocumentSymbol = {
                name: label,
                detail: option.condition != null ? 'if ${printValue(option.condition)}' : "",
                kind: SymbolKind.EnumMember,
                deprecated: false,
                range: server.rangeFromLorelinePosition(option.pos, content),
                selectionRange: server.rangeFromLorelinePosition(option.pos, content),
                children: []
            };

            for (node in option.body) {
                switch HxType.getClass(node) {
                    case NChoiceStatement:
                        optionSymbol.children.push(printChoice(cast node));
                    case NIfStatement:
                        for (symbol in printIf(cast node)) {
                            optionSymbol.children.push(symbol);
                        }
                    case NAlternative:
                        optionSymbol.children.push(printAlternative(cast node));
                    case NWhenStatement:
                        optionSymbol.children.push(printWhen(cast node));
                    case NStateDecl:
                        optionSymbol.children.push(printStateDecl(cast node));
                    case _:
                        // Skip other node types
                }
            }

            children.push(optionSymbol);
        }

        return {
            name: "choice",
            detail: I18n.count(choice.options.length, '{n} option', '{n} options'),
            kind: SymbolKind.Enum,
            deprecated: false,
            range: server.rangeFromLorelinePosition(choice.pos, content),
            selectionRange: server.rangeFromLorelinePosition(choice.pos, content),
            children: children
        };
    }

    /**
     * Process a when block: one symbol per rule, named after its header.
     * @param when When node to process
     * @return Document symbol for the when block
     */
    function printWhen(when:NWhenStatement):DocumentSymbol {
        final children:Array<DocumentSymbol> = [];

        for (rule in when.rules) {
            final label = if (rule.insertion != null) {
                printValue(rule.insertion);
            }
            else if (rule.condition == null) {
                "true";
            }
            else {
                printValue(rule.condition);
            }

            final ruleSymbol:DocumentSymbol = {
                name: (rule.once ? "- " : "") + label,
                detail: rule.insertionCondition != null ? 'if ${printValue(rule.insertionCondition)}' : "",
                kind: SymbolKind.EnumMember,
                deprecated: false,
                range: server.rangeFromLorelinePosition(rule.pos, content),
                selectionRange: server.rangeFromLorelinePosition(rule.pos, content),
                children: []
            };

            for (node in rule.body) {
                switch HxType.getClass(node) {
                    case NChoiceStatement:
                        ruleSymbol.children.push(printChoice(cast node));
                    case NWhenStatement:
                        ruleSymbol.children.push(printWhen(cast node));
                    case NIfStatement:
                        for (symbol in printIf(cast node)) {
                            ruleSymbol.children.push(symbol);
                        }
                    case NAlternative:
                        ruleSymbol.children.push(printAlternative(cast node));
                    case NStateDecl:
                        ruleSymbol.children.push(printStateDecl(cast node));
                    case _:
                        // Skip other node types
                }
            }

            children.push(ruleSymbol);
        }

        return {
            name: when.strategy != null ? "when " + when.strategy : "when",
            detail: I18n.count(when.rules.length, '{n} rule', '{n} rules'),
            kind: SymbolKind.Enum,
            deprecated: false,
            range: server.rangeFromLorelinePosition(when.pos, content),
            selectionRange: server.rangeFromLorelinePosition(when.pos, content),
            children: children
        };
    }

    /**
     * Process an if statement.
     * @param ifStmt If statement node to process
     * @return Document symbol for the if statement
     */
    function printIf(ifStmt:NIfStatement):Array<DocumentSymbol> {
        final result:Array<DocumentSymbol> = [];

        if (ifStmt.thenBranch != null) {
            result.push({
                name: printValue(ifStmt.condition),
                detail: I18n.t('condition'),
                kind: SymbolKind.Boolean,
                deprecated: false,
                range: server.rangeFromLorelinePosition(ifStmt.pos, content),
                selectionRange: server.rangeFromLorelinePosition(ifStmt.pos, content),
                children: printChildren(ifStmt.thenBranch)
            });
        }

        if (ifStmt.elseBranch != null && ifStmt.elseBranch.body.length == 1) {
            if (HxType.getClass(ifStmt.elseBranch.body[0]) == NIfStatement) {
                for (symbol in printIf(cast ifStmt.elseBranch.body[0])) {
                    result.push(symbol);
                }
            }
        }

        return result;
    }

    /**
     * Process an alternative block.
     * @param alt Alternative node to process
     * @return Document symbol for the alternative
     */
    function printAlternative(alt:NAlternative):DocumentSymbol {
        final children:Array<DocumentSymbol> = [];

        for (i in 0...alt.items.length) {
            final item = alt.items[i];
            final blockSymbol = printBlock(I18n.t('item {n}', {n: i + 1}), null, item);
            children.push(blockSymbol);
        }

        return {
            name: alt.mode.toString(),
            detail: I18n.count(alt.items.length, '{n} item', '{n} items'),
            kind: SymbolKind.Enum,
            deprecated: false,
            range: server.rangeFromLorelinePosition(alt.pos, content),
            selectionRange: server.rangeFromLorelinePosition(alt.pos, content),
            children: children
        };
    }

    /**
     * Process a block of nodes.
     * @param name Block name
     * @param detail Block detail text
     * @param block Block node to process
     * @return Document symbol for the block
     */
    function printBlock(name:String, detail:String, block:NBlock):DocumentSymbol {
        return {
            name: name,
            detail: detail,
            kind: SymbolKind.Namespace,
            deprecated: false,
            range: server.rangeFromLorelinePosition(block.pos, content),
            selectionRange: server.rangeFromLorelinePosition(block.pos, content),
            children: printChildren(block)
        };
    }

    /**
     * The symbols of the choices, conditions, alternatives, when blocks and
     * states found in a block.
     * @param block Block node to process
     * @return Document symbols of its children
     */
    function printChildren(block:NBlock):Array<DocumentSymbol> {
        final children:Array<DocumentSymbol> = [];

        for (node in block.body) {
            switch HxType.getClass(node) {
                case NChoiceStatement:
                    children.push(printChoice(cast node));
                case NIfStatement:
                    for (symbol in printIf(cast node)) {
                        children.push(symbol);
                    }
                case NAlternative:
                    children.push(printAlternative(cast node));
                case NWhenStatement:
                    children.push(printWhen(cast node));
                case NStateDecl:
                    children.push(printStateDecl(cast node));
                case _:
                    // Skip other node types
            }
        }

        return children;
    }

    /**
     * Convert a node to a string value for display.
     * @param node Node to convert
     * @return String representation
     */
    function printValue(node:Node):String {
        final printer = new Printer();
        printer.enableComments = false;
        return printer.print(node).trim();
    }

}
