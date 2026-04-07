;; SPDX-License-Identifier: GPL-3.0-or-later
;; Copyright © 2021-2025 Nicolas Graves <ngraves@ngraves.fr>

(define-module (guix-stack patchset)
  #:use-module (gnu packages guile)
  #:use-module (gnu packages tls)
  #:use-module (gnu packages version-control)
  #:use-module (guix channels)
  #:use-module (guix derivations)
  #:use-module (guix gexp)
  #:use-module (guix git)
  #:use-module (guix modules)
  #:use-module (guix monads)
  #:use-module (guix packages)
  #:use-module (guix records)
  #:use-module (guix scripts)
  #:use-module ((guix self) #:select (make-config.scm))
  #:use-module (guix store)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-26)
  #:use-module (ice-9 match)
  #:use-module (guix build utils)
  #:export (maybe-instantiate-channel
            patchset-reference
            patchset-fetch))

(define-record-type* <patchset-reference>
  patchset-reference make-patchset-reference
  patchset-reference?
  (type patchset-reference-type)
  (id patchset-reference-id)
  ;; A version, when possible, is higly recommended to enhance reproducibility
  (version patchset-reference-version
           (default 0))
  ;; here project encompasses repositories (github, gitlab), mailing lists (srht)
  (project patchset-reference-project
           (default #f)))

(define-record-type* <patched-channel>
  patched-channel make-patched-channel
  patched-channel?
  (channel patched-channel-channel)  ; <channel>
  (patchsets patched-channel-patchsets  ; list of <origin>
             (default '())))

(define* (patchset-fetch ref hash-algo hash #:optional name
                     #:key (system %current-system) guile)

  (define uri
    (apply
     format
     #f
     (assoc-ref
      '((gnu . "https://debbugs.gnu.org/cgi-bin/bugreport.cgi?bug=~a;mbox=yes")
        (srht . "https://lists.sr.ht/~a/patches/~a/mbox"))
      (patchset-reference-type ref))
     (append (or (and=> (patchset-reference-project ref) list) '())
             (list (patchset-reference-id ref)))))

  (define modules
    (cons `((guix config) => ,(make-config.scm))
          (delete '(guix config)
                  (source-module-closure '((guix build download)
                                           (guix build utils))))))

  (define build
    (with-extensions (list guile-json-4 guile-gnutls)
      (with-imported-modules modules
        #~(begin
            (use-modules (guix build utils) (guix build download))
            (setenv "TMPDIR" (getcwd))
            (setenv "XDG_DATA_HOME" (getcwd))
            (invoke #$(file-append b4 "/bin/b4")
                    "-d" "-n" "--offline-mode" "--no-stdin"
                    "am" "--no-cover" "--no-cache"
                    "--use-local-mbox"
                    (url-fetch #$uri "mbox" #:verify-certificate? #f)
                    #$@(if (eq? 0 (patchset-reference-version ref))
                           '()
                           (list "--use-version"
                                 (number->string
                                  (patchset-reference-version ref))))
                    "--no-add-trailers"
                    "--outdir" "."
                    "--quilt-ready")
            (copy-recursively
             (car (find-files "." "\\.patches" #:directories? #t))
             #$output)))));)

  (mlet %store-monad ((guile (package->derivation (or guile (default-guile))
                                                  system)))
    (gexp->derivation (or name
                          (match-record ref <patchset-reference>
                                        (type id version)
                            (format #f "~a-~a-v~a-patchset" type id version)))
      build
      ;; Use environment variables and a fixed script name so
      ;; there's only one script in store for all the
      ;; downloads.
      #:system system
      #:local-build? #t ;don't offload repo cloning
      #:hash-algo hash-algo
      #:hash hash
      #:recursive? #t
      #:guile-for-build guile)))

;;; XXX: Copied and adapted from (guix transformations).
(define (patched-source* name source patches-or-patchsets)
  "Return a file-like object with the given NAME that applies MAILDIRS to
SOURCE.  SOURCE must itself be a file-like object of any type, including
<git-checkout>, <local-file>, etc."
  (define gawk
    (module-ref (resolve-interface '(gnu packages gawk)) 'gawk))
  (define patch
    (module-ref (resolve-interface '(gnu packages base)) 'patch))
  (define quilt
    (module-ref (resolve-interface '(gnu packages patchutils)) 'quilt))

  (computed-file name
                 (with-imported-modules '((guix build utils))
                   #~(begin
                       (use-modules (guix build utils)
                                    (srfi srfi-34)
                                    (ice-9 match))
                       (define (quilt-patchset? candidate)
                          (and (directory-exists? candidate)
                               (file-exists? (string-append candidate "/series"))))
                       (define (quilt-push!)
                            (with-exception-handler
                                 (lambda (exception)
                                    (and (invoke-error? exception)
                                        ;; 2 is not an error.
                                        (not (= 2 (invoke-error-exit-status
                                                   exception)))
                                        (report-invoke-error exception)))
                               (lambda ()
                                 (invoke "quilt" "push" "-afv" "--leave-rejects"))
                               #:unwind? #t))
                       (setenv "PATH"
                               (string-append #+patch "/bin:"
                                              #+gawk "/bin:"
                                              #+quilt "/bin:"
                                              (getenv "PATH")))

                       (copy-recursively #+source #$output)
                       (chdir #$output)
                       (for-each
                        (match-lambda
                          ((? quilt-patchset? maildir)
                             (setenv "QUILT_PATCHES" maildir)
                             (quilt-push!))
                          (patch
                            (invoke "patch" "-p1" "--batch" "-i" patch)))
                        '(#+@patches-or-patchsets))))))

(define (patched-channel->channel-instance patched-channel)
  (match-record patched-channel <patched-channel>
                (channel patchsets)
    ((@@ (guix channels) channel-instance)
     channel
     (channel-commit channel)
     (patched-source*
      (symbol->string (channel-name channel))
      (git-checkout
        (url (channel-url channel))
        (branch (channel-branch channel))
        (commit (channel-commit channel)))
      patchsets))))

(define maybe-instantiate-channel
  (match-lambda
    ((? channel? channel)
     channel)
    ((? patched-channel? patched-channel)
     (let ((channel (patched-channel-channel patched-channel)))
       (if (file-exists? (channel-url channel))
           channel
           (patched-channel->channel-instance patched-channel))))))
