;;; palette-islands-candidates.el --- How candidates read in the floating panel -*- lexical-binding: t; -*-

;; Copyright (C) 2026 haidao
;; SPDX-License-Identifier: Apache-2.0

;;; Commentary:
;; What the panel shows of a candidate, as JetBrains' Search Everywhere does:
;; names before their faded directories, an icon by file type, and in the
;; footer the full location or description of the selected one.  These are
;; the defaults of `palette-islands-icon-function' and
;; `palette-islands-detail-function' (palette-islands-env.el).  A command's
;; own candidates choose by the properties `palette-islands-icon', an expui
;; icon's name, and `palette-islands-detail', text for the footer.

;;; Code:

(require 'expui-icons)
(require 'project)
(require 'subr-x)
(require 'vertico)
(require 'palette-islands-env)
(require 'palette-islands-draw)

(declare-function palette-islands-text-width "palette-islands" ())
(declare-function palette-islands-text-end "palette-islands" ())
(declare-function palette-islands-active-placement "palette-islands" ())
(declare-function xref-item-location "xref" (item))
(declare-function xref-location-group "xref" (location))
(declare-function xref-location-line "xref" (location))

(defvar-local palette-islands-candidates--roots nil
  "Project roots of directories, cached for this minibuffer, or nil.")

(defun palette-islands-candidates--category (candidate)
  "Return (CATEGORY . TARGET) for CANDIDATE of the running completion.
Mixed lists such as `consult-buffer' tag each candidate with its own."
  (or (get-text-property 0 'multi-category candidate)
      (cons (completion-metadata-get vertico--metadata 'category) candidate)))

(defun palette-islands-candidates--root (directory)
  "Return the root of DIRECTORY's project, or nil; remote ones are not looked up."
  (unless palette-islands-candidates--roots
    (setq palette-islands-candidates--roots (make-hash-table :test #'equal)))
  (with-memoization (gethash directory palette-islands-candidates--roots)
    (unless (file-remote-p directory)
      (when-let* ((project (project-current nil directory)))
        (file-name-as-directory (expand-file-name (project-root project)))))))

(defun palette-islands-candidates-forget-roots ()
  "Look up project roots afresh in this minibuffer, whose buffer is reused."
  (setq palette-islands-candidates--roots nil))

(defun palette-islands-candidates--current-root ()
  "Return the root of the project the minibuffer was opened in, or nil.
It is what `palette-islands-project-root-function' says, else the project
of the buffer that was current."
  (if-let* ((root (and palette-islands-project-root-function
                       (funcall palette-islands-project-root-function))))
      (file-name-as-directory (expand-file-name root))
    (let ((window (minibuffer-selected-window)))
      (palette-islands-candidates--root
       (expand-file-name (buffer-local-value 'default-directory
                                             (window-buffer (or window (selected-window)))))))))

(defun palette-islands-candidates--short-directory (directory)
  "Return DIRECTORY as a candidate shows it.
In the current project it is relative to the project's root, and empty
at the root; in another project it starts with that project's name.
Elsewhere it is abbreviated, and relative directories stay as they are."
  (if (not (file-name-absolute-p directory))
      (directory-file-name directory)
    (let* ((directory (file-name-as-directory (expand-file-name directory)))
           (root (palette-islands-candidates--root directory)))
      (directory-file-name
       (cond ((not root) (abbreviate-file-name directory))
             ((equal root (palette-islands-candidates--current-root))
              (if (equal root directory) "" (file-relative-name directory root)))
             (t (concat (file-name-nondirectory (directory-file-name root)) "/"
                        (file-relative-name directory root))))))))

(defun palette-islands-candidates-text-end ()
  "Return the `:align-to' position where right-aligned candidate text ends.
Marginalia runs annotators in the original buffer, so ask the minibuffer."
  (or (when-let* ((window (active-minibuffer-window)))
        (with-current-buffer (window-buffer window)
          (palette-islands-text-end)))
      'right))

(defun palette-islands-candidates--after-name (name directory)
  "Return NAME with DIRECTORY at the right, faded, smaller and shortened from
the left to fit.  DIRECTORY is shown as
`palette-islands-candidates--short-directory' says."
  (let* ((room (or (palette-islands-text-width) 80))
         (width (max 12 (- room (string-width name) 6)))
         (directory (copy-sequence
                     (palette-islands-draw-fit-left
                      (palette-islands-candidates--short-directory directory) width))))
    (if (string-empty-p directory)
        name
      (add-face-text-property 0 (length directory) 'shadow t directory)
      (add-face-text-property 0 (length directory)
                              `(:height ,palette-islands-annotation-height) t directory)
      (concat name
              (palette-islands-draw-right-space
               directory (palette-islands-candidates-text-end) (current-buffer))
              directory))))

(defun palette-islands-candidates--name-first (candidate)
  "Return file CANDIDATE as its name followed by its faded directory."
  (let ((start (string-match-p "[^/]*/?\\'" candidate)))
    (if (and start (> start 0))
        (palette-islands-candidates--after-name (substring candidate start)
                                                (substring candidate 0 start))
      candidate)))

(defun palette-islands-candidates--buffer-directory (name)
  "Return the directory of the file or Dired buffer NAME, or nil."
  (when-let* ((buffer (get-buffer name)))
    (if-let* ((file (buffer-file-name buffer)))
        (file-name-directory file)
      (and (provided-mode-derived-p (buffer-local-value 'major-mode buffer)
                                    'dired-mode)
           (buffer-local-value 'default-directory buffer)))))

(defun palette-islands-candidates--summary (symbol)
  "Return the first line of SYMBOL's documentation, or nil."
  (when-let* ((doc (ignore-errors
                     (if (fboundp symbol)
                         (documentation symbol)
                       (documentation-property symbol 'variable-documentation))))
              ((not (string-empty-p doc))))
    (car (split-string doc "\n"))))

(defun palette-islands-candidate-icon (candidate)
  "Return the icon of CANDIDATE, a file, buffer or tagged item, or nil.
A command names an icon in the `palette-islands-icon' property of its
candidates."
  (when (expui-icons-svg-p)
    (if-let* ((name (get-text-property 0 'palette-islands-icon candidate)))
        (expui-icons-icon name)
      (pcase-let ((`(,category . ,target) (palette-islands-candidates--category candidate)))
        (pcase category
          ((or 'file 'project-file) (expui-icons-icon-for-file target))
          ('buffer (when-let* ((buffer (get-buffer target)))
                     (expui-icons-icon-for-buffer buffer))))))))

(defun palette-islands-candidate-detail (candidate)
  "Return the full location or description of CANDIDATE.
Files, buffers, matches and xrefs have a location; commands, functions
and variables the first line of their documentation.  A command puts it
in the `palette-islands-detail' property of its candidates."
  (or (get-text-property 0 'palette-islands-detail candidate)
      (pcase-let ((`(,category . ,target) (palette-islands-candidates--category candidate)))
        (pcase category
          ((or 'command 'function 'variable 'symbol)
           (when-let* ((symbol (intern-soft target)))
             (palette-islands-candidates--summary symbol)))
          ('consult-grep
           (when (string-match "\\`\\([^:\n]+\\):\\([0-9]+\\):" target)
             (format "%s:%s" (abbreviate-file-name
                              (expand-file-name (match-string 1 target)))
                     (match-string 2 target))))
          ('consult-xref
           (when-let* ((xref (get-text-property 0 'consult-xref target))
                       (location (xref-item-location xref)))
             (format "%s:%s" (abbreviate-file-name (xref-location-group location))
                     (xref-location-line location))))
          ((or 'file 'project-file)
           (abbreviate-file-name (expand-file-name target)))
          ('buffer (when-let* ((buffer (get-buffer target))
                               (file (or (buffer-file-name buffer)
                                         (palette-islands-candidates--buffer-directory target))))
                     (abbreviate-file-name file)))))))

(defun palette-islands-candidates--quiet-annotation (suffix)
  "Return the Marginalia annotation SUFFIX smaller, aligned right by pixels.
Marginalia aligns by columns, which a smaller or proportional font
breaks."
  (if-let* (((> (length suffix) 0))
            (align (text-property-any 0 (length suffix) 'marginalia--align t suffix)))
      (let ((suffix (copy-sequence suffix)))
        (add-face-text-property 0 (length suffix)
                                `(:height ,palette-islands-annotation-height) t suffix)
        (put-text-property align (1+ align) 'display
                           (get-text-property
                            0 'display (palette-islands-draw-right-space
                                        (substring suffix (1+ align))
                                        (palette-islands-candidates-text-end)
                                        (current-buffer)))
                           suffix)
        suffix)
    suffix))

(defun palette-islands-candidates-format (format candidate &rest args)
  "Call FORMAT with CANDIDATE and ARGS, showing names before directories.
Buffers of files or directories follow their name with the directory too.
Matched lines of code stay in the code font where the list uses the
interface font.  Outside a panel candidates stay as they are."
  (if (not (palette-islands-active-placement))
      (apply format candidate args)
    (pcase-let ((`(,category . ,target) (palette-islands-candidates--category candidate)))
      (pcase category
        ((or 'file 'project-file)
         ;; The icon is the file's, not that of the directory now at the end.
         (let ((icon (expui-icons-name-for-file candidate)))
           (setq candidate (copy-sequence (palette-islands-candidates--name-first candidate)))
           (put-text-property 0 (length candidate) 'palette-islands-icon icon candidate)))
        ('buffer
         (when-let* ((directory (palette-islands-candidates--buffer-directory target)))
           (setq candidate (palette-islands-candidates--after-name
                            candidate (abbreviate-file-name directory)))))
        ((or 'consult-grep 'consult-xref)
         (setq candidate (copy-sequence candidate))
         (add-face-text-property 0 (length candidate) 'fixed-pitch t candidate))))
    (pcase-let ((`(,prefix ,suffix . ,rest) args))
      (apply format candidate prefix
             (palette-islands-candidates--quiet-annotation suffix) rest))))

(provide 'palette-islands-candidates)
;;; palette-islands-candidates.el ends here
