using System;
using Runtime = Loreline.Runtime;
using Internal = Loreline.Internal;

namespace Loreline
{
    /// <summary>
    /// Represents the root node of a Loreline script AST.
    /// </summary>
    public class Script : Node
    {
        /// <summary>
        /// The underlying runtime script instance.
        /// </summary>
        public readonly Runtime.Script RuntimeScript;

        /// <summary>
        /// Creates a new Script instance with the provided runtime script.
        /// </summary>
        /// <param name="runtimeScript">The parsed runtime script to wrap</param>
        public Script(Runtime.Script runtimeScript) : base(runtimeScript)
        {
            this.RuntimeScript = runtimeScript;
        }
    }
}