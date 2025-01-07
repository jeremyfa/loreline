package loreline;

class Async {

    public var func(default,null):(done:()->Void)->Void;

    public function new(func:(done:()->Void)->Void) {
        this.func = func;
    }

}
