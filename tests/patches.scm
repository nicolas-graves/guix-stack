;; SPDX-License-Identifier: GPL-3.0-or-later
;; Copyright © 2026 Nicolas Graves <ngraves@ngraves.fr>

(define-module (tests patches)
  #:use-module (ares suitbl core)
  #:use-module (guix build utils)
  #:use-module (guix tests git)
  #:use-module (guix utils)
  #:use-module (guix-stack submodules)
  #:use-module (git)
  #:use-module (ice-9 textual-ports)
  #:use-module (srfi srfi-1))

(test-runner*)

(define-suite export-patches-suite
  (test "single-patch-adds-file"
    (with-temporary-git-repository repo
        '((add "hello.txt" "Hello, world!\n")
          (commit "Initial commit")
          (add "new-file.txt" "New content\n")
          (commit "Add new-file.txt"))
      (call-with-temporary-directory
       (lambda (patches-dir)
         (let* ((repository  (repository-open repo))
                (head-oid    (reference-target (repository-head repository)))
                (head-commit (commit-lookup repository head-oid))
                (base-oid    (commit-id (commit-parent head-commit))))
           (export-patches repository base-oid head-oid patches-dir)
           (repository-close! repository)
           (let* ((files   (find-files patches-dir "\\.patch$"))
                  (content (call-with-input-file (car files) get-string-all)))
             (is (= (length files) 1))
             (is (string-prefix? "0001-" (basename (car files))))
             (is (string-contains content "Add new-file.txt"))
             (is (string-contains content "+New content")))))))))

(export-patches-suite)

(define-suite import-patches-suite
  (test "roundtrip-export-import"
    (with-temporary-git-repository repo
        '((add "hello.txt" "Hello, world!\n")
          (commit "Initial commit")
          (add "new-file.txt" "New content\n")
          (commit "Add new-file.txt"))
      (call-with-temporary-directory
       (lambda (patches-dir)
         (let* ((repository  (repository-open repo))
                (head-oid    (reference-target (repository-head repository)))
                (head-commit (commit-lookup repository head-oid))
                (base-oid    (commit-id (commit-parent head-commit))))
           ;; Export patches from base..HEAD
           (export-patches repository base-oid head-oid patches-dir)
           ;; Reset hard to base, undoing the "Add new-file.txt" commit
           (reset repository
                  (object-lookup repository base-oid)
                  RESET_HARD)
           ;; Import patches back on top of base
           (import-patches repository base-oid patches-dir)
           ;; Verify HEAD now points to a reconstructed commit with the right
           ;; message and the right parent
           (let* ((new-head-oid    (reference-target (repository-head repository)))
                  (new-head-commit (commit-lookup repository new-head-oid)))
             (is (string=? (commit-summary new-head-commit) "Add new-file.txt"))
             (is (string=? (oid->string (commit-id (commit-parent new-head-commit)))
                           (oid->string base-oid))))
           (repository-close! repository)))))))

(import-patches-suite)

;; Local Variables:
;; eval: (put 'test 'scheme-indent-function 1)
;; End:
