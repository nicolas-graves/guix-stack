;;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Copyright © 2025 Nicolas Graves <ngraves@ngraves.fr>

(define-module (guix-stack-channel))

(use-modules (ice-9 match)
             (srfi srfi-1)
             (guix packages)
             (guix gexp)
             (guix git)
             (guix git-download)
             (guix build-system guile)
             ((guix licenses) #:prefix license:)
             (guix utils)
             (gnu packages gawk)
             (gnu packages guile)
             (gnu packages package-management))

(define-public guix-stack
  (let ((commit "0caa40ed250bc1760bc42d1895478ecaa26ae85c")
        (revision "15"))
    (package
      (name "guix-stack")
      (version (git-version "0.0.0" revision commit))
      (source
       (git-checkout
        (url "https://git.sr.ht/~ngraves/guix-stack")
        (commit commit)))
      (build-system guile-build-system)
      (arguments
       (list
        #:source-directory "src"
        #:modules '((srfi srfi-1)
                    (srfi srfi-26)
                    (guix build utils)
                    (guix build guile-build-system))
        #:phases
        (let ((guile (this-package-input "guile")))
          #~(modify-phases %standard-phases
              (add-after 'unpack 'configure
                (lambda _
                  (let* ((guile-bin (string-append #$guile "/bin/guile"))
                         (guile-version
                          #$(string-join
                             (take (string-split (package-version guile) #\.) 2)
                             "."))
                         (load-compiled-path (getenv "GUILE_LOAD_COMPILED_PATH"))
                         (load-path (getenv "GUILE_LOAD_PATH")))
                    (substitute* "src/guix/extensions/stack.scm"
                      (("@GUILE@") guile-bin)
                      (("@GUILE_LOAD_PATH@") load-path)
                      (("@GUILE_LOAD_COMPILED_PATH@") load-compiled-path)
                      (("@OWN_GUILE_LOAD_PATH@")
                       (string-append
                        #$output "/share/guile/site/" guile-version))
                      (("@OWN_GUILE_LOAD_COMPILED_PATH@")
                       (string-append #$output "/lib/guile/"
                                      guile-version "/site-ccache"))))))
              (add-before 'build 'install-hook
                (lambda _
                  (let ((hookdir (string-append #$output "/share/git/hooks")))
                    (substitute* "src/guix-stack/scripts/hook.scm"
                      (("@GIT_SENDEMAIL_VALIDATE_HOOK@")
                       (string-append hookdir "/sendemail-validate")))
                    (install-file "git/hooks/sendemail-validate" hookdir))))
              (add-before 'build 'install-guix-extension
                (lambda _
                  (install-file
                   "src/guix/extensions/stack.scm"
                   (string-append #$output "/share/guix/extensions"))
                  (delete-file-recursively "src/guix")))))))
      (inputs
       (list gawk guile-3.0 guile-git guix))
      (home-page "https://git.sr.ht/~ngraves/guix-stack")
      (synopsis "Tools for local development on GNU Guix")
      (description "This package provides a guix extension to with
helpful tools for local development.")
      (license license:gpl3+))))
