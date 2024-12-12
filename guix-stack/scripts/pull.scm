;;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Copyright © 2024 Nicolas Graves <ngraves@ngraves.fr>

(define-module (guix-stack scripts pull)
  #:use-module (guix channels)
  #:use-module ((guix diagnostics) #:select (leave))
  #:use-module (guix gexp)
  #:use-module ((guix git) #:select (with-git-error-handling))
  #:use-module (guix i18n)
  #:use-module (guix profiles)
  #:use-module ((guix scripts build)
                #:select (set-build-options-from-command-line))
  ;; #:use-module (guix scripts pull)
  #:use-module (guix status)
  #:use-module (guix store)
  #:use-module ((guix ui) #:select (with-error-handling))
  #:use-module (git)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-71)
  #:export (stack-pull))

;; TODO: Would be good to avoid those awful reload-module invocations.
;; TODO: Add a --force option to go straight to stack-force-pull if necessary.

(define (stack-parse-command-line args)
  (eval
   `(begin
      (reload-module (current-module))

      (define (no-arguments arg _)
        (leave (G_ "~A: extraneous argument~%") arg))

      (parse-command-line ',args %options
                          (list %default-options)
                          #:argument-handler no-arguments))
   (resolve-module '(guix scripts pull) #:ensure #f)))

(define* (stack-pull #:key (args (list "--allow-downgrades"
                                         "--disable-authentication")))
  "Call `stack-force-pull' if there are new commits in source directories."
  (with-error-handling
    (with-git-error-handling
     (let* ((opts (stack-parse-command-line args))
            (profile (or (assoc-ref opts 'profile) %current-profile))
            (current-channels (profile-channels profile))
            ;; This is more powerful but also more dangerous than load-channels
            (read-channels (primitive-load (assoc-ref opts 'channel-file)))
            (channels instances (partition channel? read-channels))
            (next-channels (pk 'nc (append
                                    channels
                                    (map
                                     (lambda (instance)
                                       (let ((this-channel
                                              (channel-instance-channel instance)))
                                         (if (file-like?
                                              (channel-instance-checkout instance))
                                             (channel (inherit this-channel)
                                                      (commit #f))
                                             this-channel)))
                                     instances)))))
       (if
        (and
         (eq? (length current-channels) (length next-channels))
         (every (lambda (current)
                  (let* ((next-channel (find
                                        (lambda (channel)
                                          (eq? (channel-name channel)
                                               (channel-name current)))
                                        next-channels)))
                    (string= (channel-commit current)
                             (or (channel-commit next-channel)
                                 (pk 'next
                                     (let ((url (channel-url next-channel)))
                                       (and (file-exists? url)
                                            (oid->string
                                             (object-id
                                              (revparse-single
                                               (repository-open url)
                                               (channel-branch next-channel)))))))
                                 (make-string 40 #\0)))))
                current-channels))
        (display "Pull: Nothing to be done.\n")
        (stack-force-pull ; Add preloaded options to avoid laoding them twice.
         #:channels channels
         #:instances instances
         #:opts opts))))))

(define* (stack-force-pull #:key
                           (channels '())
                           (instances '())
                           (opts '()))
  "Lightly modified version of `guix pull'."

  (eval
   `(begin
      (reload-module (current-module))
      (with-error-handling
        (with-git-error-handling
         (let* ((opts ',opts)
                (substitutes? (assoc-ref opts 'substitutes?))
                (dry-run?     (assoc-ref opts 'dry-run?))
                (profile      (or (assoc-ref opts 'profile) %current-profile))
                (current-channels (profile-channels profile))
                (validate-pull    (assoc-ref opts 'validate-pull))
                (authenticate?    (assoc-ref opts 'authenticate-channels?)))
           (cond
            ((assoc-ref opts 'query)
             (process-query opts profile))
            ((assoc-ref opts 'generation)
             (process-generation-change opts profile))
            (else
             ;; Bail out early when users accidentally run, e.g., ’sudo guix pull’.
             ;; If CACHE-DIRECTORY doesn't yet exist, test where it would end up.
             (validate-cache-directory-ownership)

             (with-store store
               (with-status-verbosity (assoc-ref opts 'verbosity)
                 (parameterize ((%current-system (assoc-ref opts 'system))
                                (%graft? (assoc-ref opts 'graft?)))
                   (with-build-handler (build-notifier #:use-substitutes?
                                                       substitutes?
                                                       #:verbosity
                                                       (assoc-ref opts 'verbosity)
                                                       #:dry-run? dry-run?)
                     (set-build-options-from-command-line store opts)
                     (ensure-default-profile)
                     (honor-x509-certificates store)

                     ;; XXX: Guix source code change.
                     (let* ((instances (append
                                        (latest-channel-instances
                                         store ',channels
                                         #:current-channels current-channels
                                         #:validate-pull validate-pull
                                         #:authenticate? authenticate?)
                                        ',instances)))
                       ;; XXX: End of Guix source code change.
                       (format (current-error-port)
                               (N_ "Building from this channel:~%"
                                   "Building from these channels:~%"
                                   (length instances)))
                       (for-each (lambda (instance)
                                   (let ((channel
                                          (channel-instance-channel instance)))
                                     (format (current-error-port)
                                             "  ~10a~a\t~a~%"
                                             (channel-name channel)
                                             (channel-url channel)
                                             (string-take
                                              (channel-instance-commit instance)
                                              7))))
                                 instances)
                       (with-profile-lock profile
                         (run-with-store store
                           (build-and-install instances profile))))))))))))))
   (resolve-module '(guix scripts pull) #:ensure #f)))
