;; SPDX-License-Identifier: GPL-3.0-or-later
;; Copyright © 2026 Nicolas Graves <ngraves@ngraves.fr>

(define-module (tests export-patches)
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

;; Local Variables:
;; eval: (put 'test 'scheme-indent-function 1)
;; End:
