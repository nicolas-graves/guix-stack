(use-modules (guix gexp)
             (guix packages)
             (guix store)
             ((guix utils) #:select (substitute-keyword-arguments))
             (srfi srfi-1)
             (gnu packages emacs)
             (gnu packages version-control)
             (guix build-system copy)
             (guix-stack build local-build-system))

(let* ((source-dir (dirname (current-filename)))
       (phases-ignored-when-configured
        '(patch-compilation-driver
          patch-program-file-names
          enable-elogind
          ;; generate-gdk-pixbuf-loaders-cache-file
          bootstrap
          patch-usr-bin-file
          patch-source-shebangs
          fix-/bin/pwd
          autogen
          configure
          patch-generated-file-shebangs))
       (local-pkg (local-package guile-emacs
                                 source-dir
                                 phases-ignored-when-configured))
       (pkg
        (package/inherit local-pkg
          (arguments
           (substitute-keyword-arguments (package-arguments local-pkg)
             ((#:phases phases)
              #~(modify-phases #$phases
                  ;; FIXME strip-store-file-name breaks it.
                  (delete 'install-license-files)
                  ;; The next phases are also applied with the copy-build-system.
                  ;; No need to repeat them several times.
                  (delete 'strip)
                  (delete 'validate-runpath)
                  (delete 'validate-documentation-location)
                  (delete 'delete-info-dir-file)))
             ((#:configure-flags flags #~'())
              #~(cons* "--with-pgtk" #$flags))))
          (native-inputs
           (modify-inputs (package-native-inputs local-pkg)
             (append git-minimal))))))
  (and (with-store store
         (build-in-local-container store pkg))
       (package/inherit guile-emacs
         (source
          (local-file "out" "local-guilemacs" #:recursive? #t))
         (build-system copy-build-system)
         (arguments '()))))
