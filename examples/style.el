;;; style.el --- Optional Palette Islands styling -*- lexical-binding: t; -*-

;; Load after your theme.  This example needs only Palette Islands and its
;; dependencies; it does not change the global font, theme or mode line.
;; It takes effect from the next panel opened.

(require 'palette-islands)
(require 'expui-icons)

(defun palette-islands-example-icon (candidate)
  "Return the file icon of CANDIDATE when the panel is listing files."
  (when (and (expui-icons-svg-p)
             (memq (completion-metadata-get
                    (completion-metadata (minibuffer-contents-no-properties)
                                         minibuffer-completion-table
                                         minibuffer-completion-predicate)
                    'category)
                   '(file project-file)))
    (expui-icons-icon-for-file candidate)))

(defun palette-islands-example-detail (candidate)
  "Return the first line of the documentation of command CANDIDATE, or nil."
  (when-let* ((symbol (intern-soft candidate))
              ((commandp symbol))
              (doc (ignore-errors (documentation symbol))))
    (car (split-string doc "\n"))))

(setq palette-islands-icon-function #'palette-islands-example-icon
      palette-islands-detail-function #'palette-islands-example-detail
      palette-islands-radius 10
      palette-islands-row-height 1.7
      palette-islands-rows '((palette . 12) (point . 8)))

(custom-set-faces
 '(palette-islands-font ((t (:family "sans-serif"))))
 '(palette-islands-border
   ((((background dark)) (:background "#43454A"))
    (t (:background "#C9CCD6"))))
 '(palette-islands-edge
   ((((background dark)) (:foreground "#43454A"))
    (t (:foreground "#C9CCD6"))))
 '(palette-islands-footer
   ((((background dark)) (:background "#2B2D30"))
    (t (:background "#F2F3F5")))))

(provide 'palette-islands-example-style)
;;; style.el ends here
