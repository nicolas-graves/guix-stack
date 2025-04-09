;; SPDX-License-Identifier: GPL-3.0-or-later
;; Copyright © 2025 Nicolas Graves <ngraves@ngraves.fr>

(define-module (guix-stack submodules)
  #:use-module (gnu packages)
  #:use-module (guix-local source)
  #:use-module (ice-9 ftw)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-1)
  #:use-module (git)
  #:export (submodules-dir->channels
            submodules-dir->packages))

(define* (submodules-dir->channels #:optional (dir (getcwd))
                                   #:key
                                   (parent-dir
                                    (dirname (repository-discover dir))))
  "Return generated <channel>s from DIR.

DIR is assumed to be a directory where all subdirectories are submodules."
  (let ((this-repo (repository-open parent-dir))
        (relative-dir (string-drop (canonicalize-path dir)
                                   (1+ (string-length parent-dir)))))
    (filter-map
     (match-lambda
       ((? (cut string-prefix? relative-dir <>) path)
        (let ((this-sub (submodule-lookup this-repo path)))
          (channel
           (name (string->symbol (basename path)))
           (branch (submodule-branch this-sub))
           (commit (oid->string (submodule-head-id this-sub)))
           (url (submodule-url this-sub)))))
       ;; Otherwise: other submodules.
       (_ #f))
     (repository-submodules this-repo))))

(define* (submodules-dir->packages #:optional (dir (getcwd))
                                   #:key
                                   (git-fetch? #f)
                                   (keep-mtime? #f)
                                   (select? (const #t)))
  "Provide support for the layout where all directories under a dir are
submodules and their correspond to a development package."
  (filter-map
   (match-lambda
     ((or "." "..") #f)
     (file
      (cons (string->symbol file)
            (package-with-source*
             (specification->package file)
             (canonicalize-path (string-append dir "/" file))
             #:git-fetch? git-fetch?
             #:keep-mtime? keep-mtime?
             #:select? select?))))
   (scandir dir)))
