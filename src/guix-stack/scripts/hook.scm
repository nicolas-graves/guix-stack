;;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Copyright © 2025 Nicolas Graves <ngraves@ngraves.fr>

(define-module (guix-stack scripts hook)
  #:use-module ((guix build utils) #:select (directory-exists? install-file))
  #:use-module (git config)
  #:use-module (git repository)
  #:use-module (ice-9 match)
  #:use-module (ice-9 rdelim)
  #:use-module (ice-9 textual-ports)
  #:export (stack-install-hook))

(define* (set-git-config-options! repository)
  "Set the required git config options in the given REPOSITORY."
  (let* ((config (repository-config repository)))
    (set-config-boolean config "notes.rewrite.rebase" #t)
    (set-config-boolean config "notes.rewrite.amend" #t)
    (set-config-string config "notes.rewriteRef" "refs/notes/commits")
    (repository-close! repository)))

(define* (install-hook hook hookdir #:key (force? #f))
  (let ((destination (string-append hookdir "/sendemail-validate")))
    (if (file-exists? destination)
        (if force?
            (begin
              (delete-file destination)
              (install-file hook hookdir))
            (throw 'hook-already-present destination))
        (install-file hook hookdir))))

(define* (stack-install-hook args)
  "Install `git-metadata-record' as a git `sendemail-validate' hook,
in the current directory and set git config options."
  (let* ((force? (or (member "-f" args)
                     (member "--force" args)))
         (hook (if (getenv "GUIX_STACK_UNINSTALLED")
                   (string-append
                    (dirname (dirname (dirname (current-filename))))
                    "/git/hooks/sendemail-validate")
                   "@GIT_SENDEMAIL_VALIDATE_HOOK@"))
         (cwd (getcwd))
         (gitdir (string-append cwd "/.git")))
    (set-git-config-options! cwd)
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
