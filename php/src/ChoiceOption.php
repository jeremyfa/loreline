<?php

namespace Loreline;

/**
 * A choice option presented to the user.
 */
final class ChoiceOption
{
    public function __construct(
        /** The text of the choice option. */
        public readonly string $text,
        /** Any tags associated with the choice text. @var TextTag[] */
        public readonly array $tags,
        /** Whether this choice option is currently enabled. */
        public readonly bool $enabled,
    ) {
    }
}
