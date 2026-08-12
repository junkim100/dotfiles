# No Hard-Wrapped Prose

**One logical line per paragraph, list item, or heading — never wrap prose at a column width.**

- Applies everywhere prose lives: markdown files, docstrings, code comments, YAML/config comments, commit message bodies.
- A newline is a semantic boundary (new paragraph, new list item, table row, code fence) — never a cosmetic one.
- Code itself follows the language formatter (ruff line limits etc.); this rule governs natural-language text only.
- When editing an existing hard-wrapped file, reflow the paragraphs you touch; verify content is unchanged (whitespace-collapsed equality) when reflowing in bulk.
