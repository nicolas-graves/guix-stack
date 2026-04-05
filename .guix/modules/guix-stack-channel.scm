;;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Copyright © 2025 Nicolas Graves <ngraves@ngraves.fr>

(define-module (guix-stack-channel)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-1)
  #:use-module (guix packages)
  #:use-module (guix gexp)
  #:use-module (guix git)
  #:use-module (guix download)
  #:use-module (guix git-download)
  #:use-module (guix build-system guile)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (guix utils)
  #:use-module (gnu packages gawk)
  #:use-module (gnu packages guile)
  #:use-module (gnu packages package-management))

(define-public guix-stack
  (let ((commit "ef3e147")
        (revision "90"))
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
                       (string-append hookdir "/sendemail-validate.awk")))
                    (install-file "git/hooks/sendemail-validate.awk" hookdir))))
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

guix-stack
