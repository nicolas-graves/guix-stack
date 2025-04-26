;; SPDX-License-Identifier: GPL-3.0-or-later
;; Copyright © 2025 Nicolas Graves <ngraves@ngraves.fr>

(define-module (guix-stack build channel)
  #:use-module (guix git-download)
  #:use-module (guix gexp)
  #:use-module (guix channels)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (guix packages)
  #:use-module (guix profiles)
  #:use-module (guix store)
  #:use-module ((guix utils) #:select (substitute-keyword-arguments))
  #:use-module (guix memoization)
  #:use-module (gnu packages)
  #:use-module (gnu packages guile)
  #:use-module (gnu packages package-management)
  #:use-module (guix build utils)
  #:use-module (guix build-system)
  #:use-module (guix build-system copy)
  #:use-module (guix build-system gnu)
  #:use-module (guix build-system guile)
  #:use-module (guix build guile-build-system)
  #:use-module (guix-local build local-build-system)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-26)
  #:use-module (srfi srfi-71)
  #:use-module (ice-9 match)
  #:use-module (git)
  #:export (build-local-guix
            make-channel-package+instance
            local-channels->manifest))

(define* (is-channel-up-to-date? path
                                 #:optional (source-directory ".")
                                 #:key (effective "3.0")
                                 (find-scm-files-pred
                                  (if (equal? source-directory ".")
                                      (lambda (file stat)
                                        (and (not (string-prefix? "./out" file))
                                             (string-suffix? ".scm" file)))
                                      "\\.scm$")))
  (with-directory-excursion path
    (let* ((out-dir (string-append "out/lib/guile/" effective "/site-ccache"))
           (scm-files (find-files source-directory find-scm-files-pred))
           (prefix-length (string-length source-directory)))

      (define (go-file-path scm-file)
        (let ((file-sans-extension (string-drop
                                    (string-drop-right scm-file 4)
                                    prefix-length)))
          (string-append out-dir file-sans-extension ".go")))

      (define (needs-recompilation? scm-file)
        (let* ((go-file (go-file-path scm-file)))
          (or (not (file-exists? go-file))
              (> (stat:mtime (stat scm-file))
                 (stat:mtime (stat go-file))))))

      (and (directory-exists? "out")
           (not (any needs-recompilation? scm-files))))))

(define* (is-guix-up-to-date? guix-directory
                              #:key (make (which "make")))
  "Compute if Guix is up-to-date in the sense of GNU make.
This enables us not to try and run build steps when not necessary."
  (with-directory-excursion guix-directory
    (catch #t
      (lambda ()
        (and
         (file-exists? "guix-configured.stamp")
         ;; First check the two SUBDIRS of guix.
         (invoke make "-q" "po/guix")
         (invoke make "-q" "po/packages")
         ;; Check that compiled files are up-to-date.
         (is-channel-up-to-date?
          guix-directory
          #:find-scm-files-pred
          (lambda (file stat)
            (and (string-suffix? ".scm" file)
                 (not (string-prefix? "./out" file))
                 (not (string-prefix? "./tests" file))
                 (not (string-prefix? "./build-aux" file))
                 (not (string-prefix? "./gnu/installer" file))
                 (not (string-prefix? "./gnu/tests" file))
                 (not (string-prefix? "./doc" file))
                 (not (string-prefix? "./etc" file))
                 (not (member file '("./gnu/build/locale.scm"
                                     "./gnu/build/po.scm"
                                     "./gnu/build/shepherd.scm"
                                     "./gnu/build/svg.scm"
                                     "./guix/build/po.scm"
                                     "./guix/man-db.scm"
                                     "./guix/scripts/system/installer.scm"
                                     "./manifest.scm"
                                     "./meta-test.scm"
                                     "./test.scm"))))))
         (every
          (cut invoke make "SUBDIRS=" "-q" <>)
          ;; We had (blame) some guile code to calculate these files,
          ;; but it takes a lot of time on a section of code we want
          ;; to run often that should barely never change. The bash
          ;; equivalent to find them is:
          ;; make -pn | grep '^all:' | tail -1 | sed 's/all: //' | tr ' ' '\n'
          '("doc/os-config-bare-bones.texi"
            "doc/os-config-desktop.texi"
            "doc/os-config-lightweight-desktop.texi"
            "doc/he-config-bare-bones.scm"
            "nix/libstore/schema.sql.hh"
            ".version"))))
      (lambda args
        #f))))

(define* (build-local-guix path #:optional version)
  (let* ((version (or version
                      (let* ((repo (repository-open path))
                             (commit (oid->string
                                      (object-id
                                       (revparse-single repo "master")))))
                        (git-version "1.4.0" "0" commit))))
         (phases-ignored-when-configured
          '(disable-failing-tests
            disable-translations
            bootstrap
            patch-usr-bin-file
            patch-source-shebangs
            configure
            patch-generated-file-shebangs
            use-host-compressors))
         (local-guix (local-package guix
                                    path
                                    phases-ignored-when-configured)))
    (and
     (or
      (is-guix-up-to-date? path)
      (with-store store
        (build-in-local-container
         store
         (package/inherit local-guix
           (version version)
           (arguments
            (substitute-keyword-arguments (package-arguments local-guix)
              ;; Disable translations for speed.
              ;; ((#:configure-flags flags #~'())
               ;; #~(cons* "--disable-nls" #$flags))
              ;; ((#:modules modules)
               ;; `((srfi srfi-26) ,@modules))
              ((#:phases phases #~%standard-phases)
               #~(modify-phases #$phases
                   ;; Disable translations for speed.
                   (add-before 'bootstrap 'disable-translations
                     (lambda _
                       (substitute* "bootstrap"
                         (("for lang in \\$\\{langs\\}")
                          "for lang in "))
                       (substitute* "Makefile.am"
                         (("include po/doc/local\\.mk")
                          "EXTRA_DIST ="))
                       (substitute* "doc/local.mk"
                         (("^(MANUAL|COOKBOOK)_LANGUAGES = .*" all type)
                          (string-append type "_LANGUAGES =\n"))
                         ;; This is the rule following info_TEXINFOS.
                         (("%C%_guix_TEXINFOS =" all)
                          (string-append
                           "info_TEXINFOS=%D%/guix.texi %D%/guix-cookbook.texi\n"
                           all)))))
                   ;; FIXME arguments substitutions other than phases
                   ;; don't seem to apply : tests are run despite #:tests? #f
                   (delete 'copy-bootstrap-guile)
                   (delete 'set-SHELL)
                   (delete 'check)
                   ;; FIXME strip has the same issue
                   ;; => Run it in copy-build-system for now.
                   (delete 'strip)
                   ;; Run it only when we need to debug, saves us a few seconds.
                   (delete 'validate-runpath))))))))))))

(define (instantiate-local-guix path)
  (let* ((repo (repository-open path))
         (commit (oid->string
                  (object-id (revparse-single repo "master"))))
         (version (git-version "1.4.0" "0" commit)))
    (build-local-guix path version)
    (package/inherit guix
      (version version)
      (source
       (local-file (string-append path "/out")
                   "local-guix"
                   #:recursive? #t))
      (build-system copy-build-system)
      (arguments
       (list #:substitutable? #f
             #:strip-directories #~'("libexec" "bin")
             #:validate-runpath? #f
             #:phases
             #~(modify-phases %standard-phases
                 ;; The next phases have been applied already.
                 ;; No need to repeat them several times.
                 (delete 'validate-documentation-location)
                 (delete 'delete-info-dir-file)))))))

(define make-channel-package+instance
  (memoize
   (lambda (path)
     (let* ((dir (dirname path))
            (name (basename path))
            (repo (repository-open path))
            (commit-ref
             (oid->string
              (object-id (catch 'git-error
                           (lambda () (revparse-single repo "master"))
                           (lambda _ (revparse-single repo "main"))))))
            (origin (remote-lookup repo "origin"))
            (uri (remote-url origin))
            (home-page (if (string-prefix? "git@" uri)
                           (error
                            (format
                             #f "~a: origin remote is not an http public link"
                             path))
                           uri))
            (local-channel (channel
                            (name (string->symbol name))
                            ;; Currently all are using master.
                            (branch "master")
                            (commit commit-ref)
                            (url home-page))))
       (match name
         ("guix" (values (instantiate-local-guix path)
                         ((@@ (guix channels) channel-instance)
                          local-channel commit-ref path)))
         (_
          (let* ((metadata
                  ((@@ (guix channels) read-channel-metadata-from-source) path))
                 (src-directory
                  ((@@ (guix channels) channel-metadata-directory) metadata))
                 (dependencies
                  (map (compose (cut string-append dir "/" <>)
                                symbol->string
                                channel-name)
                       ((@@ (guix channels) channel-metadata-dependencies)
                        metadata)))
                 (phases-ignored-when-configured
                  '(patch-usr-bin-file
                    patch-source-shebangs
                    patch-generated-file-shebangs))
                 (guile guile-3.0)
                 (effective "3.0")
                 (pkg
                  (package
                    (name name)
                    (version (string-take commit-ref 7))
                    (source #f)
                    (build-system (local-build-system
                                   guile-build-system #:target-directory path))
                    (arguments
                     (local-arguments
                      (append
                       (if (equal? src-directory "/")
                           '()
                           (list #:source-directory (string-drop src-directory 1)))
                       (list #:modules '((guix build utils)
                                         (ice-9 match)
                                         (srfi srfi-1))))
                      phases-ignored-when-configured
                      path))
                    (inputs
                     (let ((guix-pkg _ (make-channel-package+instance
                                        (string-append dir "/guix"))))
                       (append
                        (list guile guix-pkg)
                        (map make-channel-package+instance dependencies))))
                    (home-page home-page)
                    (synopsis (string-append name " channel"))
                    (description (string-append name " channel"))
                    (license license:gpl3+))))
            (and (or (is-channel-up-to-date? path
                                             (if (equal? src-directory "/")
                                                 "."
                                                 (string-drop src-directory 1))
                                             #:effective effective)
                     (with-store store
                       (build-in-local-container store pkg))))
            (values
             (package/inherit pkg
               (source
                (local-file (string-append path "/out")
                            (string-append "local-" name)
                            #:recursive? #t))
               (build-system copy-build-system)
               (arguments
                (list #:substitutable? #f
                      #:validate-runpath? #f
                      #:phases
                      #~(modify-phases %standard-phases
                          ;; The next phases have been applied already.
                          ;; No need to repeat them several times.
                          (delete 'validate-documentation-location)
                          (delete 'delete-info-dir-file)))))
             ((@@ (guix channels) channel-instance)
              local-channel commit-ref path)))))))))

(define (local-channels->manifest target-directory names)

  (define (local-channel->entry instance pkg)
    (let* ((channel (channel-instance-channel instance))
           (commit  (channel-instance-commit instance)))
      (manifest-entry
        (name (symbol->string (channel-name channel)))
        (version (string-take commit 7))
        (item pkg)
        (properties
         `((source ,(channel-instance->sexp instance)))))))

  (manifest (map (lambda (name)
                   (let* ((path (string-append target-directory "/" name))
                          (pkg instance (make-channel-package+instance path)))
                     (local-channel->entry instance pkg)))
                 names)))
