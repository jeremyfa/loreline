package loreline;

import loreline.Node;
import loreline.Position;

using StringTools;

class Reference<T:Node> {

    public var target:T;

    public var origin:Node;

    public function new(target:T, origin:Node) {
        this.target = target;
        this.origin = origin;
    }

}

/**
 * Utility class for analyzing Loreline scripts without executing them.
 * Provides methods for finding nodes, variables, references, etc.
 */
class Lens {
    /** The script being analyzed */
    final script:Script;

    /** Map of all nodes by their unique ID */
    final nodesById:Map<Int, Node> = [];

    /** Map of node IDs to their parent nodes */
    final parentNodes:Map<Int, Node> = [];

    /** Map of node IDs to their child nodes */
    final childNodes:Map<Int, Array<Node>> = [];

    public function new(script:Script) {
        this.script = script;
        initialize();
    }

    /**
     * Initialize all the lookups and analysis data
     */
    function initialize() {
        // First pass: Build node maps and collect definitions
        script.each((node, parent) -> {
            // Track nodes by ID
            nodesById.set(node.id, node);

            // Track parent relationships
            if (parent != null) {
                parentNodes.set(node.id, parent);

                // And track the other way around
                var children = childNodes.get(parent.id);
                if (children == null) {
                    children = [];
                    childNodes.set(parent.id, children);
                }
                children.push(node);
            }
        });
    }

    /**
     * Gets the node at the given position
     * @param pos Position to check
     * @return Most specific node at that position, or null if none found
     */
    public function getNodeAtPosition(pos:Position):Null<Node> {
        var bestMatch:Null<Node> = null;

        script.each((node, parent) -> {
            final nodePos = node.pos;
            if (nodePos.length > 0 &&
                nodePos.offset <= pos.offset &&
                nodePos.offset + nodePos.length >= pos.offset) {

                bestMatch = node;
            }
        });

        return bestMatch;
    }

    /**
     * Gets the closest node before or at the given position
     * @param pos Position to check
     * @return Most specific node at that position or before, or null if none found
     */
    public function getClosestNodeAtOrBeforePosition(pos:Position):Null<Node> {
        var bestMatch:Null<Node> = null;
        var bestDistance:Int = 999999999;

        script.each((node, parent) -> {
            final nodePos = node.pos;
            final distance = pos.offset - nodePos.offset;
            if (distance >= 0 && distance < bestDistance) {
                bestDistance = distance;
                bestMatch = node;
            }
        });

        return bestMatch;
    }

    /**
     * Gets all nodes of a specific type
     * @param nodeType Class type to find
     * @return Array of matching nodes
     */
    public function getNodesOfType<T:Node>(nodeType:Class<T>):Array<T> {
        final matches:Array<T> = [];
        script.each((node, _) -> {
            if (Std.isOfType(node, nodeType)) {
                matches.push(cast node);
            }
        });
        return matches;
    }

    /**
     * Gets the parent node of a given node
     * @param node Child node
     * @return Parent node or null if none found
     */
    public function getParentNode(node:Node):Null<Node> {
        return parentNodes.get(node.id);
    }

    /**
     * Gets the parent node of a given node
     * @param node Child node
     * @return Parent node or null if none found
     */
    public function getFirstParentOfType<T:Node>(node:Node, type:Class<T>):Null<T> {
        var current:Any = node;
        while (current != null) {
            current = getParentNode(current);
            if (current != null && Type.getClass(current) == type) {
                return current;
            }
        }
        return null;
    }

    /**
     * Gets all ancestor nodes of a given node
     * @param node Starting node
     * @return Array of ancestor nodes from immediate parent to root
     */
    public function getAncestors(node:Node):Array<Node> {
        final ancestors:Array<Node> = [];
        var current = node;
        while (current != null) {
            current = parentNodes.get(current.id);
            if (current != null) {
                ancestors.push(current);
            }
        }
        return ancestors;
    }

    /**
     * Finds all nodes that match a predicate function
     * @param predicate Function that returns true for matching nodes
     * @return Array of matching nodes
     */
    public function findNodes(predicate:(node:Node) -> Bool):Array<Node> {
        final matches:Array<Node> = [];
        script.each((node, _) -> {
            if (predicate(node)) {
                matches.push(node);
            }
        });
        return matches;
    }

    public function resolveArrayAccess(access:NArrayAccess):Null<Node> {
        // First resolve the target array
        var targetNode:Null<Node> = null;

        // If target is itself an access expression, resolve it recursively
        if (access.target is NAccess) {
            targetNode = resolveAccess(cast access.target);
        }
        // If target is array access, resolve it recursively
        else if (access.target is NArrayAccess) {
            targetNode = resolveArrayAccess(cast access.target);
        }

        // If we couldn't resolve the target, we can't resolve the array access
        if (targetNode == null) {
            return null;
        }

        // Check what kind of node we got for the target
        switch Type.getClass(targetNode) {
            case NLiteral:
                final literal:NLiteral = cast targetNode;
                // Only arrays can be indexed
                if (literal.type == Array) {
                    final elements:Array<Dynamic> = cast literal.value;
                    // Try to resolve static numeric indices only
                    if (access.index is NLiteral) {
                        final indexLit:NLiteral = cast access.index;
                        if (indexLit.type == Number) {
                            final index:Int = Std.int(indexLit.value);
                            if (index >= 0 && index < elements.length) {
                                // Get the element at the index if it's a node
                                final element = elements[index];
                                if (Std.isOfType(element, Node)) {
                                    return cast element;
                                }
                            }
                        }
                    }
                }

            case NObjectField:
                // If the target resolves to an object field,
                // check if that field's value is an array
                final field:NObjectField = cast targetNode;
                if (field.value is NLiteral) {
                    final literal:NLiteral = cast field.value;
                    if (literal.type == Array) {
                        final elements:Array<Dynamic> = cast literal.value;
                        // Try to resolve static numeric indices only
                        if (access.index is NLiteral) {
                            final indexLit:NLiteral = cast access.index;
                            if (indexLit.type == Number) {
                                final index:Int = Std.int(indexLit.value);
                                if (index >= 0 && index < elements.length) {
                                    // Get the element at the index if it's a node
                                    final element = elements[index];
                                    if (Std.isOfType(element, Node)) {
                                        return cast element;
                                    }
                                }
                            }
                        }
                    }
                }

            case _:
                // Other node types cannot be indexed
        }

        return null;
    }

    /**
     * Resolves an identifier access to its corresponding node in the AST.
     * Resolution follows the same priority order as the interpreter:
     * 1. State fields in current scope and parent beats
     * 2. Top-level state fields
     * 3. Top-level character declarations
     * 4. Beat declarations
     *
     * @param access The access expression to resolve
     * @return The referenced node if found, null otherwise
     */
    public function resolveAccess(access:NAccess):Null<Node> {
        // First handle field access (obj.field)
        if (access.target != null) {
            // Recursively resolve the target object
            var targetNode = if (access.target is NAccess) {
                resolveAccess(cast access.target);
            }
            // If target is array access, resolve it recursively
            else if (access.target is NArrayAccess) {
                resolveArrayAccess(cast access.target);
            }
            else {
                null;
            }

            if (targetNode != null) {

                if (targetNode is NObjectField) {
                    targetNode = (cast targetNode:NObjectField).value;
                }

                switch Type.getClass(targetNode) {
                    case NCharacterDecl:
                        // If target is a character, look for field in its fields
                        final characterDecl:NCharacterDecl = cast targetNode;
                        for (prop in characterDecl.fields) {
                            if (prop.name == access.name) {
                                return prop;
                            }
                        }
                    case NLiteral:
                        // If target is a literal, check if it is an object
                        final literal:NLiteral = cast targetNode;
                        switch literal.type {
                            case Object(style):
                                final fields:Array<NObjectField> = cast literal.value;
                                for (field in fields) {
                                    if (field.name == access.name) {
                                        return field;
                                    }
                                }
                            case _:
                        }
                    case _:
                }
            }

            return null;
        }

        // Handle direct identifier resolution
        final name = access.name;
        if (name == null) return null;

        // 1. Look for state fields in current scope and parent beats
        var currentBeat = getFirstParentOfType(access, NBeatDecl);
        while (currentBeat != null) {
            // Check for state declarations in this beat
            var result:Null<Node> = null;
            traverse(currentBeat, (node, parent) -> {
                if (result != null) return false;

                if (node is NStateDecl) {
                    final stateDecl:NStateDecl = cast node;
                    for (field in stateDecl.fields) {
                        if (field.name == name) {
                            result = field;
                            return false;
                        }
                    }
                }
                return true;
            });

            if (result != null) {
                return result;
            }

            // Move up to parent beat
            currentBeat = getFirstParentOfType(currentBeat, NBeatDecl);
        }

        // 2. Look for fields in top-level state declarations
        var stateField:Null<Node> = null;
        traverse(script, (node, parent) -> {
            if (stateField != null) return false;

            if (node is NStateDecl) {
                final stateDecl:NStateDecl = cast node;
                for (field in stateDecl.fields) {
                    if (field.name == name) {
                        stateField = field;
                        return false;
                    }
                }
            }
            return false;
        });
        if (stateField != null) {
            return stateField;
        }

        // 3. Look for a top-level character declaration
        final characterDecl = findCharacterByNameFromNode(name, access);
        if (characterDecl != null) {
            return characterDecl;
        }

        // 4. Finally, look for a beat declaration
        final beatDecl = findBeatByNameFromNode(name, access);
        if (beatDecl != null) {
            return beatDecl;
        }

        // Nothing found
        return null;
    }

    /**
     * Finds and returns the beat declaration referenced by the given call.
     * This method searches through the beat declarations to find a match based on the call's fields.
     * @param call The call object containing the reference to search for
     * @return The referenced beat declaration if found, null otherwise
     */
    public function findBeatFromAccess(access:NAccess):Null<NBeatDecl> {

        if (access.target == null && access.name != null) {
            return findBeatByNameFromNode(access.name, access);
        }

        return null;

    }

    /**
     * Finds and returns the beat declaration referenced by the given transition.
     * This method searches through the beat declarations to find a match based on the transition's fields.
     * @param transition The transition object containing the reference to search for
     * @return The referenced beat declaration if found, null otherwise
     */
    public function findBeatFromTransition(transition:NTransition):Null<NBeatDecl> {

        return findBeatByNameFromNode(transition.target, transition);

    }

    public function findBeatByNameFromNode(name:String, node:Node):Null<NBeatDecl> {

        var result:Null<NBeatDecl> = null;

        // Look for beats inside other beats, in parent scopes
        var parentBeat = getFirstParentOfType(node, NBeatDecl);
        while (parentBeat != null) {
            traverse(parentBeat, (child, parent) -> {
                if (result != null || child == node) {
                    return false;
                }
                else if (child is NBeatDecl) {
                    final beatDecl:NBeatDecl = cast child;
                    if (beatDecl.name == name) {
                        result = beatDecl;
                    }
                    return false;
                }
                return true;
            });
            parentBeat = getFirstParentOfType(parentBeat, NBeatDecl);
        }

        // If nothing found, look at
        // top level beat declarations
        if (result == null) {
            traverse(script, (child, parent) -> {
                if (result == null && (child is NBeatDecl)) {
                    final beatDecl:NBeatDecl = cast child;
                    if (beatDecl.name == name) {
                        result = beatDecl;
                    }
                }
                return false;
            });
        }

        return result;

    }

    /**
     * Finds and returns the character declaration referenced by the given dialogue statement.
     * This method searches through the character declarations to find a match based on the
     * dialogue's character name.
     *
     * @param dialogue The dialogue statement containing the character reference
     * @return The referenced character declaration if found, null otherwise
     */
    public function findCharacterFromDialogue(dialogue:NDialogueStatement):Null<NCharacterDecl> {

        return findCharacterByNameFromNode(dialogue.character, dialogue);

    }

    public function findCharacterByNameFromNode(name:String, node:Node):Null<NCharacterDecl> {

        var result:Null<NCharacterDecl> = null;

        // Look at top-level character declarations
        traverse(script, (child, parent) -> {
            if (result == null && (child is NCharacterDecl)) {
                final characterDecl:NCharacterDecl = cast child;
                if (characterDecl.name == name) {
                    result = characterDecl;
                }
            }
            return false;
        });

        return result;

    }

    public function getVisibleCharacters():Array<NCharacterDecl> {

        final result:Array<NCharacterDecl> = [];

        for (node in script.declarations) {
            if (node is NCharacterDecl) {
                result.push(cast node);
            }
        }

        return result;

    }

    /**
     * Gets all state fields visible from a given position.
     * This includes fields from both temporary and permanent states.
     */
    public function getVisibleStateFields(fromNode:Node):Array<NObjectField> {
        final fields:Array<NObjectField> = [];
        final seenFields = new Map<Int, Bool>();

        // Search through ancestor nodes
        var current = fromNode;
        while (current != null) {
            switch Type.getClass(current) {
                case NStateDecl:
                    final state:NStateDecl = cast current;
                    for (field in state.fields) {
                        if (!seenFields.exists(field.id)) {
                            seenFields.set(field.id, true);
                            fields.push(field);
                        }
                    }
                case _:
            }
            current = parentNodes.get(current.id);
        }

        // Add fields from top level states
        script.each((node, parent) -> {
            switch Type.getClass(node) {
                case NStateDecl:
                    final state:NStateDecl = cast node;
                    if (parent == script) { // Only consider top-level states
                        for (field in state.fields) {
                            if (!seenFields.exists(field.id)) {
                                seenFields.set(field.id, true);
                                fields.push(field);
                            }
                        }
                    }
                case _:
            }
        });

        return fields;
    }

    /**
     * Gets all beat declarations available from a given position.
     * This includes both top-level beats and nested beats that are in scope.
     */
    public function getVisibleBeats(fromNode:Node):Array<NBeatDecl> {
        final beats:Array<NBeatDecl> = [];
        final seenBeats = new Map<String, Bool>();

        // Search through ancestor nodes for nested beats
        var current = getParentNode(fromNode);
        while (current != null) {
            switch Type.getClass(current) {
                case NBeatDecl:
                    final parent = getParentNode(current);
                    if (parent != null) {
                        for (child in getNodesOfType(NBeatDecl)) {
                            if (!seenBeats.exists(child.name)) {
                                seenBeats.set(child.name, true);
                                beats.push(child);
                            }
                        }
                    }
                case _:
            }
            current = getParentNode(current);
        }

        // Add top-level beats
        script.each((node, parent) -> {
            switch Type.getClass(node) {
                case NBeatDecl:
                    if (parent == script) {
                        final beat:NBeatDecl = cast node;
                        if (!seenBeats.exists(beat.name)) {
                            seenBeats.set(beat.name, true);
                            beats.push(beat);
                        }
                    }
                case _:
            }
        });

        return beats;
    }

    /**
     * Gets all unique tags used in the script.
     * @return Array of unique tag strings
     */
    public function getAllTags():Array<String> {
        final tags = new Map<String, Bool>();

        // Helper to process string literal
        function processStringLiteral(str:NStringLiteral) {
            for (part in str.parts) {
                switch part.type {
                    case Tag(_, content):
                        // Check if content is a simple string without interpolation
                        if (content.parts.length == 1) {
                            switch content.parts[0].type {
                                case Raw(text):
                                    tags.set(text.trim(), true);
                                case _:
                            }
                        }
                    case _:
                }
            }
        }

        // Traverse AST looking for string literals with tags
        script.each((node, parent) -> {
            switch Type.getClass(node) {
                case NStringLiteral:
                    processStringLiteral(cast node);
                case _:
            }
        });

        // Traverse AST looking for string literals with tags
        script.each((node, parent) -> {
            switch Type.getClass(node) {
                case NStringLiteral:
                    processStringLiteral(cast node);
                case _:
            }
        });

        return [for (tag in tags.keys()) tag];
    }

    /**
     * Count every occurence of tags
     * @return Map of tag counts
     */
    public function countTags():Map<String,Int> {
        final tags = new Map<String, Int>();

        // Helper to process string literal
        function processStringLiteral(str:NStringLiteral) {
            for (part in str.parts) {
                switch part.type {
                    case Tag(_, content):
                        // Check if content is a simple string without interpolation
                        if (content.parts.length == 1) {
                            switch content.parts[0].type {
                                case Raw(text):
                                    text = text.trim();
                                    final prevCount = tags.get(text) ?? 0;
                                    tags.set(text, prevCount + 1);
                                case _:
                            }
                        }
                    case _:
                }
            }
        }

        // Traverse AST looking for string literals with tags
        script.each((node, parent) -> {
            switch Type.getClass(node) {
                case NStringLiteral:
                    processStringLiteral(cast node);
                case _:
            }
        });

        return tags;
    }

    /**
     * Find the state field being accessed by a field access expression
     * @param access The field access to analyze
     * @return The matching state field, if any
     */
    function findStateField(access:NAccess):Null<NObjectField> {
        if (access.target != null) return null; // Only top-level fields

        // Search through visible state fields
        final stateFields = getVisibleStateFields(access);
        for (field in stateFields) {
            if (field.name == access.name) {
                return field;
            }
        }
        return null;
    }

    /**
     * Find all beats that can be reached from a given beat through transitions or calls.
     * @param beatDecl The beat declaration to analyze
     * @return Array of references to reachable beats
     */
    public function findOutboundBeats(beatDecl:NBeatDecl):Array<Reference<NBeatDecl>> {
        final targetBeats:Map<Int, Reference<NBeatDecl>> = new Map();

        // Traverse the beat's body looking for transitions and calls
        traverse(beatDecl, (node, parent) -> {
            switch Type.getClass(node) {
                case NTransition:
                    final transition:NTransition = cast node;
                    final targetBeat = findBeatByNameFromNode(transition.target, transition);
                    if (targetBeat != null) {
                        targetBeats.set(targetBeat.id, new Reference(targetBeat, transition));
                    }

                case NCall:
                    final call:NCall = cast node;
                    // Only check calls that could be beat references
                    if (call.target is NAccess) {
                        final access:NAccess = cast call.target;
                        // Only simple identifiers can be beat references
                        if (access.target == null) {
                            final targetBeat = findBeatFromAccess(access);
                            if (targetBeat != null) {
                                targetBeats.set(targetBeat.id, new Reference(targetBeat, call));
                            }
                        }
                    }

                case _:
            }
            return true;
        });

        return [for (ref in targetBeats) ref];
    }

    /**
     * Finds all nodes that reference a specific beat declaration.
     * @param beatDecl The beat declaration to find references to
     * @return Array of references to this beat
     */
    public function findReferencesToBeat(beatDecl:NBeatDecl):Array<Reference<NBeatDecl>> {
        final references:Array<Reference<NBeatDecl>> = [];

        // Traverse full AST looking for references
        script.each((node, parent) -> {
            switch Type.getClass(node) {
                case NTransition:
                    final transition:NTransition = cast node;
                    if (transition.target == beatDecl.name) {
                        references.push(new Reference(beatDecl, transition));
                    }

                case NCall:
                    final call:NCall = cast node;
                    // Only check calls that could be beat references
                    if (call.target is NAccess) {
                        final access:NAccess = cast call.target;
                        // Only simple identifiers can be beat references
                        if (access.target == null && access.name == beatDecl.name) {
                            final foundBeat = findBeatFromAccess(access);
                            if (foundBeat != null && foundBeat.id == beatDecl.id) {
                                references.push(new Reference(beatDecl, call));
                            }
                        }
                    }

                case _:
            }
        });

        return references;
    }

    /**
     * Finds all state fields that are modified within a given beat
     * @param beatDecl The beat declaration to analyze
     * @return Array of references to modified state fields
     */
    public function findModifiedStateFields(beatDecl:NBeatDecl):Array<Reference<NObjectField>> {
        final modifiedFields:Map<String, Reference<NObjectField>> = new Map();

        // Traverse the beat's body looking for assignments
        traverse(beatDecl, (node, parent) -> {
            switch Type.getClass(node) {
                case NAssign:
                    final assign:NAssign = cast node;

                    // Check target is a field access
                    if (assign.target is NAccess) {
                        final access:NAccess = cast assign.target;
                        final field = findStateField(access);
                        if (field != null) {
                            modifiedFields.set(field.name, new Reference(field, assign));
                        }
                    }

                case _:
            }
            return true;
        });

        // Convert map to array, sorted by field name for consistency
        final refs = [for (ref in modifiedFields) ref];
        refs.sort((a, b) -> {
            final aName = a.target.name.toLowerCase();
            final bName = b.target.name.toLowerCase();
            return aName < bName ? -1 : aName > bName ? 1 : 0;
        });
        return refs;
    }

    /**
     * Finds all state fields that are read/accessed within a given beat
     * @param beatDecl The beat declaration to analyze
     * @return Array of references to read state fields
     */
    public function findReadStateFields(beatDecl:NBeatDecl):Array<Reference<NObjectField>> {
        final readFields:Map<String, Reference<NObjectField>> = new Map();

        // Traverse the beat's body looking for state field reads
        traverse(beatDecl, (node, parent) -> {
            switch Type.getClass(node) {
                case NAccess:
                    final access:NAccess = cast node;

                    // Skip if this access is a target of an assignment
                    if (parent is NAssign) {
                        final assign:NAssign = cast parent;
                        if (assign.target == node) return true;
                    }

                    // Check if it's a state field
                    final field = findStateField(access);
                    if (field != null) {
                        readFields.set(field.name, new Reference(field, access));
                    }

                case _:
            }
            return true;
        });

        // Convert map to array, sorted by field name for consistency
        final refs = [for (ref in readFields) ref];
        refs.sort((a, b) -> {
            final aName = a.target.name.toLowerCase();
            final bName = b.target.name.toLowerCase();
            return aName < bName ? -1 : aName > bName ? 1 : 0;
        });
        return refs;
    }

    /**
     * Find all characters that have a presence in a given beat through:
     * - Field access to character state
     * - Dialogue statements
     * @param beatDecl The beat declaration to analyze
     * @return Array of references to characters involved in the beat
     */
    public function findBeatCharacters(beatDecl:NBeatDecl):Array<Reference<NCharacterDecl>> {
        final characters:Map<Int, Reference<NCharacterDecl>> = new Map();

        // Traverse beat looking for character usage
        traverse(beatDecl, (node, parent) -> {
            switch Type.getClass(node) {
                case NDialogueStatement:
                    // Look for dialogue statements (character: "text")
                    final dialogue:NDialogueStatement = cast node;
                    final character = findCharacterFromDialogue(dialogue);
                    if (character != null) {
                        characters.set(character.id, new Reference(character, dialogue));
                    }

                case NAccess:
                    // Look for character field access (character.field)
                    final access:NAccess = cast node;
                    if (access.target == null) {
                        final character = findCharacterByNameFromNode(access.name, access);
                        if (character != null) {
                            characters.set(character.id, new Reference(character, access));
                        }
                    }

                case _:
            }
            return true;
        });

        // Convert map to array, sorted by character name
        final refs = [for (ref in characters) ref];
        refs.sort((a, b) -> {
            final aName = a.target.name.toLowerCase();
            final bName = b.target.name.toLowerCase();
            return aName < bName ? -1 : aName > bName ? 1 : 0;
        });
        return refs;
    }

    /**
     * Finds all character fields that are modified within a given beat
     * @param beatDecl The beat declaration to analyze
     * @return Array of references to modified character fields
     */
    public function findModifiedCharacterFields(beatDecl:NBeatDecl):Array<Reference<NObjectField>> {
        final used:Map<Int,Bool> = new Map();
        final refs:Array<Reference<NObjectField>> = [];

        // Traverse the beat's body looking for assignments
        traverse(beatDecl, (node, parent) -> {
            switch (Type.getClass(node)) {
                case NAssign:
                    final assign:NAssign = cast node;

                    // Check target is a field access
                    if (assign.target is NAccess) {
                        final access:NAccess = cast assign.target;

                        // Check if we got an object field,
                        // and if so, check if that object field
                        // belongs to a character
                        final resolved = resolveAccess(access);
                        if (resolved is NObjectField) {
                            if (!used.exists(resolved.id)) {
                                final parent = getParentNode(resolved);
                                if (parent is NCharacterDecl) {
                                    used.set(resolved.id, true);
                                    refs.push(new Reference(
                                        cast resolved, node
                                    ));
                                }

                            }
                        }
                    }

                case _:
            }
            return true;
        });

        return refs;
    }

    /**
     * Finds all character fields that are read/accessed within a given beat
     * @param beatDecl The beat declaration to analyze
     * @return Array of references to read character fields
     */
    public function findReadCharacterFields(beatDecl:NBeatDecl):Array<Reference<NObjectField>> {
        final used:Map<Int,Bool> = new Map();
        final refs:Array<Reference<NObjectField>> = [];

        // Traverse the beat's body looking for field reads
        traverse(beatDecl, (node, parent) -> {
            switch (Type.getClass(node)) {
                case NAccess:
                    final access:NAccess = cast node;

                    // Skip if this is an assign (modification)
                    final parent = getParentNode(access);
                    if (parent is NAssign) {
                        final assign:NAssign = cast parent;
                        if (assign.target == access) {
                            return true;
                        }
                    }

                    // Check if we got an object field,
                    // and if so, check if that object field
                    // belongs to a character
                    final resolved = resolveAccess(access);
                    if (resolved is NObjectField) {
                        if (!used.exists(resolved.id)) {
                            final parent = getParentNode(resolved);
                            if (parent is NCharacterDecl) {
                                used.set(resolved.id, true);
                                refs.push(new Reference(
                                    cast resolved, node
                                ));
                            }
                        }
                    }

                case _:
            }
            return true;
        });

        return refs;
    }

    public function traverse(node:Node, callback:(node:Node, parent:Node)->Bool):Void {

        final children = childNodes.get(node.id);
        if (children != null) {
            for (i in 0...children.length) {
                final child = children[i];
                if (callback(child, node)) {
                    traverse(child, callback);
                }
            }
        }

    }

}