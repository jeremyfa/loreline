package loreline.lsp;

import Type as HxType;
import loreline.Node;
import loreline.Position;
import loreline.Printer;
import loreline.lsp.Protocol;

using StringTools;

/**
 * A printer that converts AST nodes into LSP document symbols.
 * Similar to the Printer class but outputs DocumentSymbol array.
 */
class SymbolPrinter {

    /** Reference to the document content for range calculations */
    final content:String;

    /** Current parent symbol being built */
    var currentSymbol:DocumentSymbol;

    /**
     * Creates a new symbol printer.
     * @param content Document content for range calculation
     */
    public function new(content:String) {
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

        for (decl in script.declarations) {
            switch HxType.getClass(decl) {
                case NChoiceStatement:
                    symbols.push(printChoice(cast decl));
                case NIfStatement:
                    for (symbol in printIf(cast decl)) {
                        symbols.push(symbol);
                    }
                case NStateDecl:
                    symbols.push(printStateDecl(cast decl));
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
            detail: "beat",
            kind: SymbolKind.Class,
            deprecated: false,
            range: rangeFromPosition(beat.pos),
            selectionRange: rangeFromPosition(beat.pos),
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
                range: rangeFromPosition(prop.pos),
                selectionRange: rangeFromPosition(prop.pos)
            });
        }

        return {
            name: char.name,
            detail: "character",
            kind: SymbolKind.Object,
            deprecated: false,
            range: rangeFromPosition(char.pos),
            selectionRange: rangeFromPosition(char.pos),
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
                range: rangeFromPosition(field.pos),
                selectionRange: rangeFromPosition(field.pos)
            });
        }

        return {
            name: state.temporary ? "new state" : "state",
            detail: children.length + " fields",
            kind: SymbolKind.Namespace,
            deprecated: false,
            range: rangeFromPosition(state.pos),
            selectionRange: rangeFromPosition(state.pos),
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
                range: rangeFromPosition(option.pos),
                selectionRange: rangeFromPosition(option.pos),
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
            detail: choice.options.length + " options",
            kind: SymbolKind.Enum,
            deprecated: false,
            range: rangeFromPosition(choice.pos),
            selectionRange: rangeFromPosition(choice.pos),
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
            final blockSymbol = printBlock('then', null, ifStmt.thenBranch);
            result.push({
                name: printValue(ifStmt.condition),
                detail: "condition",
                kind: SymbolKind.Boolean,
                deprecated: false,
                range: rangeFromPosition(ifStmt.pos),
                selectionRange: rangeFromPosition(ifStmt.pos),
                children: blockSymbol.children
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
     * Process a block of nodes.
     * @param name Block name
     * @param detail Block detail text
     * @param block Block node to process
     * @return Document symbol for the block
     */
    function printBlock(name:String, detail:String, block:NBlock):DocumentSymbol {
        final children:Array<DocumentSymbol> = [];

        for (node in block.body) {
            switch HxType.getClass(node) {
                case NChoiceStatement:
                    children.push(printChoice(cast node));
                case NIfStatement:
                    for (symbol in printIf(cast node)) {
                        children.push(symbol);
                    }
                case NStateDecl:
                    children.push(printStateDecl(cast node));
                case _:
                    // Skip other node types
            }
        }

        return {
            name: name,
            detail: detail,
            kind: SymbolKind.Namespace,
            deprecated: false,
            range: rangeFromPosition(block.pos),
            selectionRange: rangeFromPosition(block.pos),
            children: children
        };
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

    /**
     * Convert a Loreline position to an LSP Range.
     * @param pos Loreline position
     * @return LSP Range
     */
    function rangeFromPosition(pos:loreline.Position):Range {
        final start = fromLorelinePosition(pos);
        final end = fromLorelinePosition(pos.withOffset(content, pos.length));
        return {
            start: start,
            end: end
        };
    }

    /**
     * Convert a Loreline position to an LSP Position.
     * @param pos Loreline position
     * @return LSP Position
     */
    function fromLorelinePosition(pos:loreline.Position):loreline.lsp.Protocol.Position {
        return {
            // Convert from 1-based to 0-based indexing
            line: pos.line - 1,
            character: pos.column - 1
        };
    }

}