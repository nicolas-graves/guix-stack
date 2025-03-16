;; SPDX-License-Identifier: GPL-3.0-or-later
;; Copyright © 2025 Nicolas Graves <ngraves@ngraves.fr>

(define-module (guix-stack build patch)
  #:use-module (guix gexp)
  #:use-module (guix packages)
  #:export (patch-source-phase))

(define* (patch-source-phase source
                             #:key
                             (flags #~("-p1"))
                             (patch (@ (gnu packages base) patch)))
  ;; XXX: copied from guix/packages.scm
  (define (apply-patch patch)
    (format (current-error-port) "applying '~a'...~%" patch)

    ;; Use '--force' so that patches that do not apply perfectly are
    ;; rejected.  Use '--no-backup-if-mismatch' to prevent making
    ;; "*.orig" file if a patch is applied with offset.
    (invoke (string-append patch "/bin/patch")
            "--force" "--no-backup-if-mismatch"
            flags "--input" patch))

  (when (not (file-exists? "guix-configured.stamp"))
    (for-each apply-patch (origin-patches source))

    ;; XXX: copied from guix/packages.scm
    ;; Works but there's no log yet.
    (let ((snippet (origin-snippet source)))
      (if snippet
          #~(let ((module (make-fresh-user-module)))
              (module-use-interfaces!
               module
               (map resolve-interface '#+(origin-modules source)))
              ((@ (system base compile) compile)
               '#+(if (pair? snippet)
                      (sexp->gexp snippet)
                      snippet)
               #:to 'value
               #:opts %auto-compilation-options
               #:env module))
          #~#t))))
