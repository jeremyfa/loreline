<?php

namespace Loreline;

use Loreline\Internal\loreline\Json as HxJson;
use Loreline\Internal\loreline\Node as HxNode;

/**
 * Base class for Loreline AST nodes.
 *
 * Provides access to the node type, position, unique ID, and JSON export.
 */
class Node
{
    public function __construct(protected mixed $internal)
    {
    }

    /**
     * The raw runtime handle backing this node. Intended for internal use.
     */
    public function internal(): mixed
    {
        return $this->internal;
    }

    /**
     * The type of this node (e.g. "Script", "Beat", "Text").
     */
    public function type(): string
    {
        return $this->internal->type();
    }

    /**
     * The line number in the source code where this node appears (1-based).
     */
    public function line(): int
    {
        return $this->internal->pos->line;
    }

    /**
     * The column number in the source code where this node appears (1-based).
     */
    public function column(): int
    {
        return $this->internal->pos->column;
    }

    /**
     * The absolute character offset from the start of the source code.
     */
    public function offset(): int
    {
        return $this->internal->pos->offset;
    }

    /**
     * The length of the source text span this node represents.
     */
    public function length(): int
    {
        return $this->internal->pos->length;
    }

    /**
     * The human-readable node ID string (e.g. "1.0.0.0").
     */
    public function nodeIdToString(): string
    {
        return $this->internal->id->toString();
    }

    /**
     * Export this node as a JSON string.
     */
    public function toJson(bool $pretty = false): string
    {
        return HxJson::stringify($this->internal->toJson(), $pretty);
    }

    /**
     * Reconstruct a Node from a JSON string (as returned by toJson()).
     */
    public static function fromJson(string $json): Node
    {
        return new Node(HxNode::fromJson(HxJson::parse($json)));
    }
}
