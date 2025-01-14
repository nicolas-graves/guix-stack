;;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Copyright © 2025 Nicolas Graves <ngraves@ngraves.fr>

(define-module (guix-stack scripts hook)
  #:use-module ((guix build utils) #:select (directory-exists? install-file))
  #:use-module (ice-9 match)
  #:use-module (ice-9 rdelim)
  #:use-module (ice-9 textual-ports)
  #:export (stack-install-hook))

(define* (stack-install-hook args)
  "Install `git-metadata-record' as a git `sendemail-validate' hook,
in the current directory."
  (let ((hook (string-append
               (dirname (dirname (dirname (current-filename))))
               "/files/sendemail-validate"))
        (destination (string-append (getcwd) "/.git")))
    (match destination
      ((? directory-exists?)
       (install-file hook (string-append destination "/hooks")))
      ((? file-exists?)
       (let ((line (call-with-input-file destination read-line)))
         (if (string-prefix? "gitdir: " line)
             (let ((destination (canonicalize-path
                                 (string-drop
                                  line (string-length "gitdir: ")))))
               (if (directory-exists? destination)
                   (install-file hook (string-append destination "/hooks"))
                   (throw 'unable-to-find-git-dir destination)))
             (throw 'unable-to-read-git-dir destination))))
      (_
       (throw 'unable-to-find-git-dir destination)))))
