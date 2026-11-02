# Screenshots

`hero.png` shows Palette Islands inside a personal Emacs configuration.
`emacs-q.png` is a real window capture of graphical Emacs 31.1 on macOS,
started with `-Q`: no init file, theme, font changes or Palette Islands
customization. Only the package and its dependencies are loaded. The window
size is chosen for the screenshot; fonts and native window chrome can differ
between Emacs builds and operating systems.

## Reproduce the bare Emacs demo

From this checkout, with dependencies in sibling directories as in the
Makefile, run:

```sh
emacs -Q -g 120x38 \
  -L "$PWD" -L "$PWD/../compat" -L "$PWD/../vertico" \
  -L "$PWD/../vertico/extensions" -L "$PWD/../posframe" \
  -L "$PWD/../expui-icons" \
  -l "$PWD/scripts/demo-bare.el"
```

Adjust the dependency paths for your installation. On macOS, if launching
the app binary directly does not open a usable window, use
`open -n /Applications/Emacs.app --args` instead of `emacs`.

The script creates a fresh temporary project of fictional files, visits one
and opens the search window using the package's defaults. It does not change
this checkout or your Emacs configuration. The project's path is available in
`palette-islands-demo-root` and in `*Messages*`; it can be removed after
closing the demo Emacs.

Wait for the panel to appear, then capture the Emacs window, without the
desktop or the system's window shadow. The capture includes the native title
bar and toolbar. No UI elements are redrawn or composited.

Each committed PNG then gets a transparent 28-point margin holding a soft drop
shadow and a thin gray outline, following the window's own shape, so that the
window stands out on both light and dark pages. The window's pixels are unchanged.

## Personal configuration capture

The current `hero.png` loads the actual `.emacs.d/early-init.el` and
`.emacs.d/init.el`, including its theme, islands, tabs and sidebar, in a
separate graphical Emacs process, followed by the same demo script. Runtime
files are redirected to a temporary `user-emacs-directory`; the existing
Tree-sitter grammars are linked there. The frame is resized to 1300 × 830
content pixels and `sea` is typed into the search window. It is a window capture,
including native window chrome, with the margin described above.
