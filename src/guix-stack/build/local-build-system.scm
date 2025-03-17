;; SPDX-License-Identifier: GPL-3.0-or-later
;; Copyright © 2025 Nicolas Graves <ngraves@ngraves.fr>

(define-module (guix-stack build local-build-system)
  #:use-module (guix gexp)
  #:use-module (guix channels)
  #:use-module (guix derivations)
  #:use-module (guix packages)
  #:use-module (guix profiles)
  #:use-module (guix store)
  #:use-module (guix monads)
  #:use-module ((guix utils) #:select (substitute-keyword-arguments))
  #:use-module (guix scripts environment)
  #:use-module (gnu system file-systems)
  #:use-module (srfi srfi-1)
  #:use-module (ice-9 match)
  #:use-module (gnu packages)
  #:use-module (guix build utils)
  #:use-module (guix build-system)
  #:export (make-local-build-system
            build-in-local-container
            local-tarball
            local-arguments))

(define (make-local-lower old-lower target-directory modules)
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
                  (use-modules #$@modules)
                  (with-directory-excursion #$target-directory
                    (for-each
                     (lambda (out)
                       (setenv
                        out (string-append #$target-directory "/" out)))
                     '#$outputs)
                    #$builder))))))))))

(define* (make-local-build-system target-build-system
                                  #:key
                                  (target-directory (getcwd))
                                  (modules '((guix build utils))))
  (build-system
    (name (symbol-append
           (build-system-name target-build-system) '-local))
    (description (string-append
                  (build-system-description target-build-system)
                  " ; applied as current user in " target-directory))
    (lower (make-local-lower (build-system-lower target-build-system)
                             target-directory modules))))

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
         ;; I don't understand how we can have gexps
         ;; here though but it's necessary to work.
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
         #:profile (pk 'profile profile)
         #:manifest manifest))
      (lambda args
        (match args
          (('quit 0) #t)
          (_ (begin (error args) #f)))))))

(define* (local-tarball path #:optional name
                        #:key (exclude-vcs? #t))
  "Like recursive local-file, but keep mtimes using a tarball."
  ;; Intended to be used as an arei buffer.
  ;; We can't intern and keep mtimes with local-file, so
  ;; use this hack to use a wrapper tarball which keeps mtimes.
  (let* ((stripped-path (pk '1 (string-drop-right (basename path) 1)))
         (pfx (pk '2 (mkdtemp (format #f "/tmp/local-~aXXXXXX" stripped-path))))
         (tarball (pk 't (string-append pfx "/" stripped-path ".tar"))))
    (and
     (apply invoke
            (append
             (list "tar")
             (if exclude-vcs?
                 '("--exclude-vcs")
                 '())
             (list "-cf" (pk 't tarball)
                   "--format=gnu"
                   ;; "--owner=root:0"
                   ;; "--group=root:0"
                   ;; "--hard-dereference"
                   "-C" path ".")))
     (local-file tarball (string-append "local-" stripped-path ".tar")))))

(define* (local-arguments arguments to-ignore path #:optional source)
  "Modify phases to incorporate configured phases caching logic."
  (substitute-keyword-arguments arguments
    ((#:substitutable? _) #f)
    ((#:modules modules)
     `((guix-stack build patch)
       ,@modules))
    ((#:imported-modules modules)
     `((guix-stack build patch)
       ,@modules))
    ((#:phases phases)
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
                     (if #$source
                         (patch-source-phase #$source)
                         (format #t "No need to patch source.~%"))))
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
           wrapped-phases)))))
