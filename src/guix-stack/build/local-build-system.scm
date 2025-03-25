;; SPDX-License-Identifier: GPL-3.0-or-later
;; Copyright © 2025 Nicolas Graves <ngraves@ngraves.fr>

(define-module (guix-stack build local-build-system)
  #:use-module (guix gexp)
  #:use-module (guix channels)
  #:use-module (guix derivations)
  #:use-module (guix packages)
  #:use-module (guix profiles)
  #:use-module ((guix self) #:select (make-config.scm))
  #:use-module (guix store)
  #:use-module (guix modules)
  #:use-module (guix monads)
  #:use-module ((guix utils) #:select (substitute-keyword-arguments))
  #:use-module (guix scripts environment)
  #:use-module (gnu system file-systems)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-71)
  #:use-module (ice-9 ftw)
  #:use-module (ice-9 match)
  #:use-module (gnu packages)
  #:use-module (guix build utils)
  #:use-module (guix build-system)
  #:use-module (git)
  #:export (local-build-system+imported+modules
            build-in-local-container
            local-tarball
            local-arguments
            local-package
            package-with-source*
            submodules-dir->packages))

(define (make-local-lower old-lower target-directory)
  (lambda* args
    (let ((old-bag (apply old-lower args)))
      (bag
        (inherit old-bag)
        (build
         (lambda* (name inputs #:key (outputs '("out"))
                        #:allow-other-keys #:rest rest)
           (mlet %store-monad
               ((builder (apply (bag-build old-bag)
                                name inputs #:outputs outputs rest)))
             (return
              #~(begin
                  (use-modules (guix build utils))
                  (with-directory-excursion #$target-directory
                    (for-each
                     (lambda (out)
                       (setenv
                        out (string-append #$target-directory "/" out)))
                     '#$outputs)
                    #$builder))))))))))

(define* (local-build-system+imported+modules target-build-system
                                              #:key
                                              (target-directory (getcwd)))
  (let ((lower (build-system-lower target-build-system)))
    (values
     (build-system
       (name (symbol-append
              (build-system-name target-build-system) '-local))
       (description (string-append
                     (build-system-description target-build-system)
                     " ; applied as current user in " target-directory))
       (lower (make-local-lower lower target-directory)))
     (procedure-property lower 'default-imported-modules)
     (procedure-property lower 'default-modules))))

(define (default-guix-stack)
  "Return the default guix-stack package."
  ;; Do not use `@' to avoid introducing circular dependencies.
  (let ((module (resolve-interface '(guix-stack-channel))))
    (module-ref module 'guix-stack)))

(define* (build-in-local-container store package)
  "Build local PACKAGE in a container locally."
  ;; We can't use package->derivation directly because we want the
  ;; user rather than the daemon to build the derivation.
  ;; This allows us to have access to the compiled files without
  ;; having to mess with hashes or timestamps.
  (let* ((manifest (package->development-manifest
                    ;; This is to allow us to have access to
                    ;; (guix-stack build patch) during the build.
                    (package/inherit package
                      (native-inputs
                       (modify-inputs (package-native-inputs package)
                         (append (default-guix-stack)
                                 (@ (gnu packages package-management) guix)))))))
         (bag (package->bag package))
         ;; See (@@ (guix scripts environment) manifest->derivation).
         (prof-drv ((store-lower profile-derivation)
                    store manifest #:allow-collisions? #t))
         (drv (run-with-store store (bag->derivation bag package)))
         (_ (build-derivations
             store (cons* prof-drv (if (derivation? drv)
                                       (derivation-inputs drv)
                                       '()))))
         (profile (derivation->output-path prof-drv)))

    (catch #t
      (lambda ()
        ((store-lower
          (@@ (guix scripts environment) launch-environment/container))
         store
         #:command (cons* (derivation-builder drv)
                          (derivation-builder-arguments drv))
         #:bash (string-append profile "/bin/bash")
         #:map-cwd? #t
         #:user-mappings
         (list (specification->file-system-mapping "/gnu/store" #f))
         #:profile profile
         #:manifest manifest))
      (lambda args
        (match args
          (('quit 0) #t)
          (_ (begin (error args) #f)))))))

(define* (local-tarball path #:optional name
                        #:key (exclude-vcs? #t))
  "Like recursive local-file, but keep mtimes using a tarball.

This is intended to be used for local hacks / partial builds."
  ;; XXX Assumes recursive and finish with /.
  (let* ((stripped-path (string-drop-right (basename path) 1))
         (pfx (mkdtemp (format #f "/tmp/local-~aXXXXXX" stripped-path)))
         (tarball (string-append pfx "/" stripped-path ".tar")))
    (and
     (apply invoke
            (append
             (list "tar")
             (if exclude-vcs?
                 '("--exclude-vcs")
                 '())
             (list "-cf" tarball
                   "--format=gnu"
                   "--owner=root:0"
                   "--group=root:0"
                   "--hard-dereference"
                   "-C" (dirname path) (basename path))))
     (local-file tarball (string-append "local-" stripped-path ".tar")))))

(define* (local-arguments arguments to-ignore path
                          #:key
                          (source #f)
                          (default-imported-modules '())
                          (default-modules '()))
  "Modify phases to incorporate configured phases caching logic."
  (let ((patches (origin-patches source))
        (snippet (origin-snippet source)))
    (substitute-keyword-arguments arguments
      ((#:substitutable? _ #t)
       #f)
      ((#:imported-modules modules default-imported-modules)
       (let ((imported-modules
              (cons (make-config.scm)
                    (delete '(guix config)
                            (source-module-closure
                             '((guix-stack build patch)))))))
         `(,@imported-modules ,@modules)))
      ((#:modules modules default-modules)
       `((guix-stack build patch) ,@modules))
      ((#:phases phases #~%standard-phases)
       (let* ((wrapped-phases
               #~(modify-phases #$phases
                   (add-before 'unpack 'delete-former-output
                     (lambda _
                       (when (file-exists? "out")
                         (delete-file-recursively "out"))))
                   (add-after 'unpack 'setup-gitignore
                     (lambda _
                       (let ((gitignore (open-file ".gitignore" "a")))
                         (display "out\nguix-configured.stamp" gitignore)
                         (close-port gitignore))))
                   (add-after 'unpack 'patch-source
                     (lambda _
                       (if #$(null? patches)
                           (format #t "No patches to apply.~%")
                           (patch-source-patches (list #$@patches)))
                       (if #$(not snippet) ; readability in builder
                           (format #t "No snippet to execute.~%")
                           (patch-source-snippet #$snippet))))
                   ;; The source is the current working directory.
                   (delete 'unpack)
                   (add-before 'build 'flag-as-configured
                     (lambda _
                       (call-with-output-file "guix-configured.stamp"
                         (const #t))))))
              (ignore-phases (cons* 'setup-gitignore to-ignore)))
         (if (file-exists? (string-append path "/guix-configured.stamp"))
             ;; This fold is a simple opposite filter-alist based on key.
             #~(begin
                 (use-modules (srfi srfi-1))
                 (fold
                  (lambda (key result)
                    (if (member (car key) '#$ignore-phases)
                        result
                        (cons key result)))
                  '()
                  (reverse #$wrapped-phases)))
             wrapped-phases))))))

(define (local-package pkg target-directory
                       phases-ignored-when-configured)
  (let ((local-build-system imported-modules modules
                            (local-build-system+imported+modules
                             (package-build-system pkg)
                             #:target-directory target-directory)))
    (package/inherit pkg
      (source #f)
      (build-system local-build-system)
      (arguments (local-arguments
                  (package-arguments pkg)
                  phases-ignored-when-configured
                  target-directory
                  #:source (package-source pkg)
                  #:default-imported-modules imported-modules
                  #:default-modules modules)))))

;; Copied and extended from (guix transformations).
(define* (package-with-source* p uri #:optional version
                               #:key (keep-mtime? #f))
  "Return a package based on P but with its source taken from URI.  Extract
the new package's version number from URI."
  (if (file-exists? uri)
      (let* ((repo (repository-open uri))
             (commit (oid->string
                      (object-id (revparse-single repo "HEAD")))))
        (package/inherit p
          (source (if keep-mtime?
                      (local-tarball uri)
                      (local-file
                       (if (string-suffix? "/" uri)
                           (string-drop-right uri 1)
                           uri)
                       #:recursive? #t)))
          (version (string-take commit 7))))
      (let ((base (tarball-base-name (basename uri))))
        (let ((_ version* (hyphen-package-name->name+version base)))
          (package (inherit p)
                   (version (or version version*
                                (package-version p)))

                   ;; Use #:recursive? #t to allow for directories.
                   (source (downloaded-file uri #t)))))))

(define* (submodules-dir->packages #:key (dir "packages"))
  "Provide support for the layout where all directories under a dir are
submodules and their correspond to a development package."
  (filter-map
   (match-lambda
     ((or "." "..") #f)
     (file
      (cons (string->symbol file)
            (package-with-source*
             (specification->package file)
             (canonicalize-path (string-append dir "/" file))))))
   (scandir dir)))
