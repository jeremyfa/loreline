<?php

namespace Loreline;

use Loreline\Internal\loreline\Json as HxJson;
use Loreline\Internal\loreline\Script as HxScript;

/**
 * A parsed Loreline script AST.
 *
 * Obtain via Loreline::parse(). Pass to Loreline::play() or
 * Loreline::resume() to execute.
 */
class Script extends Node
{
    /**
     * Reconstruct a Script from a JSON string (as returned by toJson()).
     */
    public static function fromJson(string $json): Script
    {
        return new Script(HxScript::fromJson(HxJson::parse($json)));
    }
}
