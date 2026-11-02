;;; palette-islands-search.el --- One search window for several kinds of results -*- lexical-binding: t; -*-

;; Copyright (C) 2026 haidao
;; SPDX-License-Identifier: Apache-2.0

;;; Commentary:
;; As in VS Code's quick open, one window searches files, and a prefix typed
;; into the empty input switches the kind of results.  By default:
;;
;;   >  commands     @  this file's structure
;;   :  line         %  text in the project
;;
;; The prefix stays, faded, at the start of the input; Backspace in the empty
;; input removes it, back to files.  Text searches may start with any
;; character, so there another prefix needs that Backspace first.  Tabs in
;; the panel's header (palette-islands.el) show the kind and switch on click,
;; keeping the input.  The keys of each picker open the window on its tab.
;; The kinds are `palette-islands-search-kinds' (palette-islands-env.el), each
;; a command that reads from the minibuffer; this file binds no keys.

;;; Code:

(require 'seq)
(require 'subr-x)
(require 'palette-islands)

(defvar palette-islands-search--kind nil
  "Kind of the search window being opened.")

(defvar palette-islands-search--input nil
  "Input that the search window being opened starts with.")

(defvar palette-islands-search--opened nil
  "Input that each kind was last opened with, as (KIND . INPUT).")

(defvar-local palette-islands-search--current nil
  "Kind of results in this minibuffer.")

(defvar-local palette-islands-search--parent-map nil
  "Keymap of this minibuffer below `palette-islands-search-map'.")


(defconst palette-islands-search-tab-gap 20
  "Pixels between the tabs of the search window.")

;;;; Switching

(defun palette-islands-search--switch (kind input)
  "Close this search window and open it on KIND with INPUT.
The panel stays up for KIND, whose command may read only later."
  (palette-islands-expect)
  (throw 'palette-islands-search-switch (list kind input)))

(defun palette-islands-search-run (kind input &optional command)
  "Show KIND with INPUT by COMMAND, or by KIND's own, following switches."
  (let ((next (list kind input command)))
    (while next
      (setq next
            (catch 'palette-islands-search-switch
              (pcase-let ((`(,kind ,input ,command) next))
                (let ((palette-islands-search--kind kind)
                      (palette-islands-search--input input))
                  (setf (alist-get kind palette-islands-search--opened) input)
                  (let* ((command (or command (nth 3 (assq kind palette-islands-search-kinds))))
                         ;; Consult reads its per-command settings, such as
                         ;; previews, by `this-command'.
                         (this-command command))
                    (minibuffer-with-setup-hook (:append #'palette-islands-search--setup)
                      (call-interactively command)))))
              nil)))))

(defvar consult-async-split-style)
(defvar consult-async-split-styles-alist)

(defun palette-islands-search--typed ()
  "Return what was typed into this search window.
Text searches start with Consult's separator, such as #, which is not."
  (let ((input (minibuffer-contents-no-properties))
        (initial (and (eq palette-islands-search--current 'text)
                      (plist-get (alist-get (bound-and-true-p consult-async-split-style)
                                            (bound-and-true-p consult-async-split-styles-alist))
                                 :initial))))
    (if (and initial (string-prefix-p (string initial) input))
        (substring input 1)
      input)))

(defun palette-islands-search--prefix ()
  "Switch kinds when a prefix is typed into the empty input.
Text searches keep it: they may start with any character."
  (unless (eq palette-islands-search--current 'text)
    (when-let* ((typed (palette-islands-search--typed))
                ((= (length typed) 1))
                (kind (car (seq-find (lambda (entry) (equal (nth 1 entry) typed))
                                     palette-islands-search-kinds)))
                ((not (eq kind palette-islands-search--current))))
      (palette-islands-search--switch kind nil))))

(defun palette-islands-search-backspace ()
  "Delete backwards, or remove the prefix of an empty input, back to files."
  (interactive)
  (if (and (not (eq palette-islands-search--current 'files))
           (string-empty-p (palette-islands-search--typed)))
      (palette-islands-search--switch 'files nil)
    (call-interactively (or (and palette-islands-search--parent-map
                                 (lookup-key palette-islands-search--parent-map (kbd "DEL")))
                            #'delete-backward-char))))

(defvar-keymap palette-islands-search-map
  "DEL" #'palette-islands-search-backspace)

(defun palette-islands-search-take-input (kind)
  "Return the input KIND was last opened with, and forget it.
A command whose candidates arrive later, such as from a language server,
reopens KIND with this by `palette-islands-search-run'."
  (prog1 (alist-get kind palette-islands-search--opened)
    (setf (alist-get kind palette-islands-search--opened nil t) nil)))

;;;; Tabs

(defun palette-islands-search--tabs (current)
  "Return the header tabs of the search window, CURRENT being open."
  (mapconcat
   (pcase-lambda (`(,kind ,prefix ,label ,_))
     (let ((map (make-sparse-keymap)))
       ;; Act on press, as the sidebar's toolbar does; this also keeps the
       ;; press from starting a header-line drag.
       (define-key map [header-line down-mouse-1]
                   (lambda () (interactive)
                     (palette-islands-search--switch kind (minibuffer-contents-no-properties))))
       (define-key map [header-line mouse-1] #'ignore)
       ;; No mouse face: a highlight box lingers in child frames, and the
       ;; hand pointer already marks the tabs.
       (propertize label
                   'face (if (eq kind current) 'palette-islands-tab-active 'palette-islands-tab)
                   'pointer 'hand 'local-map map
                   'help-echo (if prefix
                                  (format "Search %s, or type %s" (downcase label) prefix)
                                (format "Search %s" (downcase label))))))
   palette-islands-search-kinds
   (propertize " " 'display `(space :width (,palette-islands-search-tab-gap)))))

(defun palette-islands-search--setup ()
  "Prepare the minibuffer of a search window."
  (setq palette-islands-search--current palette-islands-search--kind
        palette-islands-search--parent-map (current-local-map))
  (use-local-map (make-composed-keymap palette-islands-search-map palette-islands-search--parent-map))
  (palette-islands-set-tabs (palette-islands-search--tabs palette-islands-search--kind))
  (palette-islands-set-prefix (nth 1 (assq palette-islands-search--kind palette-islands-search-kinds)))
  (when (eq palette-islands-search--kind 'files)
    (palette-islands-set-action (string-join (delq nil (mapcar #'cadr palette-islands-search-kinds)) " ")
                           "Switch"))
  (add-hook 'post-command-hook #'palette-islands-search--prefix nil t)
  (when palette-islands-search--input
    (insert palette-islands-search--input)))

;;;; Commands

;;;###autoload
(defun palette-islands-search ()
  "Search files; a first prefix searches another kind.
The kinds and their prefixes are `palette-islands-search-kinds'."
  (interactive)
  (palette-islands-search-run 'files nil))

(defmacro palette-islands-search-define (kind)
  "Define the command `palette-islands-search-KIND', opening the window on KIND."
  `(defun ,(intern (format "palette-islands-search-%s" kind)) ()
     ,(format "Open the search window on %s." kind)
     (interactive)
     (palette-islands-search-run ',kind nil)))

(palette-islands-search-define files)
(palette-islands-search-define commands)
(palette-islands-search-define structure)
(palette-islands-search-define line)
(palette-islands-search-define text)

(provide 'palette-islands-search)
;;; palette-islands-search.el ends here
