;;; palette-islands-env.el --- What the floating panel asks of the editor around it -*- lexical-binding: t; -*-

;; Copyright (C) 2026 haidao
;; SPDX-License-Identifier: Apache-2.0

;;; Commentary:
;; The panel draws itself, but some things belong to the editor it floats
;; in: the color under its cut-off corners, the icon and detail of a
;; candidate, the commands it names or leaves alone, and the kinds of the
;; search window.  Each is a variable here, set to plain defaults that work
;; in any Emacs; a configuration sets them to its own, and the panel never
;; calls into it itself.  Faces are the panel's own, in palette-islands.el.

;;; Code:

(defgroup palette-islands nil
  "Minibuffer in a floating panel."
  :group 'minibuffer)

(defcustom palette-islands-background-function nil
  "Function returning the color the panel sits on, or nil.
Called without arguments when the panel shows; the panel's cut-off corners
paint this color.  Return an Emacs color string.  Nil, or a function
returning nil, means the default face's background on the editor's frame."
  :type '(choice (const nil) function)
  :group 'palette-islands)

(defcustom palette-islands-icon-function nil
  "Function given a candidate, returning its icon as a string, or nil.
The string displays an image in its `display' property.  Nil shows no icons."
  :type '(choice (const nil) function)
  :group 'palette-islands)

(defcustom palette-islands-detail-function nil
  "Function given a candidate, returning text for the panel's footer, or nil.
It tells the candidate's full location or description.  Nil shows nothing."
  :type '(choice (const nil) function)
  :group 'palette-islands)

(defcustom palette-islands-titles
  '((execute-extended-command . "Commands")
    (project-find-file . "Go to File")
    (find-file . "Open File")
    (consult-buffer . "Recent")
    (consult-ripgrep . "Find in Files")
    (consult-imenu . "File Structure"))
  "Panel titles by command.
Completions opened by no command, such as replies of a language server,
are titled by category in `palette-islands-category-titles'; others take their
prompt as title."
  :type '(alist :key-type symbol :value-type string)
  :group 'palette-islands)

(defcustom palette-islands-category-titles
  '((imenu . "File Structure")
    (consult-grep . "Find in Files"))
  "Panel titles by completion category, for completions without a command."
  :type '(alist :key-type symbol :value-type string)
  :group 'palette-islands)

(defcustom palette-islands-ignore-commands nil
  "Commands whose minibuffer stays in the echo area.
Live filters keep their page in view.  Expressions read in a panel show
ElDoc in its footer (see `palette-islands--eldoc-display')."
  :type '(repeat symbol)
  :group 'palette-islands)

(defcustom palette-islands-search-kinds
  '((files nil "Files" project-find-file)
    (commands ">" "Commands" execute-extended-command)
    (structure "@" "Structure" imenu)
    (line ":" "Line" goto-line)
    (text "%" "Text" project-find-regexp))
  "Kinds of results of the search window, as (KIND PREFIX LABEL COMMAND).
The kind `files' is what Backspace in an empty input goes back to."
  :type '(repeat (list symbol (choice (const nil) string) string function))
  :group 'palette-islands)

(provide 'palette-islands-env)
;;; palette-islands-env.el ends here
