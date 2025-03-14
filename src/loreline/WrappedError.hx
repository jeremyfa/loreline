package loreline;

class WrappedError<T> extends Error {

    public final wrapped:T;

    public function new(wrapped:T, message:String, pos:Position) {
        super(message, pos);
        this.wrapped = wrapped;
    }

}