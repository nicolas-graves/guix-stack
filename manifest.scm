(use-modules (guix-stack-channel)
             (guix gexp)
             (guix git-download)
             (guix packages)
             (ice-9 match))

(define-public guix-stack/devel
  (package
    (inherit guix-stack)
    (name "guix-stack-devel")
    (source
     (let ((top (dirname (current-filename))))
       (local-file top
                   #:recursive? #t
                   #:select? (git-predicate top))))
    ;; (inputs
    ;;  (list guix guix-guile (p guile-git)))
    ;; (native-inputs
    ;;  (append
    ;;   (list autoconf automake pkg-config texinfo graphviz)
    ;;   (list
    ;;    coreutils

    ;;    ;; for make distcheck
    ;;    texlive-scheme-basic

    ;;    sed

    ;;    ;; For "make release"
    ;;    perl
    ;;    git-minimal

    ;;    ;; For manual post processing
    ;;    guile-lib
    ;;    rsync

    ;;    ;; For "git push"
    ;;    openssh-sans-x

    ;;    ;; For dynamic development
    ;;    guile-next
    ;;    guile-ares-rs)))
    ))

(match (cadr (command-line))
  ("build" guix-stack/devel)
  ("shell" (package->development-manifest guix-stack/devel))
  (_ (package->development-manifest guix-stack/devel)))
