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

        public Node(Runtime.Node runtimeNode)
        {
            this.RuntimeNode = runtimeNode;
            this.Type = runtimeNode.type();
            this.Id = runtimeNode.id;
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