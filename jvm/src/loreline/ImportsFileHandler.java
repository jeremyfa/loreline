package loreline;

import java.util.function.Consumer;

/**
 * Handler for resolving file imports. Async-capable: the host receives a
 * callback and must call it (synchronously or later) with the file content
 * — or with {@code null} to signal "file not found".
 *
 * <p>For the typical synchronous case (read the file inline and call back
 * immediately), the implementation is just:</p>
 *
 * <pre>{@code
 * (path, callback) -> callback.accept(readFileSync(path));
 * }</pre>
 *
 * <p>For async loading (e.g. fetching from a network), the implementation
 * may defer the callback until the data arrives.</p>
 */
@FunctionalInterface
public interface ImportsFileHandler {
    /**
     * Called to resolve a file import.
     *
     * @param path     the path of the file to import
     * @param callback function to invoke with the file content (or {@code null}
     *                 if the file cannot be found). Must be called exactly once
     *                 — either synchronously or later.
     */
    void handle(String path, Consumer<String> callback);
}
