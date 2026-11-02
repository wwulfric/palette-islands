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
