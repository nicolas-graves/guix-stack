;;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Copyright © 2024, 2025 Nicolas Graves <ngraves@ngraves.fr>

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
  #:use-module (guix derivations)
  #:use-module (guix monads)
  #:use-module (guix status)
  #:use-module (guix store)
  #:use-module ((guix ui) #:select (with-error-handling))
  #:use-module (guix-stack build channel)
  #:use-module (git)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-26)
  #:use-module (srfi srfi-71)
  #:export (stack-pull))

;; TODO: Would be good to avoid those awful reload-module invocations.

(define channel-or-instance-name
  (match-lambda
    ((? channel? this-channel)
     (channel-name this-channel))
    ((? channel-instance? this-instance)
     (channel-name
      (channel-instance-channel this-instance)))))

(define (stack-parse-command-line args)
  (eval
   `(begin
      (reload-module (current-module))

      (define (no-arguments arg _)
        (leave (G_ "~A: extraneous argument~%") arg))

      (let* ((%options (cons*
                        (option '(#\f "force") #f #f
                                (lambda (opt name arg result)
                                  (alist-cons 'force? #t result)))
                        (option '("from-local-channels") #t #f
                                (lambda (opt name arg result)
                                  (alist-cons 'local-channels-dir #t result)))
                        %options))
             (opts (parse-command-line ',args %options
                                       (list %default-options)
                                       #:argument-handler no-arguments))
             (unsupported '(ref repository-url)))
        (remove (lambda (item)
                  (member (car item) unsupported))
                opts)))
   (resolve-module '(guix scripts pull) #:ensure #f)))

(define (channel-or-instance-list opts)
  "Return the list of channel-instances to use.  If OPTS specify a
channel file, channels are read from there; otherwise, if
~/.config/guix/channels.scm exists, read it; otherwise
%DEFAULT-CHANNELS is used.  Apply channel transformations specified in
OPTS (resulting from '--url', '--commit', or '--branch'), if any."
  (eval
   `(begin
      (reload-module (current-module))

      (define file
        (assoc-ref ',opts 'channel-file))

      (define ignore-channel-files?
        (assoc-ref ',opts 'ignore-channel-files?))

      (define default-file
        (string-append (config-directory) "/channels.scm"))

      (define global-file
        (string-append %sysconfdir "/guix/channels.scm"))

      (define (load-channels-and-instances file)
        (define (channel-or-instance? cand)
          (or (channel? cand) (channel-instance? cand)))

        (let ((result (load* file (make-user-module '((guix channels))))))
          (if (and (list? result) (every channel-or-instance? result))
              result
              (leave
               (G_ "'~a' did not return a list of channels or instances~%")
               file))))

      (cond (file
             (load-channels-and-instances file))
            ((and (not ignore-channel-files?)
                  (file-exists? default-file))
             (load-channels-and-instances default-file))
            ((and (not ignore-channel-files?)
                  (file-exists? global-file))
             (load-channels-and-instances global-file))
            (else
             %default-channels)))

   (resolve-module '(guix scripts pull) #:ensure #f)))

(define (are-channels-up-to-date? current-channels futures)
  "Check if CURRENT-CHANNELS need to be updated.

FUTURES is a list of channel or channel-instance."
  (and
   (null? (lset-xor eq?
                    (map channel-name current-channels)
                    (map channel-or-instance-name futures)))
   (every
    (lambda (current)
      (match (find
              (lambda (ch)
                (eq? (channel-name current) (channel-or-instance-name ch)))
              futures)
        ((? channel? next)
         (string= (channel-commit current)
                  (or (channel-commit next)
                      (and=> (repository-open (channel-url next))
                             (lambda (url)
                               (oid->string
                                (object-id
                                 (revparse-single
                                  url (channel-branch next))))))
                      (make-string 40 #\0))))
        ((? channel-instance? next)
         (eq? (channel-url current)
              (with-store store
                (run-with-store store
                  (mlet* %store-monad
                      ((source (lower-object
                                (channel-instance-checkout next)))
                       (_ (built-derivations (list source))))
                    (return (derivation->output-path source)))))))
        (_ #f)))
    current-channels)))

(define* (local-build-and-install instances profile
                                  #:key (target-directory getcwd))
  "Build the tool from SOURCE, and install it in PROFILE.  When DRY-RUN? is
true, display what would be built without actually building it."
  (eval
   `(begin
      (reload-module (current-module))

      (define update-profile
        (store-lift build-and-use-profile))

      (define guix-command
        ;; The 'guix' command before we've built the new profile.
        (which "guix"))

      ;; XXX: Beginning of Guix source code change.
      (mlet %store-monad ((manifest (local-channels->manifest
                                     instances
                                     #:target-directory target-directory)))
        ;; XXX: End of Guix source code change.
        (mbegin %store-monad
          (update-profile profile manifest
                          ;; Create a version 3 profile so that it is readable by
                          ;; old instances of Guix.
                          #:format-version 3
                          #:hooks %channel-profile-hooks)

          (return
           (let ((more? (display-channel-news-headlines profile)))
             (newline)
             (when more?
               (display-hint
                (G_ "Run @command{guix pull --news} to read all the news.")))))
          (if guix-command
              (let ((new (map (cut string-append <> "/bin/guix")
                              (list (user-friendly-profile profile)
                                    profile))))
                ;; Is the 'guix' command previously in $PATH the same as the new
                ;; one?  If the answer is "no", then suggest 'hash guix'.
                (unless (member guix-command new)
                  (display-hint (G_ "After setting @code{PATH}, run
@command{hash guix} to make sure your shell refers to @file{~a}.")
                                (first new)))
                (return #f))
              (return #f)))))

   (resolve-module '(guix scripts pull) #:ensure #f)))

(define* (stack-pull args)
  "Call `stack-force-pull' if there are new commits in source directories."

  (with-error-handling
    (with-git-error-handling
     (let* ((opts (stack-parse-command-line args))
            (profile (or (assq-ref opts 'profile) %current-profile))
            (current-channels (profile-channels profile))
            (read-channels-and-instances (channel-or-instance-list opts)))
       (if (and
            (not (assq-ref opts 'force?))
            (are-channels-up-to-date? current-channels
                                      read-channels-and-instances))
        (display "Pull: Nothing to be done.\n")
        (let ((channels instances
                        (partition channel? read-channels-and-instances)))
          (stack-force-pull ; Add preloaded options to avoid loading them twice.
           #:channels channels
           #:instances instances
           #:opts opts)))))))

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
                                        ',instances))
                            (local-channels-dir
                             (assoc-ref opts 'local-channels-dir)))
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
                           ;; XXX: Beginning of Guix source code change.
                           (if local-channels-dir
                               (local-build-and-install instances profile
                                                        #:target-directory
                                                        local-channels-dir)
                               (build-and-install instances profile))
                           ;; XXX: End of Guix source code change.
                           )))))))))))))
   (resolve-module '(guix scripts pull) #:ensure #f)))
