;;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Copyright © 2024 Nicolas Graves <ngraves@ngraves.

(define-module (guix extensions stacked)
  #:use-module (guix scripts)
  #:use-module (ice-9 match)
  #:use-module (ice-9 format)
  #:use-module (srfi srfi-1)
  #:use-module (stguix scripts pull)
  #:export (guix-stacked))

;;;
;;; Entry point.
;;;

(define-command (guix-stacked . args)
  (category extension)
  (synopsis "pull and patch the latest revision of Guix")

  (match (command-line)
    ((guix stacked . args)
     (with-error-handling
       (match args
         (("pull" rest)
          (stacked-pull #:args (cdr args))))))
    (_
     (format (current-error-port)
             "guix: missing or unknown command name~%"))))
