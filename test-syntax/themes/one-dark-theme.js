// Theme used to render the syntax test report.
export default {
  name: "one-dark-jeremyfa",
  type: "dark",
  colors: {
    "editor.foreground": "#dddddd",
    "editor.background": "#202020",
    "editorCursor.foreground": "#528bff",
    "editor.lineHighlightBackground": "#282828",
    "editor.selectionBackground": "#424242",
    "editorWhitespace.foreground": "#4b525b"
  },
  tokenColors: [
    {
      name: "Comments",
      scope: ["comment", "punctuation.definition.comment"],
      settings: {
        foreground: "#5c6370",
        fontStyle: "italic"
      }
    },
    {
      name: "Delimiters",
      scope: ["none"],
      settings: {
        foreground: "#a6b2c0"
      }
    },
    {
      name: "Operators",
      scope: ["keyword.operator"],
      settings: {
        foreground: "#dddddd"
      }
    },
    {
      name: "Keywords",
      scope: ["keyword"],
      settings: {
        foreground: "#c678dd"
      }
    },
    {
      name: "Variables",
      scope: ["variable"],
      settings: {
        foreground: "#e06c75"
      }
    },
    {
      name: "Functions",
      scope: [
        "entity.name.function",
        "meta.require",
        "support.function.any-method",
        "entity.name.class"
      ],
      settings: {
        foreground: "#61afef"
      }
    },
    {
      name: "Function calls (Python)",
      scope: [
        "meta.function-call.generic.python",
        "support.function.builtin.python",
        "support.function.magic.python"
      ],
      settings: {
        foreground: "#61afef"
      }
    },
    {
      name: "Classes",
      scope: [
        "entity.name.type.namespace",
        "support.class",
        "entity.name.type.class",
        "entity.name.type"
      ],
      settings: {
        foreground: "#e5c07b"
      }
    },
    {
      name: "Methods",
      scope: ["keyword.other.special-method"],
      settings: {
        foreground: "#61afef"
      }
    },
    {
      name: "Storage",
      scope: ["storage"],
      settings: {
        foreground: "#c678dd"
      }
    },
    {
      name: "Support Type Property Names",
      scope: ["support.type.property-name"],
      settings: {
        foreground: "#dddddd"
      }
    },
    {
      name: "Constants",
      scope: ["constant"],
      settings: {
        foreground: "#d19a66"
      }
    },
    {
      name: "Strings",
      scope: ["string", "entity.other.inherited-class"],
      settings: {
        foreground: "#98c379"
      }
    },
    {
      name: "Regular Expressions",
      scope: ["string.regexp"],
      settings: {
        foreground: "#56b6c2"
      }
    },
    {
      name: "Escape Characters",
      scope: ["constant.character.escape"],
      settings: {
        foreground: "#57b6c2"
      }
    },
    {
      name: "Embedded",
      scope: ["punctuation.section.embedded", "variable.interpolation"],
      settings: {
        foreground: "#be4f44"
      }
    },
    {
      name: "Invalid",
      scope: ["invalid.illegal"],
      settings: {
        background: "#e05252",
        foreground: "#ffffff"
      }
    },
    {
      name: "Broken",
      scope: ["invalid.broken"],
      settings: {
        background: "#e05252",
        foreground: "#ffffff"
      }
    },
    {
      name: "Deprecated",
      scope: ["invalid.deprecated"],
      settings: {
        background: "#d27b53",
        foreground: "#ffffff"
      }
    },
    {
      name: "HTML/XML Tags",
      scope: ["entity.name.tag"],
      settings: {
        foreground: "#e06c75"
      }
    },
    {
      name: "Markup Bold",
      scope: ["markup.bold", "punctuation.definition.bold"],
      settings: {
        foreground: "#d19a66"
      }
    },
    {
      name: "Markup Italic",
      scope: ["markup.italic", "punctuation.definition.italic"],
      settings: {
        foreground: "#c678dd"
      }
    },
    {
      name: "Markup Headings",
      scope: ["markup.heading"],
      settings: {
        foreground: "#e06c75"
      }
    },
    {
      name: "Markup Links",
      scope: ["meta.link"],
      settings: {
        foreground: "#c678dd"
      }
    },
    {
      name: "Markup Lists",
      scope: ["markup.list.punctuation.definition"],
      settings: {
        foreground: "#df6a73"
      }
    },
    {
      name: "Markup Quotes",
      scope: ["markup.quote"],
      settings: {
        foreground: "#d2945d"
      }
    },
    {
      name: "Markup Separator",
      scope: ["meta.separator"],
      settings: {
        background: "#515151",
        foreground: "#a6b2c0"
      }
    },
    {
      name: "Metadata",
      scope: ["storage.modifier.metadata"],
      settings: {
        foreground: "#59bec3"
      }
    },
    {
      name: "DOM",
      scope: ["support.variable.dom"],
      settings: {
        foreground: "#e5c07b"
      }
    },
    {
      name: "Template Expressions",
      scope: [
        "punctuation.definition.template-expression.begin",
        "punctuation.definition.template-expression.end"
      ],
      settings: {
        foreground: "#be5046"
      }
    },
    {
      name: "Meta Tag",
      scope: ["meta.tag"],
      settings: {
        foreground: "#dddddd"
      }
    },
    {
      name: "Preprocessor Directives",
      scope: ["punctuation.definition.tag"],
      settings: {
        foreground: "#8ca0b9"
      }
    }
  ]
};
