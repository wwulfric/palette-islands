;;; demo-bare.el --- Palette Islands in an unconfigured Emacs -*- lexical-binding: t; -*-

;; Run in a graphical Emacs with -Q, loading only Palette Islands and its
;; dependencies (see docs/screenshots.md).  It works in a fresh temporary
;; project.  No theme, font, face or UI option is set.

(require 'vertico)
(require 'palette-islands)
(require 'palette-islands-search)

(defvar palette-islands-demo-root (file-name-as-directory
                                   (make-temp-file "palette-islands-demo-" t)))

(defun palette-islands-demo-write (path text)
  "Write TEXT to PATH in the demo project."
  (let ((file (expand-file-name path palette-islands-demo-root)))
    (make-directory (file-name-directory file) t)
    (with-temp-file file (insert text))))

(palette-islands-demo-write "README.md" "# Atlas\n\nA small search engine.\n")
(palette-islands-demo-write "LICENSE" "Demo fixture for Palette Islands screenshots.\n")
(palette-islands-demo-write "docs/ranking.md" "# Ranking\n\nRank documents by matched terms.\n")
(palette-islands-demo-write "docs/usage.md" "# Usage\n\nCall atlas-search with a list of terms.\n")
(palette-islands-demo-write "src/index.el" ";;; index.el --- Build an index -*- lexical-binding: t; -*-\n\n(provide 'index)\n")
(palette-islands-demo-write
 "src/search.el"
 ";;; search.el --- Search an index -*- lexical-binding: t; -*-\n\n(require 'cl-lib)\n\n(defvar atlas-stop-words '(\"a\" \"an\" \"the\")\n  \"Terms left out of a search.\")\n\n(defun atlas-terms (query)\n  \"Split QUERY into terms to search for.\"\n  (seq-difference (split-string (downcase query)) atlas-stop-words))\n\n(defun atlas-score (doc terms index)\n  \"Count how many of TERMS match DOC in INDEX.\"\n  (seq-count (lambda (term) (member doc (gethash term index))) terms))\n\n(defun atlas-search (index terms)\n  \"Rank documents matching TERMS in INDEX.\"\n  (let ((scores (make-hash-table)))\n    (dolist (term terms)\n      (dolist (doc (gethash term index))\n        (cl-incf (gethash doc scores 0))))\n    (sort (hash-table-keys scores)\n          (lambda (a b)\n            (> (gethash a scores)\n               (gethash b scores))))))\n\n(provide 'search)\n")
(palette-islands-demo-write "test/search-tests.el" ";;; Search ranking tests\n(require 'ert)\n\n(atlas-search index '(\"rank\"))\n")

;; Make it a project, for `project-find-file'.  No commit is needed.
(let ((default-directory palette-islands-demo-root))
  (call-process "git" nil nil nil "init" "-q" "-b" "main")
  (call-process "git" nil nil nil "add" "."))

;; Keep the demo out of the user's list of projects.
(setq project-list-file (expand-file-name ".git/projects.eld" palette-islands-demo-root))

(vertico-mode 1)
(palette-islands-mode 1)
(find-file (expand-file-name "src/search.el" palette-islands-demo-root))
(message "Demo project: %s" palette-islands-demo-root)
;; Open after startup has drawn the frame; the panel then waits for input.
(run-with-idle-timer 0.5 nil #'palette-islands-search)

;;; demo-bare.el ends here
