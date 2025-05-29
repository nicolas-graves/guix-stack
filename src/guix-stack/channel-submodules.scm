;; SPDX-License-Identifier: GPL-3.0-or-later
;; Copyright © 2025 Nicolas Graves <ngraves@ngraves.fr>

(define-module (guix-stack channel-submodules)
  #:use-module (guix channels)
  #:use-module (ice-9 ftw)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-2)
  #:use-module (git)
  #:export (submodules-dir->channels))

(define* (submodules-dir->channels #:optional (dir (getcwd))
                                   #:key
                                   (parent-dir
                                    (dirname (repository-discover dir)))
                                   (use-local-urls? #f))
  "Return generated <channel>s from DIR.

DIR is assumed to be a directory where all subdirectories are submodules."
  (let* ((this-repo (repository-open parent-dir))
         (relative-dir (if (string-prefix? parent-dir dir)
                           (string-drop dir (1+ (string-length parent-dir)))
                           dir)))
    (filter-map
     (match-lambda
       ((or "." "..") #f)
       (path
        (and-let* ((this-sub (submodule-lookup
                              this-repo
                              (string-append relative-dir "/" path))))
          (channel
           (name (string->symbol (basename path)))
           (branch (submodule-branch this-sub))
           (commit (oid->string (submodule-wd-id this-sub)))
           (url (if use-local-urls?
                    (string-append (canonicalize-path dir) "/" path)
                    (submodule-url this-sub)))))))
     (scandir dir))))
