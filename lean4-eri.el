;;; lean4-eri.el --- Lean4-Mode Indentation  -*- lexical-binding: t; -*-

;; Copyright (c) 2005-2010 Ulf Norell, Nils Anders Danielsson,
;; Catarina Coquand, Makoto Takeyama, Andreas Abel, Karl Mehltretter,
;; Marcin Benke, Darin Morrison.

;; This file is not part of GNU Emacs.

;; Licensed under the Apache License, Version 2.0 (the "License"); you
;; may not use this file except in compliance with the License.  You
;; may obtain a copy of the License at
;;
;;     http://www.apache.org/licenses/LICENSE-2.0
;;
;; Unless required by applicable law or agreed to in writing, software
;; distributed under the License is distributed on an "AS IS" BASIS,
;; WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
;; implied.  See the License for the specific language governing
;; permissions and limitations under the License.

;;; Commentary:

;; This file is based on eri.el which was part of Agda-Mode:
;; https://github.com/agda/agda/blob/b40c6fc2e0ced7b547553654f81e5898082d700c/src/data/emacs-mode/eri.el

;;; Code:

(require 'cl-lib)

(defun lean4-eri-current-line-length nil
  "Calculate length of current line."
  (- (line-end-position) (line-beginning-position)))

(defun lean4-eri-current-line-empty nil
  "Return non-nil if the current line is empty (not counting white space)."
  (equal (current-indentation)
         (lean4-eri-current-line-length)))

(defun lean4-eri-maximum (xs)
  "Calculate maximum element in XS.
Returns nil if the list is empty."
  (if xs (apply #'max xs)))

(defun lean4-eri-take (n xs)
  "Return the first N elements of XS."
  (butlast xs (- (length xs) n)))

(defun lean4-eri-split (x xs)
  "Return a pair of lists (XS1 . XS2).
If XS is sorted, then XS = (append XS1 XS2), and all elements in
XS1 are <= X, whereas all elements in XS2 are > X."
  (let* ((pos (or (cl-position-if (lambda (y) (> y x)) xs) (length xs)))
         (xs1 (lean4-eri-take pos xs))
         (xs2 (nthcdr pos xs)))
    (cons xs1 xs2)))

(defun lean4-eri-calculate-indentation-points-on-line (max)
  "Calculate indentation points on current line.
Only points left of column number MAX are included. If MAX is
nil, then all points are included. Points are returned in
ascending order.

Example (positions marked with ^ are returned):

  f x y = g 3 (Just y) 5 4
  ^ ^ ^ ^ ^ ^ ^     ^  |
                       |
                       MAX"
  (let ((result))
    (save-excursion
      (save-restriction
        (beginning-of-line)
                                        ; To make \\` work in the regexp below:
        (narrow-to-region (line-beginning-position) (line-end-position))
        (while
            (progn
              (let ((pos (and (search-forward-regexp
                               "\\(?:\\s-\\|\\`\\)\\(\\S-\\)" nil t)
                              (match-beginning 1))))
                (when pos
                  (let ((pos1 (- pos (line-beginning-position))))
                    (when (or (null max) (< pos1 max))
                      (cl-pushnew pos1 result))))
                (and pos
                     (not (eolp))
                     (or (null max) (< (current-column) max))))))
        (nreverse result) ; Destructive operation.
        ))))

(defun lean4-eri-new-indentation-points ()
  "Calculate new indentation points.
Returns a singleton list containing the column number two steps
in from the indentation of the first non-empty line (white space
excluded) above the current line. If there is no such line,
then the empty list is returned."
  (let ((start (line-beginning-position)))
    (save-excursion
      ; Find a non-empty line above the current one, if any.
      (while
          (progn
            (forward-line -1)
            (not (or (bobp)
                     (not (lean4-eri-current-line-empty))))))
      (if (or (equal (point) start)
              (lean4-eri-current-line-empty))
          nil
        (list (+ 2 (current-indentation)))))))

(defun lean4-eri-calculate-indentation-points (reverse)
  "Calculate points used to indent the current line.
The points are given in reverse order if REVERSE is non-nil. See
`lean4-eri-indent' for a description of how the indentation points are
calculated; note that the current indentation is not included in
the returned list."
  ;; First find a bunch of indentations used above the current line.
  (let ((points)
        (max)
        (start (line-beginning-position)))
    (save-excursion
      (while
          (progn
            (forward-line -1)
            ; Skip the line we started from and lines with nothing but
            ; white space.
            (unless (or (equal (point) start)
                        (lean4-eri-current-line-empty))
              (setq points
                    (append
                     (lean4-eri-calculate-indentation-points-on-line max)
                     points))
              (setq max (car points)))
            ;; Stop after hitting the beginning of the buffer or a
            ;; non-empty, non-indented line.
            (not (or (bobp)
                     (and (equal (current-indentation) 0)
                          (> (lean4-eri-current-line-length) 0)))))))
    ;; Add new indentation points, but remove the current indentation.
    ;; Sort the indentations. Rearrange the points so that the next
    ;; point is the one after the current one. Reverse if necessary.
    ;;
    ;; Note: sort and nreverse are destructive.
    (let* ((ps0 (remove (current-indentation)
                        (append (lean4-eri-new-indentation-points) points)))
           (ps1 (lean4-eri-split (current-indentation) (sort ps0 '<)))
           (ps2 (append (cdr ps1) (car ps1))))
      (if reverse
          (nreverse ps2)
        ps2))))

(defun lean4-eri-indent (&optional reverse)
  "Cycle between some possible indentation points.
With prefix argument REVERSE, cycle in reverse order.

Assume that a file contains the following lines of code, with
point on the line with three dots:

frob = loooooooooooooooooooooooooong identifier
foo = f a b
  where
    f (Foo x) y = let bar = x
                      baz = 3 + 5

...

^ ^ ^ ^    ^  ^ ^ ^   ^ * ^ ^ ^ ^

Then the ^'s and the * mark the indentation points that this
function cycles through. The indentation points are selected as
follows:

  * All lines before the current one, up to and including the
    first non-indented line (or the beginning of the buffer) are
    considered.

      foo = f a b
        where
          f (Foo x) y = let bar = x
                            baz = 3 + 5

  * On these lines, erase all characters that stand to the right
    of some non-white space character on a lower line.

      foo
        whe
          f (Foo x) y = let b
                            baz = 3 + 5

  * Also erase all characters not immediately preceded by white
    space.

      f
        w
          f (    x  y = l   b
                            b   = 3 + 5

  * The columns of all remaining characters are indentation
    points.

      f w f (    x  y = l   b   = 3 + 5
      ^ ^ ^ ^    ^  ^ ^ ^   ^   ^ ^ ^ ^

  * A new indentation point is also added, two steps in from the
    indentation of the first non-empty line (white space
    excluded) above the current line (if there is such a line).

      f w f (    x  y = l   b   = 3 + 5
      ^ ^ ^ ^    ^  ^ ^ ^   ^ * ^ ^ ^ ^"
  (interactive "P")
  (let* ((points (lean4-eri-calculate-indentation-points reverse))
         (remaining-points (cdr (member (current-indentation) points)))
         (indentation (if remaining-points
                          (car remaining-points)
                        (car points))))
    (when indentation
      (save-excursion (indent-line-to indentation))
      (if (< (current-column) indentation)
          (indent-line-to indentation)))))

(defun lean4-eri-indent-reverse nil
  "Cycle between some possible indentation points (in reverse order).
See `lean4-eri-indent' for a description of how the indentation points
are calculated."
  (interactive)
  (lean4-eri-indent t))

(provide 'lean4-eri)
;;; lean4-eri.el ends here
