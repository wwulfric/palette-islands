;;; palette-islands-tests.el --- Tests of the floating panel -*- lexical-binding: t; -*-

;; Copyright (C) 2026 haidao
;; SPDX-License-Identifier: Apache-2.0

;;; Code:

(require 'ert)
(require 'palette-islands-search)

(ert-deftest palette-islands-loads-alone ()
  "The panel loads with its dependencies only."
  (dolist (feature '(lsp-bridge consult marginalia))
    (should-not (featurep feature))))

(ert-deftest palette-islands-load-changes-nothing ()
  "Loading the package leaves the minibuffer alone until the mode is on."
  (should-not palette-islands-mode)
  (should-not (memq #'palette-islands--setup minibuffer-setup-hook)))

(ert-deftest palette-islands-command-map-binds-commands ()
  "Each key of the command map runs a command."
  (map-keymap (lambda (_key command) (should (commandp command)))
              palette-islands-command-map)
  (should (eq (keymap-lookup palette-islands-command-map "s")
              #'palette-islands-search)))

(ert-deftest palette-islands-search-take-input-forgets ()
  "A kind's opening input is taken once, and kinds keep theirs apart."
  (let ((palette-islands-search--opened nil))
    (setf (alist-get 'structure palette-islands-search--opened) "foo"
          (alist-get 'text palette-islands-search--opened) "bar")
    (should (equal (palette-islands-search-take-input 'structure) "foo"))
    (should-not (palette-islands-search-take-input 'structure))
    (should (equal (palette-islands-search-take-input 'text) "bar"))))

(ert-deftest palette-islands-candidate-detail-by-category ()
  "The footer tells a command's documentation and a tagged item's own text."
  (let ((vertico--metadata '(metadata (category . command))))
    (should (equal (palette-islands-candidate-detail "forward-char")
                   (car (split-string (documentation 'forward-char) "\n"))))
    (should (equal (palette-islands-candidate-detail
                    (propertize "x" 'palette-islands-detail "Own"))
                   "Own"))
    (should-not (palette-islands-candidate-detail "no-such-command-here"))))

(ert-deftest palette-islands-candidates-stay-outside-a-panel ()
  "Without a panel, a file candidate reaches Vertico unchanged."
  (let ((vertico--metadata '(metadata (category . file))))
    (should (equal (palette-islands-candidates-format
                    (lambda (candidate &rest _) candidate) "a/b.el" "" "")
                   "a/b.el"))))

(ert-deftest palette-islands-mode-toggles ()
  "The mode's hooks and advice come and go with it."
  (unwind-protect
      (progn
        (palette-islands-mode 1)
        (should (memq #'palette-islands--setup minibuffer-setup-hook))
        (should (advice-member-p #'palette-islands--format-candidate
                                 'vertico--format-candidate)))
    (palette-islands-mode -1))
  (should-not (memq #'palette-islands--setup minibuffer-setup-hook))
  (should-not (advice-member-p #'palette-islands--format-candidate
                               'vertico--format-candidate)))

(ert-deftest palette-islands-search-kinds-are-commands-or-consult-free ()
  "Default kinds need nothing beyond Emacs."
  (dolist (kind palette-islands-search-kinds)
    (should (fboundp (nth 3 kind)))))

(ert-deftest palette-islands-search-typed-without-consult ()
  "A text search reads its input without Consult loaded."
  (with-temp-buffer
    (setq palette-islands-search--current 'text)
    (insert "needle")
    (should (equal (palette-islands-search--typed) "needle"))))

(ert-deftest palette-islands-draw-fit-left-keeps-the-end ()
  (should (equal (palette-islands-draw-fit-left "abcdef" 10) "abcdef"))
  (should (equal (palette-islands-draw-fit-left "abcdef" 4) "…def")))

(provide 'palette-islands-tests)
;;; palette-islands-tests.el ends here
