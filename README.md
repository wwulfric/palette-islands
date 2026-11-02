# Palette Islands

A JetBrains-style floating panel for the Emacs minibuffer, on top of
[Vertico](https://github.com/minad/vertico) and
[posframe](https://github.com/tumashu/posframe), with one search window that
switches kinds by prefix, as in Search Everywhere and VS Code's quick open.

[中文](README.zh-CN.md)

- The minibuffer shows in a child frame with rounded corners, a header, a
  divider and a footer. Focus never leaves the editor, so key maps, input
  methods and recursive minibuffers keep working.
- Two placements: `palette` at the top of the frame, and `point` under the
  symbol at point or a button.
- A typed prefix switches the search window between files, commands, structure,
  line and text. Tabs in the header show the kind and switch on click.

## Requirements

Emacs 29.1 or later with SVG support, Vertico (with its dependency compat),
posframe and [expui-icons](https://github.com/wwulfric/expui-icons). Consult is
optional. On text terminals the minibuffer stays in the echo area.

The panel advises Vertico's and posframe's internal functions:
`vertico--display-candidates`, `vertico--format-candidate`,
`vertico--resize-window` and `posframe--fit-frame-to-buffer`. It is tested with
Vertico 2.15 and posframe 1.5.3; other versions may need changes.

## Setup

```elisp
(require 'vertico)
(vertico-mode 1)
(require 'palette-islands-search)
(palette-islands-mode 1)
(keymap-global-set "s-p" #'palette-islands-search)
```

Nothing is bound and nothing changes until `palette-islands-mode` is on.

## Asking the editor around it

The panel never calls into your configuration. Set these instead
(`palette-islands-env.el`):

| Variable | Purpose |
| --- | --- |
| `palette-islands-background-function` | The color the panel sits on, shown in its cut-off corners. |
| `palette-islands-icon-function` | A candidate's icon. Nil shows none. |
| `palette-islands-detail-function` | A candidate's location or description, in the footer. Nil shows none. |
| `palette-islands-titles` | Panel titles by command. |
| `palette-islands-category-titles` | Panel titles by completion category. |
| `palette-islands-ignore-commands` | Commands whose minibuffer stays in the echo area. |
| `palette-islands-search-kinds` | Kinds of the search window: `(KIND PREFIX LABEL COMMAND)`. |

For example, searching with Consult and adding a language server's symbols:

```elisp
(setq palette-islands-search-kinds
      '((files nil "Files" project-find-file)
        (commands ">" "Commands" execute-extended-command)
        (structure "@" "Structure" consult-imenu)
        (symbols "#" "Symbols" my-workspace-symbol)
        (line ":" "Line" consult-goto-line)
        (text "%" "Text" consult-ripgrep)))
(palette-islands-search-define symbols)
```

`palette-islands-search-define` makes a command that opens the window on a kind,
here `palette-islands-search-symbols`. Commands exist already for the default
kinds.

Colors are faces (`palette-islands`, `palette-islands-border`,
`palette-islands-footer` and others in the `palette-islands` group), with light
and dark defaults. The font of interface text is `palette-islands-font`.

## For other packages

Let-bind `palette-islands-placement` around code that reads from the minibuffer
(`palette`, `point`, or nil for the echo area), and `palette-islands-anchor` to
drop a panel from a button. In the minibuffer, `palette-islands-set-status`,
`palette-islands-set-action`, `palette-islands-set-tabs` and
`palette-islands-set-prefix` fill the header and footer.

## Development

```bash
make compile test DEPS=/path/to/packages
```

## License

Apache-2.0.
