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
        /**
         * Where the tag appears in the text, in characters from its start, the
         * same on every target. Characters, not bytes: use the `mb_` functions,
         * `mb_substr($text, 0, $offset)` is the text before the tag.
         */
        public readonly int $offset,
        /** Whether this is a closing tag. */
        public readonly bool $closing,
    ) {
    }
}
