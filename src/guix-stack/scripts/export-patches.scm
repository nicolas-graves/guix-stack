;; SPDX-License-Identifier: GPL-3.0-or-later
;; Copyright © 2026 Nicolas Graves <ngraves@ngraves.fr>

(define-module (guix-stack scripts export-patches)
  #:use-module (guix build utils)
  #:use-module (guix diagnostics)
  #:use-module (guix i18n)
  #:use-module (guix scripts)
  #:use-module (guix-stack submodules)
  #:use-module (ice-9 ftw)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-37)
  #:export (stack-export-patches))

;;;
;;; Command-line options.
;;;

(define %options
  (list
   (option '("notes") #f #f
           (lambda (opt name arg result)
             (alist-cons 'notes? #t result)))
   (option '(#\h "help") #f #f
           (lambda (opt name arg result)
             (alist-cons 'help? #t result)))))

(define %default-options '())

(define (show-help)
  (display "Usage: guix stack export-patches [OPTIONS] CHANNELS-DIR

For each channel (subdirectory) in CHANNELS-DIR, generate patches
representing commits on top of the upstream branch and write them to
CHANNELS-DIR/<channel>/patches/.

Options:
  --notes         append the git note for each commit to the patch description
  -h, --help      display this help and exit\n"))

;;;
;;; Entry point.
;;;

(define (stack-export-patches args)
  (let* ((opts         (parse-command-line args %options
                                           (list %default-options)))
         (notes?       (assoc-ref opts 'notes?))
         (help?        (assoc-ref opts 'help?))
         (channels-dir (assoc-ref opts 'argument)))
    (when help?
      (show-help)
      (exit 0))
    (unless channels-dir
      (report-error (G_ "export-patches: Missing CHANNELS-DIR argument!"))
      (exit 0))
    (with-directory-excursion channels-dir
      (for-each
       (match-lambda
         ((or "." "..") #f)
         ((? directory-exists? channel)
          (let* ((patches-dir (string-append "../patches/" channel)))
            (format #t "Exporting patches for ~a...\n" channel)
            (mkdir-p patches-dir)
            (submodule-generate-patches channel
                                        (canonicalize-path patches-dir)
                                        ;; Reduce churn.
                                        #:robust? #t
                                        #:notes?  notes?))))
       (scandir ".")))))
