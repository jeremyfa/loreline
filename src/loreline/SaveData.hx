package loreline;

/**
 * Values that can be serialized in state fields
 */
typedef SaveDataState = SaveDataFields;

/**
 * Values that can be serialized in character fields
 */
typedef SaveDataCharacter = SaveDataFields;

/**
 * Represents a reference to a beat node
 */
typedef SaveDataBeat = {
    /** The unique ID of the beat node */
    var id:String;
    /** The path of the beat (composed name aaa.bbb...) */
    var path:String;
}

/**
 * Represents a reference to a node
 */
typedef SaveDataNode = {
    /** The unique ID of the node */
    var id:String;
    /** The node type */
    var type:String;
}

/**
 * Represents a scope's state in the save data
 */
typedef SaveDataScope = {
    /** The scope's unique identifier */
    var id:Int;

    /** ID of the associated beat, if any */
    var ?beat:SaveDataBeat;

    /** ID of the associated node, if any */
    var ?node:SaveDataNode;

    /** State data if temporary state is present */
    var ?state:Any;

    /** Beat IDs if scope has beats */
    var ?beats:Array<SaveDataBeat>;

    /** ID of the current head node, if any */
    var ?head:SaveDataNode;
}

/**
 * Values that can be serialized in fields
 */
typedef SaveDataFields = {
    /** Optional type information for special cases */
    var ?type:String;
    /** The actual field values */
    var fields:Any;
}

/**
 * Top-level save data structure
 */
typedef SaveData = {
    /** Save data format version */
    var version:Int;

    /** Current execution stack */
    var stack:Array<SaveDataScope>;

    /** Top level state */
    var state:SaveDataFields;

    /** Character states keyed by name */
    var characters:Dynamic<SaveDataFields>;

    /** Node states keyed by ID */
    var nodeStates:Dynamic<SaveDataFields>;
}
