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
  #:use-module (guix scripts environment)
  #:use-module (gnu system file-systems)
  #:use-module (srfi srfi-1)
  #:use-module (ice-9 match)
  #:use-module (gnu packages)
  #:use-module (guix build utils)
  #:use-module (guix build-system)
  #:export (make-local-build-system
            build-in-local-container
            local-phases))

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

(define* (build-in-local-container store package)
  "Build local PACKAGE in a container locally."
  (with-store store
    ;; We can't use package->derivation directly because we want the
    ;; user rather than the daemon to build the derivation.
    ;; This allows us to have access to the pre-built files without
    ;; having to mess with hashes or timestamps.
    (let* ((manifest (package->development-manifest package))
           (bag (package->bag package))
           ;; See (@@ (guix scripts environment) manifest->derivation).
           (prof-drv ((store-lower profile-derivation)
                      store manifest #:allow-collisions? #t))
           (drv ((@@ (guix packages) bag->derivation*) store bag package))
           (_ (build-derivations store
                                 (cons* prof-drv (derivation-inputs drv))))
           (profile (derivation->output-path prof-drv)))
      (catch #t
        (lambda ()
          ((store-lower launch-environment/container)
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
            (_         #f)))))))

(define (local-phases phases to-ignore path)
  "Modify phases to incorporate configured phases caching logic."
  (let ((filtered-phases
         (if (file-exists? (string-append path "/guix-configured.stamp"))
             ;; This fold is a simple opposite filter-alist based on key.
             #~(begin
                 (use-modules (srfi srfi-1))
                 (fold
                  (lambda (key result)
                    (if (member (car key) '#$to-ignore)
                        result
                        (cons key result)))
                  '()
                  (reverse #$phases)))
             phases)))
    #~(modify-phases #$filtered-phases
        (add-before 'unpack 'delete-former-output
          (lambda _
            (when (file-exists? "out")
              (delete-file-recursively "out"))
            (let ((gitignore (open-file ".gitignore" "a")))
              (display "out\nguix-configured.stamp" gitignore)
              (close-port gitignore))))
        ;; The source is the current working directory.
        (delete 'unpack)
        (add-before 'build 'flag-as-cached
          (lambda _
            (call-with-output-file "guix-configured.stamp"
              (const #t)))))))
