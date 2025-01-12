;;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Copyright © 2025 Nicolas Graves <ngraves@ngraves.fr>

(define-module (guix-stack scripts hook)
  #:export (stack-install-hook))

(define* (stack-install-hook args)
  "Install `git-metadata-record' as a git `sendemail-validate' hook,
in the current directory."
  (pk 'cwd (getcwd))
  (pk 'args args)
  (pk 'hook (string-append
             (dirname (dirname (current-filename)))
             "/files/git-metadata-record"))
  )
