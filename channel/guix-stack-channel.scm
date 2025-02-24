;;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Copyright © 2025 Nicolas Graves <ngraves@ngraves.fr>

(define-module (guix-stack-channel))

(use-modules (ice-9 match)
             (srfi srfi-1)
             (guix packages)
             (guix gexp)
             (guix git)
             (guix download)
             (guix git-download)
             (guix build-system guile)
             ((guix licenses) #:prefix license:)
             (guix utils)
             (gnu packages gawk)
             (gnu packages guile)
             (gnu packages package-management))

(define-public guile-git-with-revwalker
  (package
    (inherit guile-git)
    (name "guile-git-with-revwalker")
    (source
     (origin
       (inherit (package-source guile-git))
       (patches
        (list
         (origin
           (method url-fetch)
           (uri "https://lists.sr.ht/~ngraves/devel/%3C20250115001917.20631-2-ngraves@ngraves.fr%3E/raw")
           (sha256 (base32 "1papq9lvzqnipwb2nvfwmm5xzs4ls6bvhndqn9k2ff52lkdbm5rh")))
         (origin
           (method url-fetch)
           (uri "https://lists.sr.ht/~ngraves/devel/%3C20250115042525.29416-1-ngraves@ngraves.fr%3E/raw")
           (sha256 (base32 "1nxy7wp6882x6cdcqywvy90q37dnlblibh62g584pycyvwx88hlp")))))))))

(define-public guix-stack
  (let ((commit "aec44ed")
        (revision "20"))
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
                    (install-file "git/hooks/sendemail-validate" hookdir))))
              (add-before 'build 'install-guix-extension
                (lambda _
                  (install-file
                   "src/guix/extensions/stack.scm"
                   (string-append #$output "/share/guix/extensions"))
                  (delete-file-recursively "src/guix")))))))
      (inputs
       (list gawk guile-3.0 guile-git-with-revwalker guix))
      (home-page "https://git.sr.ht/~ngraves/guix-stack")
      (synopsis "Tools for local development on GNU Guix")
      (description "This package provides a guix extension to with
helpful tools for local development.")
      (license license:gpl3+))))
