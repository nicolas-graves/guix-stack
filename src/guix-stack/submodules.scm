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
  #:use-module (ice-9 textual-ports)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-2)
  #:export (submodules-dir->packages
            export-patches
            import-patches
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

(define* (format-patch repo commit index total #:key (robust? #f) (notes? #f))
  "Generate git format-patch style content.
When ROBUST? is #t, omit the mbox envelope line and Date: header so that
patches change as little as possible across rebases.
When NOTES? is #t, append the git note for the commit (if any) to the
patch description."
  (let* ((author (commit-author commit))
         (parent (false-if-exception (commit-parent commit)))
         (old-tree (and parent (commit-tree parent)))
         (new-tree (commit-tree commit))
         (diff (diff-tree-to-tree repo
                                  (or old-tree new-tree)
                                  new-tree))
         (note (and notes?
                    (note-read repo (commit-id commit)))))
    (format #f "\
~aFrom: ~a <~a>
~aSubject: [PATCH ~a/~a] ~a~%
~a~a~%
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
            (if note
                (format #f "Notes:\n~a\n"
                        (string-join
                         (map (lambda (line) (string-append "    " line))
                              (string-split (string-trim-right (note-message note))
                                            #\newline))
                         "\n"))
                "")
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

(define* (export-patches repo base-oid head-oid patches-dir
                         #:key (robust? #f) (notes? #f))
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
                                              #:robust? robust?
                                              #:notes? notes?))))
           (loop rest (1+ i))))))))

(define (parse-patch content)
  "Parse a format-patch style patch file CONTENT.
Returns an alist with keys: from-name, from-email, summary, body, diff."
  (let* ((lines (string-split content #\newline))
         ;; Skip optional mbox envelope line ("From <sha1> ...")
         (lines (if (and (pair? lines)
                         (string-prefix? "From " (car lines))
                         (not (string-prefix? "From: " (car lines))))
                    (cdr lines)
                    lines)))
    (let header-loop ((lines lines)
                      (from-name "")
                      (from-email "")
                      (summary ""))
      (match lines
        (() (list (cons 'from-name from-name)
                  (cons 'from-email from-email)
                  (cons 'summary summary)
                  (cons 'body "")
                  (cons 'diff "")))
        (("" . rest)
         ;; End of headers; collect body lines until "---" separator.
         (let body-loop ((lines rest) (body-lines '()))
           (match lines
             (() (list (cons 'from-name from-name)
                       (cons 'from-email from-email)
                       (cons 'summary summary)
                       (cons 'body (string-join (reverse body-lines) "\n"))
                       (cons 'diff "")))
             (("---" . rest)
              ;; Collect diff lines until the trailing "-- " or "--" line.
              (let diff-loop ((lines rest) (diff-lines '()))
                (match lines
                  (() (list (cons 'from-name from-name)
                            (cons 'from-email from-email)
                            (cons 'summary summary)
                            (cons 'body (string-join (reverse body-lines) "\n"))
                            (cons 'diff (string-join (reverse diff-lines) "\n"))))
                  (((or "--" "-- ") . _)
                   (list (cons 'from-name from-name)
                         (cons 'from-email from-email)
                         (cons 'summary summary)
                         (cons 'body (string-join (reverse body-lines) "\n"))
                         (cons 'diff (string-join (reverse diff-lines) "\n"))))
                  ((line . rest)
                   (diff-loop rest (cons line diff-lines))))))
             ((line . rest)
              (body-loop rest (cons line body-lines))))))
        ((line . rest)
         (cond
           ((string-prefix? "From: " line)
            (let* ((from (substring line 6))
                   (lt   (string-rindex from #\<))
                   (gt   (string-rindex from #\>)))
              (if (and lt gt)
                  (header-loop rest
                               (string-trim-right (substring from 0 lt))
                               (substring from (1+ lt) gt)
                               summary)
                  (header-loop rest from-name from-email summary))))
           ((string-prefix? "Subject: " line)
            (let* ((subj (substring line 9))
                   (end  (string-contains subj "] ")))
              (header-loop rest from-name from-email
                           (if end
                               (substring subj (+ end 2))
                               subj))))
           (else
            (header-loop rest from-name from-email summary))))))))

(define* (import-patches repo base-oid patches-dir)
  "Apply patches from PATCHES-DIR on top of BASE-OID in REPO, detaching HEAD."
  (let* ((patch-files (sort (find-files patches-dir "\\.patch$") string<?))
         (total (length patch-files))
         (base-commit (commit-lookup repo base-oid)))
    (repository-detach-head repo)
    (let loop ((patch-files patch-files)
               (parent-commit base-commit)
               (i 1))
      (match patch-files
        (()
         (format #t "Applied ~a patches on top of ~a\n"
                 total (oid->string base-oid)))
        ((patch-file . rest)
         (let* ((content      (call-with-input-file patch-file get-string-all))
                (parsed       (parse-patch content))
                (from-name    (assoc-ref parsed 'from-name))
                (from-email   (assoc-ref parsed 'from-email))
                (summary      (assoc-ref parsed 'summary))
                (body         (assoc-ref parsed 'body))
                (diff-str     (assoc-ref parsed 'diff))
                (diff         (string->diff diff-str))
                (parent-tree  (commit-tree parent-commit))
                (new-index    (apply-diff-to-tree repo parent-tree diff))
                (new-tree-oid (index-write-tree-to new-index repo))
                (new-tree     (tree-lookup repo new-tree-oid))
                (author       (signature-now from-name from-email))
                (message      (if (string-null? body)
                                  (string-append summary "\n")
                                  (string-append summary "\n\n" body "\n")))
                (new-oid      (commit-create repo "HEAD" author author
                                             message new-tree
                                             (list parent-commit))))
           (format #t "Applied patch ~a/~a: ~a\n" i total summary)
           (loop rest (commit-lookup repo new-oid) (1+ i))))))))

(define* (submodule-generate-patches submodule-path patches-dir
                                     #:key (branches (list "origin/master"
                                                           "origin/main"))
                                     (robust? #f)
                                     (notes? #f))
  "Stash changes and generate patches for submodule.
When ROBUST? is #t, omit volatile headers (mbox envelope and Date:) from
patches so they change as little as possible across rebases.
When NOTES? is #t, append any git note for each commit to the patch
description."
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
                      #:robust? robust?
                      #:notes? notes?))))
