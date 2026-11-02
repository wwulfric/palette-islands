;;; palette-islands.el --- JetBrains-style minibuffer in a floating panel -*- lexical-binding: t; -*-

;; Copyright (C) 2026 haidao
;; SPDX-License-Identifier: Apache-2.0

;; Author: haidao
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (posframe "1.4") (vertico "2.0") (expui-icons "0.2.2"))
;; Keywords: convenience, frames
;; URL: https://github.com/wwulfric/palette-islands

;;; Commentary:
;; Minibuffer input appears in a child frame instead of the echo area:
;;
;;   palette  top center of the frame: commands, files, buffers and search.
;;   point    under the symbol at point: choices about that symbol, such as
;;            its implementations, references and new name.
;;
;; The child frame only displays the minibuffer buffer.  The minibuffer
;; window stays selected and is scrolled out of sight, so focus never leaves
;; the editor frame: key maps, input methods, recursive minibuffers and
;; `minibuffer-message' keep working.  Messages sent meanwhile show in the
;; panel too.  Vertico draws the candidates; this file places and frames
;; them:
;;
;;     Recent                                         title
;;     🔍 sea                                         input
;;     ──────────────────────────────────────────     divider
;;     BUFFER                                         group title
;;   ( 📄 search.el                           src )   selected row
;;     📄 research.md                        docs
;;
;; Titles, icons and the footer share an outer column; the input and the
;; candidates' names an inner one.  The selected row is a pill (see Pills
;; in palette-islands-draw.el), so rows take their heights from struts rather than
;; from `line-spacing'.
;;
;; Nothing changes until `palette-islands-mode' is on, and nothing is bound
;; by default; bind the commands, or `palette-islands-command-map':
;;
;;   (keymap-global-set "C-c p" palette-islands-command-map)
;;
;; The panel asks the editor around it through the variables in
;; palette-islands-env.el and draws with the faces and sizes here.  Their
;; defaults work in a bare Emacs; a configuration can tie them to its look.

;;; Code:

(require 'posframe)
(require 'expui-icons)
(require 'thingatpt)
(require 'seq)
(require 'vertico)
(require 'palette-islands-env)
(require 'palette-islands-draw)
(require 'palette-islands-candidates)

(defvar vertico--index)
(defvar vertico--total)
(defvar consult-after-jump-hook)

(defface palette-islands '((t (:inherit default)))
  "Text and background of the floating minibuffer panel."
  :group 'palette-islands)

(defface palette-islands-font '((t (:inherit variable-pitch)))
  "Font of the panel's interface text.
Leave colors unspecified; pickers keep code in the code font."
  :group 'palette-islands)

(defface palette-islands-border
  '((((background dark)) (:background "gray35"))
    (t (:background "gray70")))
  "One-pixel outline of the floating minibuffer panel."
  :group 'palette-islands)

(defface palette-islands-edge
  '((((background dark)) (:foreground "gray35"))
    (t (:foreground "gray70")))
  "Side outline drawn in the panel's fringes; follows `palette-islands-border'."
  :group 'palette-islands)

(defface palette-islands-title '((t (:inherit shadow)))
  "Title above the input of the floating minibuffer panel."
  :group 'palette-islands)

(defface palette-islands-divider
  '((((background dark)) (:strike-through "gray25"))
    (t (:strike-through "gray85")))
  "Line between the input and the candidates of the panel."
  :group 'palette-islands)

(defface palette-islands-tab '((t (:inherit shadow)))
  "Tab of the panel's header that is not the current one."
  :group 'palette-islands)

(defface palette-islands-tab-active '((t (:underline t)))
  "Current tab of the panel's header, underlined as the current buffer's tab is."
  :group 'palette-islands)

(defface palette-islands-footer
  '((((background dark)) (:background "gray15"))
    (t (:background "gray96")))
  "Band at the bottom of the panel holding the footer."
  :group 'palette-islands)

(defface palette-islands-header '((t (:inherit palette-islands-footer)))
  "Band at the top of the panel holding the title or tabs."
  :group 'palette-islands)

(defvar palette-islands-placement 'palette
  "Where the next minibuffer appears: `palette', `point', or nil for the echo area.
Let-bind it around code that reads from the minibuffer.")

(defvar palette-islands-anchor nil
  "Frame pixel position (X Y LINE-HEIGHT) for the next panel at `point'.
Or a function returning one, asked each time the panel shows, as windows
may move once the minibuffer opens.  Nil places the panel under the symbol
at point.  Let-bind it, with `palette-islands-placement', to drop a panel down
from a button.")

(defcustom palette-islands-actions
  '((consult-buffer "<" "Narrow"))
  "Keys named at the right of the footer, by command, as (KEY DESCRIPTION).
See `palette-islands-set-action'."
  :type '(alist :key-type symbol :value-type (list string string))
  :group 'palette-islands)

(defcustom palette-islands-top 0.12
  "Top edge of the palette as a fraction of the frame height."
  :type 'number
  :group 'palette-islands)

(defcustom palette-islands-width '(0.55 72 . 120)
  "Palette width: fraction of the frame, then minimum and maximum columns."
  :type '(cons number (cons integer integer))
  :group 'palette-islands)

(defcustom palette-islands-point-width '(48 . 100)
  "Minimum and maximum columns of the panel at point."
  :type '(cons integer integer)
  :group 'palette-islands)

(defcustom palette-islands-rows '((palette . 14) (point . 8))
  "Candidates shown by each placement."
  :type '(alist :key-type symbol :value-type integer)
  :group 'palette-islands)

(defconst palette-islands-padding 12
  "Horizontal padding inside the panel, in pixels.")

(defcustom palette-islands-radius 8
  "Radius of the panel's rounded corners, in pixels."
  :type 'integer
  :group 'palette-islands)

(defcustom palette-islands-edge-height 80
  "Height in 1/10 pt of the empty mode line padding the panel's bottom.
It ends a panel that has no footer band."
  :type 'integer
  :group 'palette-islands)

(defcustom palette-islands-header-height 0.85
  "Height of the title line relative to the panel text."
  :type 'number
  :group 'palette-islands)

(defcustom palette-islands-header-padding 8
  "Space above and below the title line, in pixels."
  :type 'integer
  :group 'palette-islands)

(defcustom palette-islands-input-height 1.1
  "Height of the input relative to the candidates."
  :type 'number
  :group 'palette-islands)

(defconst palette-islands-indent 28
  "Pixels before the input and candidate text, holding the bar and icons.")

(defconst palette-islands-icon-indent 6
  "Pixels before the outer column, after the bar of the selected candidate.
It holds the title, the search icon, group titles, icons and the footer;
the input and the candidates' names start at `palette-islands-indent'.")

(defconst palette-islands-pill-radius 6
  "Radius in pixels of the selected candidate's rounded ends.")

(defconst palette-islands-text-end-inset (* 2 palette-islands-pill-radius)
  "Pixels between candidates' right-aligned text and the selection's end.")

(defcustom palette-islands-row-height 1.85
  "Height of a candidate row, in frame character units."
  :type 'number
  :group 'palette-islands)

(defcustom palette-islands-input-padding '(14 . 4)
  "Pixels above and below the input, as (ABOVE . BELOW).
BELOW adds to the divider row's upper half, so that the input sits midway
between the header's band and the divider.  The cursor runs from the top
of its row, so a strut would lift it off the text; lines this high pad
the input instead."
  :type '(cons integer integer)
  :group 'palette-islands)

(defcustom palette-islands-group-row-height 1.6
  "Height of a group title row, in frame character units."
  :type 'number
  :group 'palette-islands)

(defcustom palette-islands-divider-height 1.0
  "Height of the row holding the divider, in frame character units."
  :type 'number
  :group 'palette-islands)

;;;###autoload
(autoload 'palette-islands-search "palette-islands-search" nil t)
;;;###autoload
(autoload 'palette-islands-search-files "palette-islands-search" nil t)
;;;###autoload
(autoload 'palette-islands-search-commands "palette-islands-search" nil t)
;;;###autoload
(autoload 'palette-islands-search-structure "palette-islands-search" nil t)
;;;###autoload
(autoload 'palette-islands-search-line "palette-islands-search" nil t)
;;;###autoload
(autoload 'palette-islands-search-text "palette-islands-search" nil t)

;;;###autoload
(defvar palette-islands-command-map
  (let ((map (make-sparse-keymap)))
    (define-key map "s" #'palette-islands-search)
    (define-key map "f" #'palette-islands-search-files)
    (define-key map "x" #'palette-islands-search-commands)
    (define-key map "i" #'palette-islands-search-structure)
    (define-key map "l" #'palette-islands-search-line)
    (define-key map "t" #'palette-islands-search-text)
    map)
  "Commands of the search window, to bind under a prefix.")

(defun palette-islands--strut (height)
  "Return a strut making its row HEIGHT frame character units high."
  (palette-islands-draw-strut (ceiling (* (frame-char-height) height))))

(defvar palette-islands--expected nil
  "Timer that hides the panel `palette-islands-expect' keeps up, or nil.")

(defvar-local palette-islands--placement nil
  "Placement of this minibuffer session, or nil when it is not floating.")

(defvar-local palette-islands--editor nil
  "Editor window selected when this minibuffer opened.")

(defvar-local palette-islands--anchor nil
  "Frame pixel position (X Y LINE-HEIGHT) of the symbol for `point'.")

(defvar-local palette-islands--width 0
  "Width in columns of the panel at point, fixed after its first display.")

(defvar-local palette-islands--list nil
  "Non-nil when this panel lists candidates, so that it has a footer.")

(defvar-local palette-islands--status nil
  "Status shown at the left of the footer instead of the detail, or nil.")

(defvar-local palette-islands--action nil
  "Key named at the right of the footer, as (KEY DESCRIPTION), or nil.")

(defvar-local palette-islands--line-face nil
  "Face attributes of a panel's title and footer lines.")

(defvar-local palette-islands--footer-face nil
  "Face attributes of a panel's footer band.")

(defvar-local palette-islands--tabs nil
  "Tabs shown in the header instead of the title, or nil.")

(defvar-local palette-islands--icon nil
  "Overlay showing the search icon in place of the prompt, or nil.")

(defvar-local palette-islands--top nil
  "Overlay padding the panel above its input, or nil.")

(defvar-local palette-islands--bottom nil
  "Overlay padding a panel without a list below its input, or nil.")

(defvar-local palette-islands--top-height 0
  "Pixels of the padding above the input.")

(defvar-local palette-islands--input-start nil
  "Overlay of the space before the input, or nil.")

(defvar-local palette-islands--prefix nil
  "Overlay showing the prefix of the input, or nil.")

(defvar-local palette-islands--outside nil
  "Color under the panel, shown in its cut-off corners.")

(defvar-local palette-islands--edge-face nil
  "Face of the empty mode line padding the bottom of a panel without a list.")

(defvar-local palette-islands--line-heights nil
  "Alist of a header or mode line face and its height in pixels.")

(defvar-local palette-islands--title nil
  "Title of this minibuffer, or nil when it shows its prompt.")

;;;; Placement

(defun palette-islands--origin ()
  "Return the editor window that was selected when the minibuffer opened.
It is kept from the start: a click on the panel selects the panel's own
window."
  (let ((window (or palette-islands--editor (minibuffer-selected-window))))
    (if (and (window-live-p window) (not (frame-parent (window-frame window))))
        window
      (frame-first-window (or (frame-parent) (selected-frame))))))

(defun palette-islands--symbol-anchor (window)
  "Return the frame pixel position of the symbol at point in WINDOW."
  (with-selected-window window
    (let* ((start (or (car (bounds-of-thing-at-point 'symbol)) (point)))
           (xy (and (pos-visible-in-window-p start window)
                    (posn-x-y (posn-at-point start window))))
           (edges (window-inside-pixel-edges window)))
      (when xy
        (list (+ (nth 0 edges) (car xy))
              (+ (nth 1 edges) (cdr xy))
              (save-excursion (goto-char start) (line-pixel-height)))))))

(defun palette-islands--top-center (info)
  "Center the panel horizontally near the top of its frame, per INFO."
  (cons (/ (- (plist-get info :parent-frame-width)
              (plist-get info :posframe-width))
           2)
        (round (* palette-islands-top (plist-get info :parent-frame-height)))))

(defun palette-islands--below-symbol (info)
  "Align the panel's text with the symbol of INFO, below or above its line."
  (pcase-let* ((`(,x ,y ,line) (plist-get info :anchor))
               (width (plist-get info :posframe-width))
               (height (plist-get info :posframe-height))
               (below (+ y line)))
    (cons (max 0 (min (- x palette-islands-padding palette-islands-indent)
                      (- (plist-get info :parent-frame-width) width)))
          (max 0 (if (> (+ below height) (plist-get info :parent-frame-height))
                     (- y height)
                   below)))))

(defun palette-islands--columns (window)
  "Return the palette width in columns for WINDOW's frame."
  (pcase-let ((`(,ratio ,min . ,max) palette-islands-width))
    (max min (min max (round (* ratio (frame-width (window-frame window))))))))

;;;; Display

(defun palette-islands--show ()
  "Display the current minibuffer buffer in its floating panel."
  ;; The panel kept up for this one stops showing the last one's copy.
  (palette-islands--drop-snapshot)
  (let* ((buffer (current-buffer))
         (input (point))
         (anchor (and (eq palette-islands--placement 'point)
                      (if (functionp palette-islands--anchor)
                          (funcall palette-islands--anchor)
                        palette-islands--anchor)))
         (origin (palette-islands--origin))
         (frame
          ;; Poshandlers measure the editor window, not the minibuffer.
          (with-selected-window origin
            ;; The panel never covers the pointer's work: leave it alone.
            (let ((posframe-mouse-banish-function #'ignore))
              (posframe-show
               buffer
               :poshandler (if anchor #'palette-islands--below-symbol
                             #'palette-islands--top-center)
               :poshandler-extra-info (list :anchor anchor)
               ;; At point the first display fits the content; the width
               ;; then stays, so typing or moving never resizes it.
               :width (cond ((not anchor) (palette-islands--columns origin))
                            ((> palette-islands--width 0) palette-islands--width))
               :min-width (when anchor (car palette-islands-point-width))
               :max-width (when anchor (cdr palette-islands-point-width))
               :lines-truncate t
               :cursor (default-value 'cursor-type)
               :window-point input
               :left-fringe palette-islands-padding
               :right-fringe palette-islands-padding
               ;; The panel draws its own rounded outline (see
               ;; `palette-islands--rounded'); a frame border has square corners.
               :border-width 0
               :background-color (face-background 'palette-islands nil t)
               :foreground-color (face-foreground 'palette-islands nil t)
               ;; Its header and mode lines pad the panel (see the setup).
               :respect-header-line t
               :respect-mode-line t
               ;; Struts set the rows' heights; spacing would add to them.
               :override-parameters '((line-spacing . 0))
               :hidehandler #'palette-islands--hidehandler)))))
    ;; The panel shows all of its text.  A window that once scrolled, as when
    ;; it was too short, would keep starting past the icon and the outline.
    (unless (= (window-start (frame-root-window frame)) (point-min))
      (set-window-start (frame-root-window frame) (point-min)))
    (when anchor
      (when (zerop palette-islands--width)
        (setq palette-islands--width (frame-width frame))))
    ;; Fringes are the horizontal padding: paint them like the panel, with
    ;; the side outline at their outer edge.
    (let ((color (face-background 'palette-islands nil t))
          (line (face-background 'palette-islands-border nil t)))
      (unless (equal (face-background 'fringe frame t) color)
        (set-face-background 'fringe color frame))
      (unless (equal (face-foreground 'palette-islands-edge frame t) line)
        (set-face-foreground 'palette-islands-edge line frame)))
    ;; The cut-off corners show what the panel sits on.
    ;; Editor windows have the theme's background, whatever their frame's.
    (setq palette-islands--outside (or (and palette-islands-background-function
                                       (funcall palette-islands-background-function))
                                  (face-background 'default (window-frame origin) t)))))

(defvar palette-islands--echo-height nil
  "Height of the echo area, in pixels, recorded before a panel opens.")

(defun palette-islands--display ()
  "Show this minibuffer in its panel and hide the echo-area copy.
The copy is scrolled out of view; its window keeps the echo area's height,
so the windows above do not move while the panel is open."
  ;; A click on the panel selects its frame; the panel belongs to the
  ;; editor frame.
  (when-let* ((parent (frame-parent)))
    (select-frame parent t))
  (when-let* ((window (active-minibuffer-window))
              ((eq (window-buffer window) (current-buffer))))
    (setq-local resize-mini-windows nil)
    (palette-islands--hold-echo-area t)
    (palette-islands--hide-copy window)
    (palette-islands--show)))

(defvar palette-islands--saved-resize 'unset
  "Default of `resize-mini-windows' while a panel is open, or `unset'.")

(defun palette-islands--hold-echo-area (hold)
  "Keep the echo area's height while panels are open if HOLD, else restore it.
The minibuffer's own nil value applies only while it is current: a
command in another window would let redisplay shrink the echo area to
the hidden input's one line."
  (cond ((and hold (eq palette-islands--saved-resize 'unset))
         (setq palette-islands--saved-resize (default-value 'resize-mini-windows))
         (setq-default resize-mini-windows nil))
        ((and (not hold) (not (eq palette-islands--saved-resize 'unset)))
         (setq-default resize-mini-windows palette-islands--saved-resize)
         (setq palette-islands--saved-resize 'unset))))

(defun palette-islands--hide-copy (window)
  "Scroll the echo-area copy in minibuffer WINDOW out of view, at the echo
area's height."
  (let ((delta (- (or palette-islands--echo-height 0) (window-pixel-height window))))
    (unless (zerop delta)
      (ignore-errors (window-resize window delta nil nil 'pixelwise))))
  (set-window-vscroll window 100))

(defun palette-islands--keep-hidden (&rest _)
  "Keep the echo-area copy of a floating minibuffer out of view.
Events that redraw nothing in the panel, such as the release of the click
that opened it, can grow the window and reset its scroll, showing the copy."
  (when-let* ((window (active-minibuffer-window)))
    (when (buffer-local-value 'palette-islands--placement (window-buffer window))
      (palette-islands--hide-copy window))))

;; After every command, before redisplay: also one the minibuffer runs for
;; such a release.
(add-hook 'post-command-hook #'palette-islands--keep-hidden)

(defun palette-islands--refresh ()
  "Redisplay a floating minibuffer that Vertico does not manage."
  (when (and palette-islands--placement (not (bound-and-true-p vertico--input)))
    (palette-islands--display)))

(defun palette-islands--after-candidates (&rest _)
  "Redisplay the panel whenever Vertico redraws, including async updates."
  (when palette-islands--placement
    (palette-islands--display)))

(defun palette-islands--vertico-resize (resize &rest args)
  "Call RESIZE with ARGS only when the minibuffer is not floating."
  (unless palette-islands--placement
    (apply resize args)))

(defun palette-islands--fit (fit posframe &rest args)
  "Fit POSFRAME as FIT does with ARGS, counting a panel's padding line.
Fitting measures from the window's start, which leaves out the line an
overlay string draws above the input.  A panel's height is set in one
resize: growing it after a fit would show as a flash."
  (let* ((window (frame-root-window posframe))
         (buffer (window-buffer window))
         (padding (and (buffer-local-value 'palette-islands--placement buffer)
                       (buffer-local-value 'palette-islands--top-height buffer))))
    (cond ((not padding) (apply fit posframe args))
          ;; Only the height is fitted; the width is the panel's own.
          ((eq (car (last args)) 'vertically)
           (let ((height (+ (cdr (window-text-pixel-size window nil nil nil nil t))
                            padding)))
             (unless (= height (frame-text-height posframe))
               (set-frame-height posframe height nil t))))
          (t (apply fit posframe args)
             (set-frame-height posframe (+ (frame-text-height posframe) padding) nil t)))))

(defun palette-islands--hidehandler (info)
  "Hide a panel described by INFO once its minibuffer is no longer active.
A panel kept up for the next one stays."
  (and (not palette-islands--expected)
       (not (minibufferp (cdr (plist-get info :posframe-buffer)) t))))

;;;; Structure

(defun palette-islands--title ()
  "Return the title for this minibuffer: its command's, else its prompt."
  (let ((title (or (alist-get this-command palette-islands-titles)
                   (and minibuffer-completion-table
                        (alist-get (completion-metadata-get
                                    (completion-metadata
                                     "" minibuffer-completion-table
                                     minibuffer-completion-predicate)
                                    'category)
                                   palette-islands-category-titles))
                   (string-trim (minibuffer-prompt) "[ \t]+" "[ \t:：]+"))))
    (unless (string-empty-p title) title)))

(defun palette-islands--header ()
  "Return the title line with the title or tabs at the left."
  (concat (palette-islands-draw-space-to palette-islands-icon-indent)
          (or palette-islands--tabs
              (and palette-islands--title
                   (propertize (palette-islands--literal palette-islands--title)
                               'face 'palette-islands-title)))))

(define-fringe-bitmap 'palette-islands-edge-left
  (vector (ash 1 (1- palette-islands-padding))) 1 palette-islands-padding '(top periodic))
(define-fringe-bitmap 'palette-islands-edge-right [1] 1 palette-islands-padding '(top periodic))

(defconst palette-islands--edges
  (concat (propertize " " 'display '(left-fringe palette-islands-edge-left palette-islands-edge))
          (propertize " " 'display '(right-fringe palette-islands-edge-right palette-islands-edge)))
  "Text that draws the side outline in the fringes of its row.")

(defun palette-islands--spacer (height)
  "Return a line HEIGHT pixels high, with the side outline.
Its text is tiny, so the strut alone sets its height."
  (let ((line (concat (palette-islands-draw-strut height) "\n")))
    (add-face-text-property 0 (length line) '(:height 0.1) t line)
    (concat palette-islands--edges line)))

(defun palette-islands--line-height (face)
  "Return the height of a header or mode line in FACE, measured once."
  (or (alist-get face palette-islands--line-heights nil nil #'eq)
      (setf (alist-get face palette-islands--line-heights nil nil #'eq)
            (palette-islands-draw-line-height face))))

(defun palette-islands--rounded (text top)
  "Return TEXT as the panel's TOP line, or else its bottom one.
Its corners are rounded and carry the outline's sides around them."
  (let ((face (cond (top palette-islands--line-face)
                    ((palette-islands--banded-p) palette-islands--footer-face)
                    (t palette-islands--edge-face))))
    (if (not (and palette-islands--outside (display-graphic-p)))
        text
      (palette-islands-draw-rounded-line text palette-islands-radius
                          (palette-islands--line-height face)
                          (plist-get face :background) palette-islands--outside
                          (face-background 'palette-islands-border nil t) top))))

(defun palette-islands--remap (line spec)
  "Draw LINE, `header-line' or `mode-line', with face attributes SPEC.
The minibuffer window has neither line, so only the panel shows them."
  (dolist (face (list line (intern (format "%s-active" line))
                      (intern (format "%s-inactive" line))))
    (when (facep face)
      (setq-local face-remapping-alist
                  (cons (cons face spec)
                        (assq-delete-all face (copy-sequence face-remapping-alist)))))))

(defun palette-islands--literal (text)
  "Return TEXT for the header or footer, which read % as a format directive."
  (string-replace "%" "%%" text))

(defun palette-islands--at-right (text)
  "Return TEXT, in the title and footer size, aligned to the right edge."
  (concat (palette-islands-draw-right-space
           (propertize text 'face `(:inherit palette-islands-font
                                    :height ,palette-islands-header-height)))
          text))

(defun palette-islands--detail (width)
  "Return the full location or description of the selected candidate.
It is shortened from the left to WIDTH columns."
  (when-let* ((palette-islands-detail-function)
              ((>= vertico--index 0))
              (detail (funcall palette-islands-detail-function (vertico--candidate))))
    (propertize (palette-islands--literal (palette-islands-draw-fit-left detail width))
                'face 'shadow)))

(defun palette-islands--banded-p ()
  "Return non-nil when the panel's bottom line is a footer band, not padding.
A list or tabs always have one; another panel, while it has a status."
  (or palette-islands--list palette-islands--tabs palette-islands--status))

(defun palette-islands--lone-padding ()
  "Return the pixels below an input that no candidates follow.
They are as many as the divider's upper half adds, so that the input
sits as it does above candidates."
  (+ (cdr palette-islands-input-padding)
     (/ (ceiling (* (frame-char-height) palette-islands-divider-height)) 2)))

(defun palette-islands--refooter ()
  "Draw this panel's bottom line as a footer band or as padding, as it has.
A panel without a list pads its input above a band as an empty list does."
  (palette-islands--remap 'mode-line (if (palette-islands--banded-p)
                                    palette-islands--footer-face
                                  palette-islands--edge-face))
  (when (overlayp palette-islands--bottom)
    (overlay-put palette-islands--bottom 'after-string
                 (when (and (not palette-islands--list) (palette-islands--banded-p))
                   (let ((strut (copy-sequence (palette-islands-draw-strut (palette-islands--lone-padding)))))
                     (add-face-text-property 0 (length strut) '(:height 0.1) t strut)
                     ;; The cursor stays on the input, as Vertico keeps it.
                     (concat (propertize " " 'cursor t) "\n" palette-islands--edges strut))))))

(defun palette-islands--footer ()
  "Return the bottom line.
A list's footer tells about the selected candidate, or the picker's status,
at the left, and names one key at the right.  Without a list it shows the
status, such as ElDoc's, or else is blank, padding the panel."
  (cond
   ((and (not palette-islands--list) palette-islands--status)
    (concat (palette-islands-draw-space-to palette-islands-icon-indent)
            (palette-islands--literal
             (truncate-string-to-width palette-islands--status
                                       (+ 2 (or (palette-islands-text-width) 80)) nil nil "…"))))
   ((not palette-islands--list)
    " ")
   (t
    (let* ((action (when palette-islands--action
                     (concat (propertize (palette-islands--literal (car palette-islands--action))
                                         'face 'palette-islands-title)
                             " "
                             (propertize (palette-islands--literal (cadr palette-islands--action))
                                         'face 'shadow))))
           (room (- (+ 2 (or (palette-islands-text-width) 80))
                    (if action (+ 3 (string-width action)) 0))))
      (concat (palette-islands-draw-space-to palette-islands-icon-indent)
              (if palette-islands--status
                  (palette-islands--literal (palette-islands-draw-fit-left palette-islands--status room))
                (palette-islands--detail room))
              (and action (palette-islands--at-right action)))))))

(defun palette-islands-set-status (status)
  "Show STATUS at the left of this panel's footer, instead of the detail.
STATUS tells why a list is empty, for example; nil gives the place back to
the selected candidate.  Call it in the minibuffer."
  (when palette-islands--placement
    (let ((banded (palette-islands--banded-p)))
      (setq palette-islands--status status)
      ;; A panel without a list gains or loses its footer band.
      (unless (eq (and banded t) (and (palette-islands--banded-p) t))
        (palette-islands--refooter)
        (palette-islands--display)))
    (force-mode-line-update t)))

(defun palette-islands--eldoc-display (docs _interactive)
  "Show the first of ElDoc's DOCS in the panel's footer, or clear it.
In the echo area ElDoc writes into the mode line of the window above,
which the frame's single status bar leaves no room for."
  (palette-islands-set-status
   (when-let* ((doc (car docs)))
     (let ((text (car (split-string (car doc) "\n")))
           (thing (plist-get (cdr doc) :thing)))
       (if thing
           (concat (propertize (format "%s" thing)
                               'face (or (plist-get (cdr doc) :face) 'palette-islands-title))
                   ": " text)
         text)))))

(defun palette-islands-set-tabs (tabs)
  "Show TABS, a string, in this panel's header instead of its title.
Pickers that are kinds of one search show which kind is open; see
palette-islands-search.el.  Call it in the minibuffer."
  (when palette-islands--placement
    (setq palette-islands--tabs tabs)
    (palette-islands--refooter)
    ;; Every kind of the search shows the search icon, lists or not.
    (when (overlayp palette-islands--icon)
      (overlay-put palette-islands--icon 'display (palette-islands--search-icon)))
    (force-mode-line-update t)))

(defun palette-islands-set-action (key description)
  "Name KEY, a string, and what it does, DESCRIPTION, in this panel's footer.
Each picker names at most one key, one that is easy to miss."
  (when palette-islands--placement
    (setq palette-islands--action (and key (list key description)))
    (force-mode-line-update t)))

(defun palette-islands-text-width ()
  "Return the columns for candidate text in this minibuffer's panel, or nil."
  (when-let* ((palette-islands--placement)
              (frame (bound-and-true-p posframe--frame))
              ((frame-live-p frame)))
    (- (window-body-width (frame-root-window frame))
       (ceiling palette-islands-indent (frame-char-width frame)))))

(defun palette-islands--search-icon ()
  "Return the display of the search icon."
  ;; JetBrains' search icon, in the face's color in the mono style.
  ;; Display strings ignore display properties inside them, so the image
  ;; is the display itself.
  (if (expui-icons-svg-p) (expui-icons-image "general/search") "🔍"))

(defun palette-islands--replace-prompt (search)
  "Hide the prompt, which the title replaces, showing an icon if SEARCH.
The prompt's last character becomes the space before the input, so that
input lines up with candidates, or with the input of other panels."
  (let ((end (minibuffer-prompt-end)))
    (when (> end (1+ (point-min)))
      (let ((icon (make-overlay (point-min) (1- end))))
        (overlay-put icon 'display (if search (palette-islands--search-icon) ""))
        (overlay-put icon 'face 'shadow)
        (overlay-put icon 'before-string (palette-islands-draw-space-to palette-islands-icon-indent))
        (setq palette-islands--icon icon)))
    (when (> end (point-min))
      ;; A display string would ignore an alignment inside it.
      (let ((space (make-overlay (1- end) end)))
        (overlay-put space 'display `(space :align-to (,palette-islands-indent)))
        (setq palette-islands--input-start space)))))

(defun palette-islands-set-prefix (prefix)
  "Show PREFIX, faded, before the input of this panel, or nothing if nil.
It reads as the start of the input, as in VS Code's quick open, without
being part of what is matched.  It is drawn on the prompt's last
characters, so that messages shown after the input stay after it.  Call
it in the minibuffer."
  (when (overlayp palette-islands--input-start)
    (let* ((end (overlay-end palette-islands--input-start))
           (start (overlay-start palette-islands--input-start))
           ;; The space before the input moves one character back, onto the
           ;; icon's last character, to leave the prompt's last one for
           ;; the prefix.
           (room (and prefix (overlayp palette-islands--icon)
                      (> (overlay-end palette-islands--icon)
                         (1+ (overlay-start palette-islands--icon))))))
      (if (not room)
          (progn
            (move-overlay palette-islands--input-start start end)
            (when (overlayp palette-islands--prefix) (delete-overlay palette-islands--prefix)))
        (move-overlay palette-islands--icon (overlay-start palette-islands--icon) (1- start))
        (move-overlay palette-islands--input-start (1- start) start)
        (unless (overlayp palette-islands--prefix)
          (setq palette-islands--prefix (make-overlay start end)))
        (move-overlay palette-islands--prefix start end)
        (overlay-put palette-islands--prefix 'display
                     ;; Plain, not in the bold of the prompt it covers.
                     (propertize (concat prefix " ")
                                 'face `(:inherit shadow :weight normal
                                         :height ,palette-islands-input-height)))))))

(defun palette-islands--divider-args (args)
  "Put a line before the candidate lines in ARGS when they show in a panel.
Padding under the input comes first.  Every line draws the panel's side
outline in the fringes.  Without candidates the input meets the footer;
it is padded as by the divider's upper half then, so that it stays put
when candidates come."
  (pcase-let ((`(,lines) args))
    (cond
     ((not palette-islands--placement) args)
     ((not lines)
      (list (list (palette-islands--spacer
                   (+ (cdr palette-islands-input-padding)
                      (/ (ceiling (* (frame-char-height) palette-islands-divider-height)) 2))))))
     (t
      (list (cons (palette-islands--spacer (cdr palette-islands-input-padding))
                  (mapcar (lambda (line) (concat palette-islands--edges line))
                          (cons (concat
                                 ;; Centered on the divider's smaller text,
                                 ;; whose middle the line runs through.
                                 (propertize (palette-islands--strut palette-islands-divider-height)
                                             'face '(:inherit palette-islands-divider
                                                     :strike-through nil))
                                 (propertize " " 'face 'palette-islands-divider
                                             'display '(space :align-to right))
                                 (propertize "\n" 'face 'palette-islands-divider))
                                lines))))))))

(defvar palette-islands-candidate-map)

(defun palette-islands--format-candidate (format cand prefix &rest args)
  "Call FORMAT with CAND, PREFIX and ARGS, indenting panel candidates.
The indentation holds the row's strut, or the selected row's rounded left
end, then the icon of a file or buffer below the search icon, so that
names line up with the input.  The selected row ends in its rounded right
end.  Vertico puts a space before every alignment in a candidate, so the
indentation is made of exact widths instead.  Emoji and symbols are scaled
to the row, which the panel's height counts on."
  (if (not palette-islands--placement)
      (apply format cand prefix args)
    (let* ((selected (= (nth 1 args) vertico--index))
           (height (ceiling (* (frame-char-height) palette-islands-row-height)))
           (color (and selected (face-background 'vertico-current nil t)))
           (icon (and palette-islands-icon-function
                       (funcall palette-islands-icon-function cand)))
           (icon-width (if icon (car (image-size (get-text-property 0 'display icon) t))
                         0))
           (used (if selected palette-islands-pill-radius 1))
           (line (apply format (palette-islands-draw-fit-tall-glyphs cand)
                        (concat (if selected
                                    ;; Vertico draws the whole row in the
                                    ;; selection's face, this end included.
                                    (palette-islands-draw-pill-end 'left palette-islands-pill-radius height color
                                                    nil (face-background 'palette-islands nil t))
                                  (palette-islands-draw-strut height))
                                (when icon
                                  (prog1 (concat (palette-islands-draw-space
                                                  (- palette-islands-icon-indent used))
                                                 icon)
                                    (setq used (+ palette-islands-icon-indent icon-width))))
                                (palette-islands-draw-space (- palette-islands-indent used))
                                prefix)
                        args)))
      ;; A click chooses the candidate, as RET does.
      (add-text-properties 0 (1- (length line))
                           `(palette-islands-index ,(nth 1 args) keymap ,palette-islands-candidate-map)
                           line)
      (if (not selected)
          line
        ;; Before the newline, which ends every candidate.
        (concat (substring line 0 -1)
                (palette-islands-draw-pill-right palette-islands-pill-radius height color)
                (substring line -1))))))

;;;; Mouse

;; As in JetBrains' lists, the wheel moves the selection and a click
;; chooses.  The panel draws only the rows it shows, so there is nothing
;; to scroll otherwise.  Rows are not highlighted under the pointer: the
;; highlight of a mouse face lingers in child frames.

(defvar-local palette-islands--scrolled 0
  "Pixels the wheel has turned past the last row it moved the selection by.")

(defun palette-islands-scroll (event)
  "Move the selection a row for each line wheel EVENT scrolls.
Lines are as long as the system counts them, a frame line; a touchpad
sends many small turns, which add up until they pass one."
  (interactive "e")
  (with-selected-window (active-minibuffer-window)
    (let ((up (eq (event-basic-type event) 'wheel-up)))
      (if-let* ((pixels (cdr-safe (nth 4 event)))
                ((/= pixels 0)))
          ;; The event's direction follows the system's; its delta need not.
          (let* ((delta (if up (- (abs pixels)) (abs pixels)))
                 (row (frame-char-height))
                 (total (+ delta (if (< (* delta palette-islands--scrolled) 0) 0
                                   palette-islands--scrolled)))
                 (rows (truncate total row)))
            (setq palette-islands--scrolled (- total (* rows row)))
            (unless (zerop rows)
              (vertico-next rows)))
        (vertico-next (if up -1 1))))))

(defun palette-islands-choose (event)
  "Choose the candidate pressed in EVENT, as RET would."
  (interactive "e")
  (when-let* ((object (posn-object (event-start event)))
              ((consp object))
              (index (get-text-property (cdr object) 'palette-islands-index (car object))))
    (with-selected-window (active-minibuffer-window)
      (let ((vertico--index index))
        (call-interactively (keymap-local-lookup "RET"))))))

(defvar-keymap palette-islands-candidate-map
  :doc "Mouse actions on a candidate in the panel."
  ;; On press, as the tabs act; this also keeps it from starting a drag.
  "<down-mouse-1>" #'palette-islands-choose
  "<mouse-1>" #'ignore)

(defun palette-islands--format-group-title (title)
  "Indent group TITLE in a panel like the panel title, outside its items.
It is in capitals, a label rather than an item."
  (if palette-islands--placement
      (concat (palette-islands--strut palette-islands-group-row-height)
              (palette-islands-draw-space-to palette-islands-icon-indent)
              (upcase title))
    title))

(defun palette-islands-text-end ()
  "Return where candidates' right-aligned text ends in this panel, or nil.
It is an `:align-to' position clear of the selected row's rounded end."
  (when palette-islands--placement
    `(- right (,palette-islands-text-end-inset))))

;;;; Session

(defun palette-islands--setup ()
  "Decide where this minibuffer appears before it is first displayed."
  (when (= (minibuffer-depth) 1)
    (setq palette-islands--echo-height (window-pixel-height (minibuffer-window))))
  (setq palette-islands--placement
        (and (display-graphic-p)
             (not (memq this-command palette-islands-ignore-commands))
             palette-islands-placement))
  (when palette-islands--placement
    ;; This is the panel the last one was kept up for.
    (when (timerp palette-islands--expected)
      (cancel-timer palette-islands--expected)
      (setq palette-islands--expected nil))
    ;; One panel at a time: an enclosing one comes back when this exits
    ;; (see `palette-islands--after-exit').
    (when (> (minibuffer-depth) 1)
      (dolist (buffer (buffer-list))
        (when (and (not (eq buffer (current-buffer)))
                   (minibufferp buffer t)
                   (buffer-local-value 'palette-islands--placement buffer))
          (posframe-hide buffer))))
    (setq palette-islands--editor nil
          palette-islands--editor (palette-islands--origin)
          palette-islands--width 0
          palette-islands--anchor (and (eq palette-islands--placement 'point)
                                  (or palette-islands-anchor
                                      (palette-islands--symbol-anchor (palette-islands--origin))))
          palette-islands--list (bound-and-true-p vertico--input)
          palette-islands--title (palette-islands--title))
    (setq-local eldoc-display-functions (list #'palette-islands--eldoc-display))
    (setq-local vertico-count (alist-get palette-islands--placement palette-islands-rows)
                ;; The input's column holds the search icon, not a count.
                vertico-count-format nil
                truncate-lines t
                ;; The selected row reaches the edge; the fringes are padding.
                fringe-indicator-alist (cons '(truncation nil nil) fringe-indicator-alist)
                auto-hscroll-mode 'current-line
                ;; The header line holds the title, the mode line the footer
                ;; of a list or else padding.
                header-line-format '(:eval (palette-islands--rounded (palette-islands--header) t))
                mode-line-format '(:eval (palette-islands--rounded (palette-islands--footer) nil)))
    (let* ((background (face-background 'palette-islands nil t))
           (border (face-background 'palette-islands-border nil t))
           ;; The outline's top runs along the header line, its bottom along
           ;; the mode line; an underline that low lands on the last pixel.
           (top `(:overline ,border :underline nil))
           (bottom `(:overline nil :underline (:color ,border :position 100)))
           (band (face-background 'palette-islands-header nil t))
           (plain `(:box nil :inherit palette-islands-font :background ,background))
           (edge `(:height ,palette-islands-edge-height ,@bottom ,@plain)))
      (setq palette-islands--status nil
            palette-islands--tabs nil
            palette-islands--icon nil
            palette-islands--input-start nil
            palette-islands--prefix nil
            palette-islands--action (alist-get this-command palette-islands-actions)
            palette-islands--edge-face edge
            palette-islands--line-heights nil
            palette-islands--line-face
            `(:height ,palette-islands-header-height ,@top
                      :box (:line-width (0 . ,palette-islands-header-padding) :color ,band)
                      :inherit palette-islands-font :background ,band)
            palette-islands--footer-face
            (let ((band (face-background 'palette-islands-footer nil t)))
              `(:height ,palette-islands-header-height ,@bottom
                        :inherit palette-islands-font :background ,band
                        :box (:line-width (0 . ,palette-islands-header-padding)
                                          :color ,band))))
      (palette-islands--remap 'header-line palette-islands--line-face))
    ;; Interface text in the interface font; pickers keep code in the code
    ;; font.
    (face-remap-add-relative 'default 'palette-islands-font)
    (setq palette-islands--top (make-overlay (point-min) (point-min))
          palette-islands--top-height (car palette-islands-input-padding)
          ;; Advancing both ends keeps it empty after the input.
          palette-islands--bottom (make-overlay (point-max) (point-max) nil t t))
    (overlay-put palette-islands--top 'before-string
                 (concat (palette-islands--spacer palette-islands--top-height) palette-islands--edges))
    (palette-islands--refooter)
    (let ((start (minibuffer-prompt-end)))
      (when palette-islands--title
        (palette-islands--replace-prompt palette-islands--list))
      ;; Typed text grows the overlay, so it keeps the larger size.
      (overlay-put (make-overlay start (point-max) nil nil t)
                   'face `(:height ,palette-islands-input-height)))
    ;; A header line shows only once the frame is tall enough for it, so
    ;; fit the panel again after its first redisplay.
    (run-at-time 0 nil #'palette-islands--refit (current-buffer))
    ;; The command loop runs this once on entry, then after every command.
    (add-hook 'post-command-hook #'palette-islands--refresh 90 t)
    (add-hook 'minibuffer-exit-hook #'palette-islands--exit nil t)))

(defun palette-islands--exit ()
  "Hide the panel after this minibuffer exits.
Deferred so that a prompt which directly follows reuses the visible panel."
  (when-let* ((window (active-minibuffer-window)))
    (set-window-vscroll window 0))
  ;; Never leave the hidden panel selected: keys would go nowhere.
  (when-let* ((parent (frame-parent)))
    (select-frame parent t))
  (run-at-time 0 nil #'palette-islands--after-exit (current-buffer)))

(defvar palette-islands--snapshot nil
  "Copy of a panel's buffer that its panel shows while kept up, or nil.")

(defun palette-islands--frame (buffer)
  "Return the child frame of BUFFER's panel, or nil."
  (seq-find (lambda (frame)
              (and (frame-parent frame)
                   (eq (cdr (frame-parameter frame 'posframe-buffer)) buffer)))
            (frame-list)))

(defun palette-islands--show-snapshot (buffer)
  "Show a copy of BUFFER in its panel, which goes on looking as it does.
The minibuffer itself is reset once it exits."
  (palette-islands--drop-snapshot)
  (when-let* ((frame (palette-islands--frame buffer))
              ((frame-visible-p frame)))
    (let ((window (frame-root-window frame))
          (copy (with-current-buffer buffer (clone-buffer " *palette-snapshot*"))))
      ;; Cloning copies the text and the local variables, not overlays.
      (with-current-buffer buffer
        (dolist (overlay (reverse (overlays-in (point-min) (point-max))))
          (let ((twin (make-overlay (overlay-start overlay) (overlay-end overlay) copy))
                (props (overlay-properties overlay)))
            (while props
              (overlay-put twin (pop props) (pop props))))))
      (setq palette-islands--snapshot copy)
      (set-window-dedicated-p window nil)
      (set-window-buffer window copy t)
      (set-window-start window (with-current-buffer copy (point-min)))
      (set-window-point window (with-current-buffer copy (point)))
      (set-window-dedicated-p window t))))

(defun palette-islands--drop-snapshot ()
  "Give a panel showing a snapshot its own buffer back."
  (when (buffer-live-p palette-islands--snapshot)
    (dolist (frame (frame-list))
      (let ((window (frame-root-window frame)))
        (when (eq (window-buffer window) palette-islands--snapshot)
          (set-window-dedicated-p window nil)
          (set-window-buffer window (cdr (frame-parameter frame 'posframe-buffer)) t)
          (set-window-dedicated-p window t))))
    (kill-buffer palette-islands--snapshot))
  (setq palette-islands--snapshot nil))

(defun palette-islands-expect ()
  "Keep the panel up for a minibuffer about to replace the current one.
Its command may work before it reads, or read from a callback, as a
search switching kinds does; the panel then goes on showing a copy of
this one rather than flashing.  It hides after a second if no panel
comes.  Call it in the minibuffer."
  (when (timerp palette-islands--expected)
    (cancel-timer palette-islands--expected))
  (palette-islands--show-snapshot (current-buffer))
  (setq palette-islands--expected
        (run-at-time 1 nil #'palette-islands--unexpect (current-buffer))))

(defun palette-islands--unexpect (buffer)
  "Stop keeping BUFFER's panel up for another, hiding it unless it is in use."
  (when (timerp palette-islands--expected)
    (cancel-timer palette-islands--expected))
  (setq palette-islands--expected nil)
  (palette-islands--drop-snapshot)
  (palette-islands--after-exit buffer))

(defun palette-islands--after-exit (buffer)
  "Hide BUFFER's panel unless it is active again; show an enclosing one."
  (let* ((window (active-minibuffer-window))
         (active (and window (window-buffer window))))
    (unless (or palette-islands--expected
                (and (eq active buffer)
                     (buffer-local-value 'palette-islands--placement buffer)))
      (posframe-hide buffer))
    (when (and active (not (eq active buffer))
               (buffer-local-value 'palette-islands--placement active))
      (with-current-buffer active
        (palette-islands--display)))
    (unless (and active (buffer-local-value 'palette-islands--placement active))
      (palette-islands--hold-echo-area nil))))

(defun palette-islands--refit (buffer)
  "Show BUFFER's panel again if its minibuffer is still active.
Each fit measures the header and mode lines as the last redisplay drew
them, and they grow as they gain their spacing and corners; fit again
until the panel's height settles.  A list's panel also refits whenever
the list updates, but a panel without one has only this."
  (when (and (minibufferp buffer t)
             (buffer-local-value 'palette-islands--placement buffer))
    (let ((height nil) (tries 0))
      (while (and (< tries 4)
                  (not (eql height (palette-islands--frame-height buffer))))
        (setq height (palette-islands--frame-height buffer)
              tries (1+ tries))
        ;; Let the header line appear first, so the fit counts it.
        (redisplay)
        (with-current-buffer buffer
          (palette-islands--display))))))

(defun palette-islands--frame-height (buffer)
  "Return the pixel height of BUFFER's panel, or nil when it has none."
  (when-let* ((frame (palette-islands--frame buffer)))
    (frame-pixel-height frame)))

(defun palette-islands-active-placement ()
  "Return the placement of the active minibuffer, or nil."
  (when-let* ((window (active-minibuffer-window)))
    (buffer-local-value 'palette-islands--placement (window-buffer window))))

(defun palette-islands-recenter ()
  "Recenter after a jump, keeping a previewed line below the palette."
  (if (eq (palette-islands-active-placement) 'palette)
      (recenter (round (* 0.62 (window-body-height))))
    (recenter)))

(defun palette-islands--nested-exit ()
  "Hide an enclosing panel's echo-area copy again after this minibuffer exits.
All minibuffers share the echo area's window: one nested in a panel's, and
not in a panel itself (such as \\[eval-expression]), resizes and scrolls
it, so the panel's input would show there until the panel next redraws."
  (when (and (> (minibuffer-depth) 1) (not palette-islands--placement))
    (run-at-time 0 nil #'palette-islands--rehide (current-buffer))))

(defun palette-islands--rehide (buffer)
  "Show the panel enclosing BUFFER's minibuffer again, once it has exited.
The redisplay that follows the exit puts the shared window back at the
start of the text; let it happen first, or it undoes the hiding."
  (redisplay t)
  (palette-islands--after-exit buffer))

;;;###autoload
(define-minor-mode palette-islands-mode
  "Show the minibuffer in a floating panel instead of the echo area."
  :global t
  :group 'palette-islands
  (if palette-islands-mode
      (progn
        (add-hook 'minibuffer-setup-hook #'palette-islands--setup 50)
        (add-hook 'minibuffer-exit-hook #'palette-islands--nested-exit)
        (add-hook 'minibuffer-setup-hook #'palette-islands-candidates-forget-roots)
        (advice-add 'posframe--fit-frame-to-buffer :around #'palette-islands--fit)
        (keymap-set vertico-map "<wheel-up>" #'palette-islands-scroll)
        (keymap-set vertico-map "<wheel-down>" #'palette-islands-scroll)
        (advice-add 'vertico--display-candidates :after #'palette-islands--after-candidates)
        (advice-add 'vertico--resize-window :around #'palette-islands--vertico-resize)
        (advice-add 'vertico--display-candidates :filter-args
                    #'palette-islands--divider-args)
        ;; Before the panel's own, which wraps it with the row and the icon.
        (advice-add 'vertico--format-candidate :around
                    #'palette-islands-candidates-format)
        (advice-add 'vertico--format-candidate :around
                    #'palette-islands--format-candidate)
        (advice-add 'vertico--format-group-title :filter-return
                    #'palette-islands--format-group-title)
        (with-eval-after-load 'consult
          (when palette-islands-mode
            (setq consult-after-jump-hook
                  (cons #'palette-islands-recenter
                        (remq #'recenter (remq #'palette-islands-recenter
                                               consult-after-jump-hook)))))))
    (remove-hook 'minibuffer-setup-hook #'palette-islands--setup)
    (remove-hook 'minibuffer-exit-hook #'palette-islands--nested-exit)
    (remove-hook 'minibuffer-setup-hook #'palette-islands-candidates-forget-roots)
    (advice-remove 'posframe--fit-frame-to-buffer #'palette-islands--fit)
    (keymap-unset vertico-map "<wheel-up>")
    (keymap-unset vertico-map "<wheel-down>")
    (advice-remove 'vertico--display-candidates #'palette-islands--after-candidates)
    (advice-remove 'vertico--resize-window #'palette-islands--vertico-resize)
    (advice-remove 'vertico--display-candidates #'palette-islands--divider-args)
    (advice-remove 'vertico--format-candidate #'palette-islands--format-candidate)
    (advice-remove 'vertico--format-candidate #'palette-islands-candidates-format)
    (advice-remove 'vertico--format-group-title #'palette-islands--format-group-title)
    (when (boundp 'consult-after-jump-hook)
      (setq consult-after-jump-hook
            (cons #'recenter (remq #'palette-islands-recenter consult-after-jump-hook))))))

(provide 'palette-islands)
;;; palette-islands.el ends here
