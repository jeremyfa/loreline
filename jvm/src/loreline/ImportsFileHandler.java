package loreline;

/**
 * Handler for resolving file imports.
 * Called when the parser encounters an import statement and needs to read a file.
 */
@FunctionalInterface
public interface ImportsFileHandler {
    /**
     * Called to resolve a file import.
     *
     * @param path the path of the file to import
     * @return the content of the file as a string, or null if the file cannot be found
     */
    String handle(String path);
}
