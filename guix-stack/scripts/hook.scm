;;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Copyright © 2025 Nicolas Graves <ngraves@ngraves.fr>

(define-module (guix-stack scripts hook)
  #:use-module ((guix build utils) #:select (directory-exists?))
  #:use-module (ice-9 match)
  #:use-module (ice-9 rdelim)
  #:use-module (ice-9 textual-ports)
  #:export (stack-install-hook))

(define* (stack-install-hook args)
  "Install `git-metadata-record' as a git `sendemail-validate' hook,
in the current directory."
  (let ((hook (string-append
               (dirname (dirname (current-filename)))
               "/files/git-metadata-record"))
        (destination (string-append (getcwd) "/.git")))
    (match destination
      ((? directory-exists?)
       (copy-file hook
                  (string-append destination "/hooks/sendemail-validate")))
      ((? file-exists?)
       (let ((line (call-with-input-file destination read-line)))
         (if (string-prefix? "gitdir: " line)
             (copy-file hook
                        (string-append
                         (canonicalize-path
                          (string-drop line (string-length "gitdir: ")))
                         "/hooks/sendemail-validate"))
             (throw 'unable-to-read-git-dir destination))))
      (_
       (throw 'unable-to-find-git-dir destination)))))
