package loreline.lib;

import loreline.Node;

class GoNode {

    public final node:Node;

    public function new(node:Node) {
        this.node = node;
    }

    @:go.Export
    public function type():String {
        return node.type();
    }

    @:go.Export
    public function line():Int {
        return node.pos != null ? node.pos.line : 0;
    }

    @:go.Export
    public function column():Int {
        return node.pos != null ? node.pos.column : 0;
    }

    @:go.Export
    public function offset():Int {
        return node.pos != null ? node.pos.offset : 0;
    }

    @:go.Export
    public function length():Int {
        return node.pos != null ? node.pos.length : 0;
    }

    @:go.Export
    public function id():String {
        return node.id.toString();
    }

    @:go.Export
    public function toJson(pretty:Bool):String {
        return loreline.Json.stringify(node.toJson(), pretty);
    }

}
