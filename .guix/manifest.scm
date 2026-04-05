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
     (let ((top (dirname (dirname (current-filename)))))
       (local-file top
                   #:recursive? #t
                   #:select? (git-predicate top))))))

(match (cadr (command-line))
  ("build" guix-stack/devel)
  ("shell" (package->development-manifest guix-stack/devel))
  (_ (package->development-manifest guix-stack/devel)))
