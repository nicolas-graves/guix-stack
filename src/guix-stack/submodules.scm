;; SPDX-License-Identifier: GPL-3.0-or-later
;; Copyright © 2025, 2026 Nicolas Graves <ngraves@ngraves.fr>

(define-module (guix-stack submodules)
  #:use-module (gnu packages)
  #:use-module (guix build utils)
  #:use-module (guix git)
  #:use-module (guix-local source)
  #:use-module (guix-stack channel-submodules)
  #:use-module (git)
  #:use-module (ice-9 format)
  #:use-module (ice-9 ftw)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-2)
  #:export (submodules-dir->packages
            submodule-generate-patches)
  #:re-export (submodules-dir->channels))

;;; Helpers

(define libgit2-version
  (string-join
   (map number->string
        ((@@ (git bindings) libgit2-version)))
   "."))

(define (repository-dirty? repo)
  "Check if repository has uncommitted changes (staged or unstaged)."
  (let* ((opts (make-status-options STATUS-SHOW-INDEX-AND-WORKDIR
                                    STATUS-FLAG-INCLUDE-UNTRACKED))
         (status-list (status-list-new repo opts)))
    (> (status-list-entry-count status-list) 0)))

(define (stash-changes repo)
  "Stash changes if any. Returns #t if stashed, #f otherwise."
  (stash-save repo
              (signature-now "guix-stack" "guix-stack@localhost")
              "guix-stack auto-stash for patch generation"
              STASH-INCLUDE-UNTRACKED))

(define (call-with-clean-repository directory proc)
  (let ((repository #f)
        (dirty? #f))
    (dynamic-wind
        (lambda ()
          (set! repository (repository-open directory))
          (set! dirty? (repository-dirty? repository))
          (and dirty? (stash-changes repository)))
        (lambda ()
          (proc repository))
        (lambda ()
          (when dirty?
            (stash-pop repository 0))
          (repository-close! repository)))))

(define-syntax-rule (with-clean-repository directory repository exp ...)
  "Open the repository at DIRECTORY, stash eventual dirty (staged and
unstaged) changes, and bind REPOSITORY to it within the dynamic extent
of EXP."
  (call-with-clean-repository directory
                              (lambda (repository) exp ...)))

;; Procedures

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

;;; Patch generation

(define (sanitize-filename str)
  "Convert string to safe filename."
  (string-map (lambda (c)
                (if (or (char-alphabetic? c)
                        (char-numeric? c)
                        (char=? c #\-)
                        (char=? c #\_))
                    c
                    #\-))
              (string-take str (min 50 (string-length str)))))

(define* (format-patch repo commit index total #:key (robust? #f))
  "Generate git format-patch style content.
When ROBUST? is #t, omit the mbox envelope line and Date: header so that
patches change as little as possible across rebases."
  (let* ((author (commit-author commit))
         (parent (false-if-exception (commit-parent commit)))
         (old-tree (and parent (commit-tree parent)))
         (new-tree (commit-tree commit))
         (diff (diff-tree-to-tree repo
                                  (or old-tree new-tree)
                                  new-tree)))
    (format #f "\
~aFrom: ~a <~a>
~aSubject: [PATCH ~a/~a] ~a~%
~a~%
---
~a
--
~a
"
            (if robust?
                ""
                (format #f "From ~a Mon Sep 17 00:00:00 2001\n"
                        (oid->string (commit-id commit))))
            (signature-name author)
            (signature-email author)
            (if robust?
                ""
                (format #f "Date: ~a\n"
                        (strftime "%a, %d %b %Y %H:%M:%S %z"
                                  (localtime (commit-time commit)))))
            index
            total
            (commit-summary commit)
            (commit-body commit)
            (diff->string diff)
            libgit2-version)))

(define (collect-commits repo base-oid head-oid)
  "Collect commits from HEAD to base."
  (let ((walker (revwalk-new repo)))
    (revwalk-push! walker head-oid)
    (revwalk-hide! walker base-oid)
    (let loop ((commits '()))
      (match (revwalk-next! walker)
        (#f commits)
        ((? oid? oid) (loop (cons oid commits)))))))

(define* (export-patches repo base-oid head-oid patches-dir #:key (robust? #f))
  "Export patches from base..HEAD to patches-dir."
  (delete-file-recursively patches-dir)
  (mkdir-p patches-dir)
  (let* ((commits (collect-commits repo base-oid head-oid))
         (total (length commits)))
    (let loop ((lst commits) (i 1))
      (match lst
        (() (format #t "Exported ~a patches to ~a\n" total patches-dir))
        ((oid . rest)
         (let* ((commit (commit-lookup repo oid))
                (filename (format #f "~a/~4,'0d-~a.patch"
                                  patches-dir i
                                  (sanitize-filename (commit-summary commit)))))
           (with-output-to-file filename
             (lambda _ (display (format-patch repo commit i total
                                              #:robust? robust?))))
           (loop rest (1+ i))))))))

(define* (submodule-generate-patches submodule-path patches-dir
                                     #:key (branches (list "origin/master"
                                                           "origin/main"))
                                     (robust? #f))
  "Stash changes and generate patches for submodule.
When ROBUST? is #t, omit volatile headers (mbox envelope and Date:) from
patches so they change as little as possible across rebases."
  (with-clean-repository submodule-path repository
    (and-let* ((head-oid (reference-target (repository-head repository)))
               (target (any
                        (lambda (branch)
                          (false-if-exception
                           (reference-lookup
                            repository
                            (string-append "refs/remotes/" branch))))
                        branches))
               (base-oid (reference-target target)))
      (export-patches repository base-oid head-oid patches-dir
                      #:robust? robust?))))
