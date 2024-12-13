;;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Copyright © 2018-2022 Ricardo Wurmus <rekado@elephly.net>
;;; Copyright © 2024 Nicolas Graves <ngraves@ngraves.fr>

(define-module (guix-stack-channel))

(use-modules (guix git)
             (ice-9 vlist)
             (ice-9 match)
             (srfi srfi-1)
             (srfi srfi-11)
             (guix packages)
             (guix gexp)
             (guix git-download)
             (guix build-system gnu)
             (guix transformations)
             ((guix licenses) #:prefix license:)
             (guix utils)
             (gnu packages base)
             (gnu packages admin)
             (gnu packages autotools)
             (gnu packages package-management)
             (gnu packages pkg-config)
             (gnu packages guile)
             (gnu packages guile-xyz)
             (gnu packages graphviz)
             (gnu packages tex)
             (gnu packages texinfo)
             (gnu packages perl)
             (gnu packages rsync)
             (gnu packages ssh)
             (gnu packages version-control))

(define* (package-input-rewriting/spec* replacements
                                        #:key
                                        (deep? #t)
                                        (cut? (const #f)))
  "This is just like PACKAGE-INPUT-REWRITING/SPEC but takes an extra
argument CUT?, a procedure that takes the package value and
returns a boolean to determine whether rewriting should continue."
  (define table
    (fold (lambda (replacement table)
            (match replacement
              ((spec . proc)
               (let-values (((name version)
                             (package-name->name+version spec)))
                 (vhash-cons name (list version proc) table)))))
          vlist-null
          replacements))

  (define (find-replacement package)
    (vhash-fold* (lambda (item proc)
                   (or proc
                       (match item
                         ((#f proc)
                          proc)
                         ((version proc)
                          (and (version-prefix? version
                                                (package-version package))
                               proc)))))
                 #f
                 (package-name package)
                 table))

  (define replacement-property
    (gensym " package-replacement"))

  (define (rewrite p)
    (if (assq-ref (package-properties p) replacement-property)
        p
        (match (find-replacement p)
          (#f p)
          (proc
           (let ((new (proc p)))
             ;; Mark NEW as already processed.
             (package/inherit new
               (properties `((,replacement-property . #t)
                             ,@(package-properties new)))))))))

  (define (cut?* p)
    (or (assq-ref (package-properties p) replacement-property)
        (find-replacement p)
        (cut? p)))

  (package-mapping rewrite cut?*
                   #:deep? deep?))

(define guix-guile
  (and=> (assoc-ref (package-native-inputs guix) "guile") car))

(define with-guix-guile-instead-of-any-guile
  ;; Replace all the packages called "guile" with the Guile variant
  ;; used by the "guix" package.
  (package-input-rewriting/spec*
   `(("guile" . ,(const guix-guile)))
   #:deep? #false
   #:cut?
   (lambda (p)
     (not (or (string-prefix? "guile-"
                              (package-name p)))))))

(define p
  with-guix-guile-instead-of-any-guile)

(define commit "4ec2625f0167d4b4c5dc8f7d776e81356d3d3856")

(define-public guix-stack
  (package
   (name "guix-stack")
   (version (git-version "0.0.0" "0" (string-take commit 7)))
   (source
    (git-checkout
     (url "https://git.sr.ht/~ngraves/guix-stack")
     (commit commit)))
   (build-system gnu-build-system)
   (arguments
    '(#:make-flags
      '("GUILE_AUTO_COMPILE=0")))
   (inputs
    (let ((p (package-input-rewriting
              `((,guile-3.0 . ,guile-3.0-latest))
              #:deep? #false)))
      (list guix guile-3.0-latest (p guile-git))))
   (native-inputs
    (list autoconf automake pkg-config texinfo graphviz))
   (home-page "https://git.sr.ht/~ngraves/guix-stack")
   (synopsis "Tools for local development on GNU Guix")
   (description "This package provides a guix extension to with
helpful tools for local development.")
   (license license:gpl3+)))

(define-public guix-stack/devel
  (package
   (inherit guix-stack)
   (name "guix-stack-devel")
   (inputs
    (list guix guix-guile (p guile-git)))
   (native-inputs
    (append
     (list autoconf automake pkg-config texinfo graphviz)
     (list
      coreutils

      ;; for make distcheck
      texlive-scheme-basic

      sed

      ;; For "make release"
      perl
      git-minimal

      ;; For manual post processing
      guile-lib
      rsync

      ;; For "git push"
      openssh-sans-x

      ;; For dynamic development
      guile-next
      guile-ares-rs)))))
