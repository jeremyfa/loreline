namespace Loreline
{
    /// <summary>
    /// Base interface to hold loreline values.
    /// This interface allows to map loreline object fields to game-specific objects.
    /// </summary>
    public interface IFields
    {
        /// <summary>
        /// Called when the object has been created from an interpreter
        /// </summary>
        /// <param name="interpreter">The interpreter instance</param>
        void LorelineCreate(Interpreter interpreter);

        /// <summary>
        /// Get the value associated to the given field key
        /// </summary>
        /// <param name="interpreter">The interpreter instance</param>
        /// <param name="key">The field key</param>
        /// <returns>The value associated with the key</returns>
        object LorelineGet(Interpreter interpreter, string key);

        /// <summary>
        /// Set the value associated to the given field key
        /// </summary>
        /// <param name="interpreter">The interpreter instance</param>
        /// <param name="key">The field key</param>
        /// <param name="value">The value to set</param>
        void LorelineSet(Interpreter interpreter, string key, object value);

        /// <summary>
        /// Remove the field associated to the given key
        /// </summary>
        /// <param name="interpreter">The interpreter instance</param>
        /// <param name="key">The field key to remove</param>
        /// <returns>True if the key was found and removed, false otherwise</returns>
        bool LorelineRemove(Interpreter interpreter, string key);

        /// <summary>
        /// Check if a value exists for the given key
        /// </summary>
        /// <param name="interpreter">The interpreter instance</param>
        /// <param name="key">The field key to check</param>
        /// <returns>True if the key exists, false otherwise</returns>
        bool LorelineExists(Interpreter interpreter, string key);

        /// <summary>
        /// Get all the fields of this object
        /// </summary>
        /// <param name="interpreter">The interpreter instance</param>
        /// <returns>An array of field keys</returns>
        string[] LorelineFields(Interpreter interpreter);
    }
}