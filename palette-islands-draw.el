;;; palette-islands-draw.el --- Pixel drawing of the floating panel -*- lexical-binding: t; -*-

;; Copyright (C) 2026 haidao
;; SPDX-License-Identifier: Apache-2.0

;;; Commentary:
;; The panel's own copy of the helpers it draws with: spaces measured in
;; pixels, rows of one height, rounded corners and pills.  Private to the
;; panel, so that it depends on no configuration; the editor's windows have
;; theirs in ui-layout.el.

;;; Code:

(require 'seq)

(defun palette-islands-draw-space (width)
  "Return a space WIDTH pixels wide."
  (propertize " " 'display `(space :width (,(max 0 width)))))

(defun palette-islands-draw-space-to (x)
  "Return a space reaching X pixels from the start of the text area."
  (propertize " " 'display `(space :align-to (,x))))

(defun palette-islands-draw-right-space (text &optional edge buffer)
  "Return a space that ends where TEXT, following it, meets EDGE.
EDGE is an `:align-to' position, `right' by default.  TEXT is measured
with BUFFER's face remapping, as `string-pixel-width' does."
  (propertize " " 'display
              `(space :align-to (- ,(or edge 'right)
                                   (,(string-pixel-width text buffer))))))

(defun palette-islands-draw-fit-left (text width)
  "Return TEXT shortened from the left to WIDTH columns, keeping its end.
The end of a path or place names the file, so it is the part to keep."
  (let ((columns (string-width text)))
    (if (<= columns width)
        text
      (concat "…" (truncate-string-to-width
                   text columns (- columns (max 0 (1- width))))))))

;;;; Tall glyphs

;; A glyph from a fallback font whose ascent or descent exceeds the text
;; font's makes its whole row taller.  Lists that count rows to size a
;; panel then jump when such a glyph scrolls in.  Scaling only those glyphs,
;; to the largest size that still fits the row, keeps every row one height.
;; Only emoji and symbols are considered: CJK text keeps its size.

(defconst palette-islands-draw--glyph-scales '(0.9 0.8 0.7 0.6 0.5)
  "Scales tried, largest first, for a glyph taller than its row.")

(defvar palette-islands-draw--glyph-scale-cache (make-hash-table :test #'equal)
  "Scale for (CHAR FACE-REMAPPING FONT): a number, or t when it fits.")

(defun palette-islands-draw--glyph-candidate-p (char)
  "Return non-nil when CHAR may come from a taller fallback font."
  (and (>= char #x2000)
       (memq (aref char-script-table char) '(emoji symbol))))

(defun palette-islands-draw--row-height (string remapping)
  "Return the pixel height of one row showing STRING under REMAPPING."
  (with-temp-buffer
    (setq-local face-remapping-alist remapping
                line-spacing nil)
    (insert string)
    (cdr (buffer-text-pixel-size nil nil t))))

(defun palette-islands-draw--glyph-scale (char face remapping)
  "Return the scale that fits CHAR in a row of FACE, or nil when it fits."
  (let* ((key (list char face remapping (face-attribute 'default :font)))
         (known (gethash key palette-islands-draw--glyph-scale-cache)))
    (if known
        (and (numberp known) known)
      (let* ((sample (lambda (scale)
                       (let ((glyph (propertize (string char) 'face face)))
                         (when scale
                           (put-text-property 0 1 'display `(height ,scale) glyph))
                         (palette-islands-draw--row-height
                          (concat (propertize "0" 'face face) glyph) remapping))))
             (line (palette-islands-draw--row-height (propertize "0" 'face face) remapping))
             (scale (unless (<= (funcall sample nil) line)
                      (or (seq-find (lambda (scale) (<= (funcall sample scale) line))
                                    palette-islands-draw--glyph-scales)
                          (car (last palette-islands-draw--glyph-scales))))))
        (puthash key (or scale t) palette-islands-draw--glyph-scale-cache)
        scale))))

(defun palette-islands-draw-fit-tall-glyphs (string &optional buffer)
  "Return STRING with glyphs taller than its rows scaled down to fit.
Rows are measured with BUFFER's face remapping, the current buffer's by
default.  Characters that already have a `display' property are kept.
STRING is returned unchanged when nothing needs scaling."
  (if (or (not (display-graphic-p))
          (not (multibyte-string-p string))
          (not (string-match-p "[^\0-῿]" string)))
      string
    (let ((remapping (buffer-local-value 'face-remapping-alist
                                         (or buffer (current-buffer))))
          copy)
      (dotimes (index (length string))
        (let ((char (aref string index)))
          (when-let* (((palette-islands-draw--glyph-candidate-p char))
                      ((not (get-text-property index 'display string)))
                      (scale (palette-islands-draw--glyph-scale
                              char (get-text-property index 'face string) remapping)))
            (unless copy (setq copy (copy-sequence string)))
            (put-text-property index (1+ index) 'display `(height ,scale) copy))))
      (or copy string))))

(defun palette-islands-draw-line-height (face &optional buffer)
  "Return the pixel height of a header or mode line drawn in FACE.
FACE may be a face name or attribute list; BUFFER's face remapping
applies, the current buffer's by default."
  (palette-islands-draw--row-height (propertize " " 'face face)
                     (buffer-local-value 'face-remapping-alist
                                         (or buffer (current-buffer)))))

;;;; Rounded corners

;; A child frame is an opaque rectangle on macOS: neither the native
;; rounded window style nor a transparent background applies to it.  A
;; panel that draws its own outline can still look rounded: images of its
;; corners paint the cut-off part in the color the panel sits on, while
;; everything between them stays native text.

(defvar palette-islands-draw--corner-cache (make-hash-table :test #'equal)
  "Corner strings by (CORNER RADIUS HEIGHT INSIDE OUTSIDE LINE ASCENT).")

(defun palette-islands-draw--svg-color (color)
  "Return COLOR, which may be an Emacs color name, as #RRGGBB."
  (if-let* ((values (and color (color-values color))))
      (apply #'format "#%02x%02x%02x" (mapcar (lambda (v) (/ v 257)) values))
    "none"))

(defun palette-islands-draw-corner (corner radius height inside outside line &optional ascent)
  "Return a string showing CORNER of a rounded box, RADIUS by HEIGHT pixels.
CORNER is `top-left', `top-right', `bottom-left' or `bottom-right'.  The
box is filled with INSIDE and outlined by a one-pixel LINE; the cut-off
corner shows OUTSIDE, the color the box sits on.  The image fills a row
HEIGHT pixels high and ignores the row's box, overline and underline.
ASCENT places it in the row as the image property does, `center' by
default; a row whose height comes from a spacer uses that spacer's ascent.
LINE nil draws no outline."
  (let ((key (list corner radius height inside outside line ascent)))
    (or (gethash key palette-islands-draw--corner-cache)
        (puthash
         key
         (let* ((r radius) (h height) (a (- r 0.5))
                ;; Drawn as the top-left corner, then mirrored.
                (transform (pcase corner
                             ('top-left "")
                             ('top-right (format "translate(%d 0) scale(-1 1)" r))
                             ('bottom-left (format "translate(0 %d) scale(1 -1)" h))
                             ('bottom-right (format "translate(%d %d) scale(-1 -1)" r h))))
                (svg (format "<svg xmlns='http://www.w3.org/2000/svg' width='%d' height='%d'>\
<rect width='%d' height='%d' fill='%s'/>\
<g transform='%s'>\
<path d='M0,%d V%d A%d,%d 0 0 1 %d,0 H%d V%d Z' fill='%s'/>\
<path d='M0.5,%d V%d A%s,%s 0 0 1 %d,0.5' fill='none' stroke='%s' stroke-width='1'/>\
</g></svg>"
                             r h r h (palette-islands-draw--svg-color outside) transform
                             h r r r r r h (palette-islands-draw--svg-color inside)
                             h r a a r (palette-islands-draw--svg-color line))))
           (propertize " " 'face '(:box nil :overline nil :underline nil)
                       'display (create-image svg 'svg t :ascent (or ascent 'center))))
         palette-islands-draw--corner-cache))))

(defun palette-islands-draw-rounded-line (text radius height inside outside line top)
  "Return TEXT between the two corners of a rounded header or mode line.
TOP chooses the top corners, else the bottom ones.  RADIUS, HEIGHT,
INSIDE, OUTSIDE and LINE are as in `palette-islands-draw-corner'."
  (concat (palette-islands-draw-corner (if top 'top-left 'bottom-left)
                        radius height inside outside line)
          text
          (propertize " " 'display
                      `(space :align-to (- (+ right right-fringe right-margin)
                                           (,radius))))
          (palette-islands-draw-corner (if top 'top-right 'bottom-right)
                        radius height inside outside line)))

;;;; Pills

;; A selected row in a list is a pill: a band with rounded ends.  Faces
;; have no rounded corners, so the ends are images as tall as the row.
;; `line-spacing' would add to an image's height, so rows that hold a
;; pill take their height from a strut, an invisible image, instead.

(defvar palette-islands-draw--pill-cache (make-hash-table :test #'equal)
  "Strut and pill end strings by their arguments.")

(defun palette-islands-draw--image-string (svg)
  "Return a string displaying SVG, centered on its row's text as icons are.
The image is loaded at once: a frame fitted to its rows before then would
measure them as tall as their text."
  (let ((image (create-image svg 'svg t :ascent 'center :scale 1)))
    (when (display-images-p)
      (image-size image t))
    (propertize " " 'display image)))

(defun palette-islands-draw-strut (height)
  "Return a one-pixel-wide string that makes its row HEIGHT pixels high.
The row's text stays centered in it."
  (with-memoization (gethash (list nil height) palette-islands-draw--pill-cache)
    (palette-islands-draw--image-string
     (format "<svg xmlns='http://www.w3.org/2000/svg' width='1' height='%d'/>"
             height))))

(defun palette-islands-draw-pill-end (side radius height color &optional margin outside)
  "Return a string showing the SIDE end of a pill, RADIUS pixels round.
SIDE is `left' or `right'.  The end fills a row HEIGHT pixels high in
COLOR, and also sets the row's height as `palette-islands-draw-strut' does.
MARGIN pixels, 0 by default, stay clear outside it: the string is MARGIN plus
RADIUS pixels wide.  The clear part shows OUTSIDE, or else the image's
background, which is that of the face the string is drawn in: pass
OUTSIDE when that face may be the selection's own."
  (let ((margin (or margin 0)))
    (with-memoization (gethash (list side radius height color margin outside)
                               palette-islands-draw--pill-cache)
      (let ((width (+ margin radius)))
        (palette-islands-draw--image-string
         (format "<svg xmlns='http://www.w3.org/2000/svg' width='%d' height='%d'>\
%s<path d='%s' fill='%s'/></svg>"
                 width height
                 (if outside
                     (format "<rect width='%d' height='%d' fill='%s'/>"
                             width height (palette-islands-draw--svg-color outside))
                   "")
                 (if (eq side 'left)
                     (format "M%d,0 A%d,%d 0 0 0 %d,%d V%d A%d,%d 0 0 0 %d,%d Z"
                             width radius radius margin radius
                             (- height radius) radius radius width height)
                   (format "M0,0 A%d,%d 0 0 1 %d,%d V%d A%d,%d 0 0 1 0,%d Z"
                           radius radius radius radius
                           (- height radius) radius radius height))
                 (palette-islands-draw--svg-color color)))))))

(defun palette-islands-draw-pill-right (radius height color &optional margin edge)
  "Return the right end of a pill in COLOR, reaching EDGE from the text before.
EDGE is an `:align-to' position, `right' by default.  RADIUS, HEIGHT and
MARGIN are as in `palette-islands-draw-pill-end'."
  (concat (propertize " " 'face `(:background ,color)
                      'display `(space :align-to (- ,(or edge 'right)
                                                    (,(+ radius (or margin 0))))))
          (palette-islands-draw-pill-end 'right radius height color margin)))

(defun palette-islands-draw--forget-glyph-scales (&rest _)
  "Measure glyphs and draw corners again after fonts or colors change."
  (clrhash palette-islands-draw--glyph-scale-cache)
  (clrhash palette-islands-draw--corner-cache))

(add-hook 'after-setting-font-hook #'palette-islands-draw--forget-glyph-scales)
(add-hook 'enable-theme-functions #'palette-islands-draw--forget-glyph-scales)

(provide 'palette-islands-draw)
;;; palette-islands-draw.el ends here
