// Theme used to render the syntax test report.
export default {
  "name": "github-light-custom",
  "type": "light",
  "colors": {
    "editor.foreground": "#24292e"
  },
  "tokenColors": [
    {
      "scope": [
        "comment",
        "punctuation.definition.comment",
        "string.comment"
      ],
      "settings": {
        "foreground": "#6a737d"
      }
    },
    {
      "scope": [
        "constant",
        "entity.name.constant",
        "variable.other.constant",
        "variable.other.enummember",
        "variable.language"
      ],
      "settings": {
        "foreground": "#005cc5"
      }
    },
    {
      "scope": [
        "entity",
        "entity.name"
      ],
      "settings": {
        "foreground": "#6f42c1"
      }
    },
    {
      "scope": "variable.parameter.function",
      "settings": {
        "foreground": "#24292e"
      }
    },
    {
      "scope": [
        "meta.function-call.generic.python",
        "support.function.builtin.python",
        "support.function.magic.python"
      ],
      "settings": {
        "foreground": "#6f42c1"
      }
    },
    {
      "scope": "entity.name.tag",
      "settings": {
        "foreground": "#22863a"
      }
    },
    {
      "scope": "keyword",
      "settings": {
        "foreground": "#d73a49"
      }
    },
    {
      "scope": [
        "storage",
        "storage.type"
      ],
      "settings": {
        "foreground": "#d73a49"
      }
    },
    {
      "scope": [
        "storage.modifier.package",
        "storage.modifier.import",
        "storage.type.java"
      ],
      "settings": {
        "foreground": "#24292e"
      }
    },
    {
      "scope": [
        "string",
        "punctuation.definition.string",
        "string punctuation.section.embedded source"
      ],
      "settings": {
        "foreground": "#032f62"
      }
    },
    {
      "scope": "support",
      "settings": {
        "foreground": "#005cc5"
      }
    },
    {
      "scope": "meta.property-name",
      "settings": {
        "foreground": "#005cc5"
      }
    },
    {
      "scope": "variable",
      "settings": {
        "foreground": "#e36209"
      }
    },
    {
      "scope": "variable.other",
      "settings": {
        "foreground": "#2b6cb0"
      }
    },
    {
      "scope": "invalid.broken",
      "settings": {
        "fontStyle": "italic",
        "foreground": "#b31d28"
      }
    },
    {
      "scope": "invalid.deprecated",
      "settings": {
        "fontStyle": "italic",
        "foreground": "#b31d28"
      }
    },
    {
      "scope": "invalid.illegal",
      "settings": {
        "fontStyle": "italic",
        "foreground": "#b31d28"
      }
    },
    {
      "scope": "invalid.unimplemented",
      "settings": {
        "fontStyle": "italic",
        "foreground": "#b31d28"
      }
    },
    {
      "scope": "carriage-return",
      "settings": {
        "background": "#d73a49",
        "content": "^M",
        "fontStyle": "italic underline",
        "foreground": "#fafbfc"
      }
    },
    {
      "scope": "message.error",
      "settings": {
        "foreground": "#b31d28"
      }
    },
    {
      "scope": "string variable",
      "settings": {
        "foreground": "#005cc5"
      }
    },
    {
      "scope": [
        "source.regexp",
        "string.regexp"
      ],
      "settings": {
        "foreground": "#032f62"
      }
    },
    {
      "scope": [
        "string.regexp.character-class",
        "string.regexp constant.character.escape",
        "string.regexp source.ruby.embedded",
        "string.regexp string.regexp.arbitrary-repitition"
      ],
      "settings": {
        "foreground": "#032f62"
      }
    },
    {
      "scope": "string.regexp constant.character.escape",
      "settings": {
        "fontStyle": "bold",
        "foreground": "#22863a"
      }
    },
    {
      "scope": "support.constant",
      "settings": {
        "foreground": "#005cc5"
      }
    },
    {
      "scope": "support.variable",
      "settings": {
        "foreground": "#005cc5"
      }
    },
    {
      "scope": "meta.module-reference",
      "settings": {
        "foreground": "#005cc5"
      }
    },
    {
      "scope": "punctuation.definition.list.begin.markdown",
      "settings": {
        "foreground": "#e36209"
      }
    },
    {
      "scope": [
        "markup.heading",
        "markup.heading entity.name"
      ],
      "settings": {
        "fontStyle": "bold",
        "foreground": "#005cc5"
      }
    },
    {
      "scope": "markup.quote",
      "settings": {
        "foreground": "#22863a"
      }
    },
    {
      "scope": "markup.italic",
      "settings": {
        "fontStyle": "italic",
        "foreground": "#24292e"
      }
    },
    {
      "scope": "markup.bold",
      "settings": {
        "fontStyle": "bold",
        "foreground": "#24292e"
      }
    },
    {
      "scope": [
        "markup.underline"
      ],
      "settings": {
        "fontStyle": "underline"
      }
    },
    {
      "scope": [
        "markup.strikethrough"
      ],
      "settings": {
        "fontStyle": "strikethrough"
      }
    },
    {
      "scope": "markup.inline.raw",
      "settings": {
        "foreground": "#005cc5"
      }
    },
    {
      "scope": [
        "markup.deleted",
        "meta.diff.header.from-file",
        "punctuation.definition.deleted"
      ],
      "settings": {
        "background": "#ffeef0",
        "foreground": "#b31d28"
      }
    },
    {
      "scope": [
        "markup.inserted",
        "meta.diff.header.to-file",
        "punctuation.definition.inserted"
      ],
      "settings": {
        "background": "#f0fff4",
        "foreground": "#22863a"
      }
    },
    {
      "scope": [
        "markup.changed",
        "punctuation.definition.changed"
      ],
      "settings": {
        "background": "#ffebda",
        "foreground": "#e36209"
      }
    },
    {
      "scope": [
        "markup.ignored",
        "markup.untracked"
      ],
      "settings": {
        "background": "#005cc5",
        "foreground": "#f6f8fa"
      }
    },
    {
      "scope": "meta.diff.range",
      "settings": {
        "fontStyle": "bold",
        "foreground": "#6f42c1"
      }
    },
    {
      "scope": "meta.diff.header",
      "settings": {
        "foreground": "#005cc5"
      }
    },
    {
      "scope": "meta.separator",
      "settings": {
        "fontStyle": "bold",
        "foreground": "#005cc5"
      }
    },
    {
      "scope": "meta.output",
      "settings": {
        "foreground": "#005cc5"
      }
    },
    {
      "scope": [
        "brackethighlighter.tag",
        "brackethighlighter.curly",
        "brackethighlighter.round",
        "brackethighlighter.square",
        "brackethighlighter.angle",
        "brackethighlighter.quote"
      ],
      "settings": {
        "foreground": "#586069"
      }
    },
    {
      "scope": "brackethighlighter.unmatched",
      "settings": {
        "foreground": "#b31d28"
      }
    },
    {
      "scope": [
        "constant.other.reference.link",
        "string.other.link"
      ],
      "settings": {
        "fontStyle": "underline",
        "foreground": "#032f62"
      }
    }
  ]
};
