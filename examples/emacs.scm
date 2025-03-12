(use-modules (guix git)
             (guix git-download)
             (guix gexp)
             (guix scripts)
             (guix packages)
             (guix derivations)
             (guix store)
             (guix utils)
             (guix monads)
             (guix search-paths)
             (guix build utils)
             (srfi srfi-1)
             (srfi srfi-26)
             (ice-9 match)
             (gnu packages)
             (gnu packages emacs)
             (gnu packages base)
             (gnu packages glib)
             (gnu packages version-control)
             (guix build-system)
             (guix build-system copy)
             (guix build-system glib-or-gtk)
             (guix build-system gnu)
             (guix-stack build local-build-system))

(define %srcdir (dirname (current-filename)))

;; XXX: copied from guix/packages.scm
(define instantiate-patch
  (match-lambda
    ((? string? patch)                          ;deprecated
     (local-file patch #:recursive? #t))
    ((? struct? patch)                          ;origin, local-file, etc.
     patch)))

(with-store store
  (let* ((flags #~("-p1"))
         (patches (map instantiate-patch
                       (origin-patches (package-source emacs-pgtk))))
         (phases-ignored-when-configured
          '(patch-compilation-driver
            patch-program-file-names
            enable-elogind
            ;; generate-gdk-pixbuf-loaders-cache-file
            bootstrap
            patch-usr-bin-file
            patch-source-shebangs
            fix-/bin/pwd
            configure
            patch-generated-file-shebangs))
         (emacs-source (package-source emacs-pgtk))
         (pkg
          (package/inherit emacs-pgtk
            (source #f)
            (build-system
              (make-local-build-system (package-build-system emacs-pgtk)
                                       #:target-directory %srcdir))
            (native-inputs
             (modify-inputs (package-native-inputs emacs-pgtk)
               (append patch git-minimal)))
            (arguments
             (substitute-keyword-arguments (package-arguments emacs-pgtk)
               ((#:substitutable? _) #f)
               ((#:phases phases)
                (let ((filtered-phases
                       (local-phases phases
                                     phases-ignored-when-configured
                                     %srcdir)))
                  #~(modify-phases #$filtered-phases
                      ;; FIXME strip-store-file-name breaks it.
                      (delete 'install-license-files)
                      ;; The next phases are also applied with the copy-build-system.
                      ;; No need to repeat them several times.
                      (delete 'strip)
                      (delete 'validate-runpath)
                      (delete 'validate-documentation-location)
                      (delete 'delete-info-dir-file)
                      ;; We need to apply patches and snippets in the source.
                      (add-after 'install-locale 'patch-source
                        (lambda _
                          ;; XXX: copied from guix/packages.scm
                          (define (apply-patch patch)
                            (format (current-error-port) "applying '~a'...~%" patch)

                            ;; Use '--force' so that patches that do not apply perfectly are
                            ;; rejected.  Use '--no-backup-if-mismatch' to prevent making
                            ;; "*.orig" file if a patch is applied with offset.
                            (invoke (string-append #$(this-package-native-input "patch")
                                                   "/bin/patch")
                                    "--force" "--no-backup-if-mismatch"
                                    #+@flags "--input" patch))

                          (when (not (file-exists? "guix-configured.stamp"))
                            (for-each apply-patch '#$patches)

                            ;; XXX: copied from guix/packages.scm
                            ;; Works but there's no log yet.
                            #+(let ((snippet (origin-snippet emacs-source)))
                                (if snippet
                                    #~(let ((module (make-fresh-user-module)))
                                        (module-use-interfaces!
                                         module
                                         (map resolve-interface '#+(origin-modules emacs-source)))
                                        ((@ (system base compile) compile)
                                         '#+(if (pair? snippet)
                                                (sexp->gexp snippet)
                                                snippet)
                                         #:to 'value
                                         #:opts %auto-compilation-options
                                         #:env module))
                                    #~#t)))))
                      (add-before 'install-locale 'delete-former-output
                        (lambda _
                          (when (file-exists? "out")
                            (delete-file-recursively "out"))))
                      (add-before 'build 'flag-as-cached
                        (lambda _
                          (call-with-output-file "guix.configured" (const #t))))))))))))
    (and (build-in-local-container store pkg)
         (package/inherit emacs-pgtk
           (source
            (local-file "out" "local-emacs"
                        #:recursive? #t
                        #:select? (const #t)))
           (build-system copy-build-system)
           (arguments '())))))
