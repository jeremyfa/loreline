<?php

namespace Loreline;

/**
 * A tag embedded in text content, used for styling or other purposes.
 */
final class TextTag
{
    public function __construct(
        /** The value or name of the tag. */
        public readonly string $value,
        /** The offset in the text where this tag appears. */
        public readonly int $offset,
        /** Whether this is a closing tag. */
        public readonly bool $closing,
    ) {
    }
}
