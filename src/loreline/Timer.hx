package loreline;

@:structInit
private class PendingTimer {
    public var remaining:Float;
    public var done:()->Void;
}

/**
 * Deferred timer system for non-blocking wait() on game-loop targets.
 *
 * On sys targets, `deferredMode` starts false. Once the host calls
 * `update()` (or `enableDeferredMode()` directly), deferred mode is active
 * and wait() will register timers here instead of blocking with Sys.sleep().
 *
 * For CLI/tool targets that never call update(), wait() falls back to
 * the blocking Sys.sleep() path automatically.
 */
class Timer {

    static var timers:Array<PendingTimer> = [];

    #if sys
    /**
     * True once the host's update loop has been connected.
     * Gates deferred vs. blocking wait() on sys targets.
     */
    public static var deferredMode:Bool = false;

    /**
     * Proactively enable deferred mode without ticking timers.
     * Call this before any interpreter work starts (e.g. in Loreline_createThread)
     * to avoid a race condition where wait() runs before the first update().
     */
    public static function enableDeferredMode():Void {
        deferredMode = true;
    }
    #end

    /**
     * Register a timer to fire `done` after `seconds` have elapsed.
     * Called by wait() when deferred mode is active.
     */
    public static function register(seconds:Float, done:()->Void):Void {
        timers.push({remaining: seconds, done: done});
    }

    /**
     * Tick all pending timers by `delta` seconds, firing any that have expired.
     * Call this every frame from your game loop. The first call also enables
     * deferred mode on sys targets.
     *
     * @param delta Time elapsed since the last frame in seconds.
     */
    public static function update(delta:Float):Void {
        #if sys
        deferredMode = true;
        #end
        if (timers.length == 0) return;
        var i = timers.length;
        while (--i >= 0) {
            final t = timers[i];
            t.remaining -= delta;
            if (t.remaining <= 0.0) {
                timers.splice(i, 1);
                t.done();
            }
        }
    }

}
