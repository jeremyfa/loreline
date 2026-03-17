using System;
using Runtime = Loreline.Runtime;
using Internal = Loreline.Internal;
using System.Collections.Generic;

namespace Loreline
{
    public struct NodeId
    {
        public readonly long Value;

        public NodeId(long value)
        {
            Value = value;
        }

        public static implicit operator NodeId(long value)
        {
            return new NodeId(value);
        }

        public static explicit operator long(NodeId id)
        {
            return id.Value;
        }

        public static explicit operator string(NodeId id)
        {
            return id.ToString();
        }

        public override string ToString()
        {
            return Runtime._Node.NodeId_Impl_.toString(Value);
        }
    }

    /// <summary>
    /// Represents a node in a Loreline AST.
    /// </summary>
    public class Node
    {
        /// <summary>
        /// The underlying runtime node instance.
        /// </summary>
        public readonly Runtime.Node RuntimeNode;

        /// <summary>
        /// The type of the node as string
        /// </summary>
        public readonly string Type;

        /// <summary>
        /// The id of this node (should be unique within a single script hierarchy)
        /// </summary>
        public readonly NodeId Id;

        /// <summary>
        /// The line number in the source code where this node appears (1-based).
        /// </summary>
        public readonly int Line;

        /// <summary>
        /// The column number in the source code where this node appears (1-based).
        /// </summary>
        public readonly int Column;

        /// <summary>
        /// The absolute character offset from the start of the source code.
        /// </summary>
        public readonly int Offset;

        /// <summary>
        /// The length of the source text span this node represents.
        /// A value of 0 indicates a point position rather than a span.
        /// </summary>
        public readonly int Length;

        public Node(Runtime.Node runtimeNode)
        {
            this.RuntimeNode = runtimeNode;
            this.Type = runtimeNode.type();
            this.Id = runtimeNode.id;
            var pos = runtimeNode.pos;
            this.Line = pos.line;
            this.Column = pos.column;
            this.Offset = pos.offset;
            this.Length = pos.length;
        }

        /// <summary>
        /// Converts the node to a JSON representation.
        /// This can be used for debugging or serialization purposes.
        /// </summary>
        /// <param name="pretty">Whether to format the JSON with indentation and line breaks</param>
        /// <returns>A JSON string representation of the node</returns>
        public string ToJson(bool pretty = false)
        {
            return Runtime.Json.stringify(RuntimeNode.toJson(), pretty);
        }
    }
}