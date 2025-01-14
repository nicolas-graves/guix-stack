;;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Copyright © 2025 Nicolas Graves <ngraves@ngraves.fr>

(define-module (guix-stack scripts hook)
  #:use-module ((guix build utils) #:select (directory-exists? install-file))
  #:use-module (ice-9 match)
  #:use-module (ice-9 rdelim)
  #:use-module (ice-9 textual-ports)
  #:export (stack-install-hook))

(define (install-hook hook hookdir)
  (let ((destination (string-append hookdir "/sendemail-validate")))
    (if (file-exists? destination)
        (throw 'hook-already-present destination)
        (install-file hook hookdir))))

(define* (stack-install-hook args)
  "Install `git-metadata-record' as a git `sendemail-validate' hook,
in the current directory."
  (let ((hook (string-append
               (dirname (dirname (dirname (current-filename))))
               "/files/sendemail-validate"))
        (gitdir (string-append (getcwd) "/.git")))
    (match gitdir
      ((? directory-exists?)
       (install-hook hook (string-append gitdir "/hooks")))
      ((? file-exists?)
       (let ((line (call-with-input-file gitdir read-line)))
         (if (string-prefix? "gitdir: " line)
             (let* ((gitdir (canonicalize-path
                             (string-drop
                              line (string-length "gitdir: ")))))
               (if (directory-exists? gitdir)
                   (install-hook hook (string-append gitdir "/hooks"))
                   (throw 'unable-to-find-git-dir gitdir)))
             (throw 'unable-to-read-git-dir gitdir))))
      (_
       (throw 'unable-to-find-git-dir gitdir)))))
