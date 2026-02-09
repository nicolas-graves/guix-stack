;; SPDX-License-Identifier: GPL-3.0-or-later
;; Copyright © 2025, 2026 Nicolas Graves <ngraves@ngraves.fr>

(define-module (guix-stack channel-submodules)
  #:use-module (guix build utils)
  #:use-module (guix channels)
  #:use-module (guix git)
  #:use-module (ice-9 ftw)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-2)
  #:use-module (srfi srfi-26)
  #:use-module (git)
  #:export (submodules-dir->channel-instances
            submodules-dir->channels))

(define (get-submodule-oid full-path branch)
  "Get the OID of BRANCH for a submodule by opening its path."
  ;; XXX: This could techniocally be improved by using submodule_open
  ;; but it's not implemented yet.
  (with-repository full-path submodule-repository
    (and=> (false-if-exception
            (branch-lookup submodule-repository branch BRANCH-REMOTE))
           reference-target)))

(define* (submodules-dir->channel-instances #:optional (dir (getcwd))
                                            #:key
                                            (parent-dir
                                             (dirname
                                              (repository-discover dir)))
                                            (use-local-urls? #f)
                                            (type '(head)))
  "Return generated <channel-instance>s from DIR.

DIR is assumed to be a directory where all subdirectories are submodules."
  (with-repository parent-dir this-repo
    (let* ((relative-dir (if (and (> (string-length parent-dir)
                                     (string-length dir))
                                  (string-prefix? parent-dir dir))
                             (string-drop dir (1+ (string-length parent-dir)))
                             dir)))
      (filter-map
       (match-lambda
         ((or "." "..") #f)
         ((? (compose directory-exists?
                      (cut string-append relative-dir "/" <>))
             path)
          (and-let*
              ((full-path (string-append relative-dir "/" path))
               (this-sub (catch 'git-error
                                 (lambda ()
                                   (submodule-lookup this-repo full-path))
                                 (lambda (key error . rest)
                                   (if (= GIT_EEXISTS (git-error-code error))
                                       (begin
                                         (format (current-error-port) "\
git-error: check that every submodule has its branch set in .gitmodules.~%")
                                         #f)
                                       (apply throw key error rest)))))
               (oid (match type
                      (('head)
                       (submodule-wd-id this-sub))
                      (('branch 'or branches ...)
                       (any (cut get-submodule-oid full-path <>) branches))
                      (`(branch . ,branch)
                       (get-submodule-oid full-path branch)))))
            ((@@ (guix channels) channel-instance)
             (channel
               (name (string->symbol (basename path)))
               (branch (submodule-branch this-sub))
               (commit (oid->string oid))
               (url (if use-local-urls?
                        (string-append (canonicalize-path dir) "/" path)
                        (submodule-url this-sub))))
             (oid->string oid)
             (string-append (canonicalize-path dir) "/" path))))
         (_ #f))
       (scandir dir)))))

(define* (submodules-dir->channels #:optional (dir (getcwd))
                                   #:key
                                   (parent-dir
                                    (dirname
                                     (repository-discover dir)))
                                   (use-local-urls? #f)
                                   (type '(head)))
  "Return generated <channel>s from DIR.

DIR is assumed to be a directory where all subdirectories are submodules."
  (map channel-instance-channel
       (submodules-dir->channel-instances
        (getcwd)
        #:parent-dir (dirname (repository-discover dir))
        #:use-local-urls? #f
        #:type '(head))))
