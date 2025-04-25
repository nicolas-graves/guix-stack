;;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Copyright © 2024, 2025 Nicolas Graves <ngraves@ngraves.fr>

(define-module (guix extensions stack)
  #:use-module (guix channels)
  #:use-module (guix scripts)
  #:use-module (guix profiles)
  #:use-module ((guix ui) #:select (with-error-handling))
  #:use-module (guix-stack build channel)
  #:use-module (guix-stack scripts pull)
  #:use-module (guix-stack scripts hook)
  #:use-module (ice-9 format)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-1)
  #:export (guix-stack))

;;;
;;; Entry point.
;;;

(define-command (guix-stack . args)
  (category extension)
  (synopsis "pull and patch the latest revision of Guix")

  (match (command-line)
    ((guix stack . args)
     (with-error-handling
       (match args
         (((or "-V" "--version") . rest)
          (format (current-output-port) "guix-stack: ~a
Copyright © 2025 Nicolas Graves <ngraves@ngraves.fr>
License GPLv3+: GNU GPL version 3 or later <http://gnu.org/licenses/gpl.html>
This is free software: you are free to change and redistribute it.
There is NO WARRANTY, to the extent permitted by law.
"
                  (let ((%current-profile
                         (string-append %profile-directory "/current-guix")))
                    (channel-commit
                     (find (lambda (channel)
                             (eq? (channel-name channel) 'guix-stack))
                           (profile-channels %current-profile))))))
         (("build" "guix" . rest)
          (build-local-guix (getcwd)))
         (("pull" . rest)
          (stack-pull rest))
         (("install-hook" . rest)
          (stack-install-hook rest))
         (otherwise
          (begin
            (format (current-error-port)
                    "guix-stack: unrecognized option or command '~a'~%"
                    otherwise)
            (exit 1))))))))
