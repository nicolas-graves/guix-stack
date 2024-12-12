;;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Copyright © 2024 Nicolas Graves <ngraves@ngraves.

(define-module (stguix main)
  #:use-module ((guix ui) #:select (with-error-handling))
  #:use-module (guix scripts)
  #:use-module (stguix scripts pull)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-1)
  #:export (guix-stacked-main))

;;;
;;; Entry point.
;;;

(define (guix-stacked-main . args)
  (let ((command-args (cddr args)))
    (with-error-handling
      (match (car command-args)
        ("pull"
         (stacked-pull #:args (cdr command-args)))
        (_
         (format (current-error-port)
                 "guix: missing or unknown command name~%"))))))
