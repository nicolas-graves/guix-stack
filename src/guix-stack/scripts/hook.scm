;;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Copyright © 2025 Nicolas Graves <ngraves@ngraves.fr>

(define-module (guix-stack scripts hook)
  #:use-module ((guix build utils) #:select (directory-exists? install-file))
  #:use-module (ice-9 match)
  #:use-module (ice-9 rdelim)
  #:use-module (ice-9 textual-ports)
  #:export (stack-install-hook))

(define* (install-hook hook hookdir #:key (force? #f))
  (let ((destination (string-append hookdir "/sendemail-validate")))
    (if (pk 'e (file-exists? (pk 'd destination)))
        (if force?
            (begin
              (delete-file destination)
              (install-file hook hookdir))
            (throw 'hook-already-present destination))
        (install-file hook hookdir))))

(define* (stack-install-hook args)
  "Install `git-metadata-record' as a git `sendemail-validate' hook,
in the current directory."
  (let ((force? (or (member "-f" args)
                    (member "--force" args)))
        (hook (if (getenv "GUIX_STACK_UNINSTALLED")
                  (string-append
                   (dirname (dirname (dirname (current-filename))))
                   "/git/hooks/sendemail-validate")
                  "@GIT_SENDEMAIL_VALIDATE_HOOK@"))
        (gitdir (string-append (getcwd) "/.git")))
    (match gitdir
      ((? directory-exists?)
       (install-hook hook (string-append gitdir "/hooks") #:force? force?))
      ((? file-exists?)
       (let ((line (call-with-input-file gitdir read-line)))
         (if (string-prefix? "gitdir: " line)
             (let* ((gitdir (canonicalize-path
                             (string-drop
                              line (string-length "gitdir: ")))))
               (if (directory-exists? gitdir)
                   (install-hook hook (string-append gitdir "/hooks")
                                 #:force? force?)
                   (throw 'unable-to-find-git-dir gitdir)))
             (throw 'unable-to-read-git-dir gitdir))))
      (_
       (throw 'unable-to-find-git-dir gitdir)))))
