(define-module (tests)
  #:use-module (ares suitbl core)
  #:use-module (git)
  #:use-module (git structs)
  #:use-module (rnrs bytevectors)
  #:use-module (ice-9 match)
  #:use-module (ice-9 popen)
  #:use-module (ice-9 rdelim)
  #:use-module (ice-9 textual-ports)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-71))

;; Helpers

(define-syntax-rule (with-email-headers headers body ...)
  "Populate /tmp/email-headers.txt with email HEADERS, then run BODY."
  (let ((file "/tmp/email-headers.txt"))
    (dynamic-wind
        (const #t)
        (lambda ()
          (call-with-output-file file
            (lambda (port)
              (display headers port)))
          body ...)
        (lambda ()
          (delete-file file)
          #f))))

;; Copied from (guix scripts system)
(define-syntax-rule (save-environment-excursion body ...)
  "Save the current environment variables, run BODY..., and restore them."
  (let ((env (environ)))
    (dynamic-wind
        (const #t)
        (lambda ()
          body ...)
        (lambda ()
          (environ env)))))

(define (apply-env-vars vars)
  (for-each (match-lambda
              ((var . value)
               (setenv var value)))
            vars))

(define-syntax-rule (with-environment vars body ...)
  (save-environment-excursion
   (apply-env-vars vars)
   body ...))

(define* (hook-eval #:optional
                    (commit-file "/tmp/null.txt")
                    (headers-file "/tmp/email-headers.txt"))
  (let* ((cmd (format #f "awk -f ~s ~s ~s"
                      (string-append (dirname (dirname (current-filename)))
                                     "/git/hooks/sendemail-validate.awk")
                      commit-file headers-file))
         (port (open-input-pipe cmd))
         (result (get-string-all port)))
    (close-pipe port)
    (if (and (not (string-null? result)) (not (equal? "#<unspecified>" result)))
        result
        "")))

(define (parse-hook-output str)
  (define (parse-line line)
    (string-trim (cadr (string-split line #\:))))

  (call-with-input-string str
    (lambda (port)
      (let ((first-line  (read-line port))
            (second-line (read-line port)))
        (if (or (string= first-line "\
Skipping commit: Not the last patch in the series.")
                (not (string= second-line "")))
            (values #f #f #f #f)
            (let ((lst            (parse-line (read-line port)))
                  (message-id     (parse-line (read-line port)))
                  (version        (string->number
                                   (parse-line (read-line port))))
                  (number-patches (string->number
                                   (parse-line (read-line port)))))
              (values lst message-id version number-patches)))))))

;; Test suite

(test-runner*)

(define-suite guix-stack-hook-suite
  (setenv "GUIX_STACK_TEST" "1")

  (test "fails-when-not-last-patch"
    (is
     (with-environment '(("GIT_SENDEMAIL_FILE_COUNTER" . "1")
                         ("GIT_SENDEMAIL_FILE_TOTAL" . "3"))
       (with-email-headers
        "Message-ID: <msgid>\nTo: mailing-list\nSubject: [PATCH 1/3]"
        (let ((message-id mailing-list version number-patches
                          (parse-hook-output (hook-eval))))
          (not (any identity (list message-id mailing-list version number-patches))))))))

  (test "plain"
    (is
     (with-environment '(("GIT_SENDEMAIL_FILE_COUNTER" . "1")
                         ("GIT_SENDEMAIL_FILE_TOTAL" . "1"))
       (with-email-headers
        "Message-ID: <msgid>\nTo: mailing-list\nSubject: [PATCH] Simple patch"
        (let ((mailing-list message-id version number-patches
                            (parse-hook-output (hook-eval))))
          (and (string=? message-id "<msgid>")
               (string=? mailing-list "mailing-list")
               (= version 1)
               (= number-patches 1)))))))

  (test "version"
    (is
     (with-environment '(("GIT_SENDEMAIL_FILE_COUNTER" . "1")
                         ("GIT_SENDEMAIL_FILE_TOTAL" . "1"))
       (with-email-headers
        "Message-ID: <msgid-v>\nTo: mailing-list\nSubject: [PATCH v3] Another patch"
        (let ((mailing-list message-id version number-patches
                            (parse-hook-output (hook-eval))))
          (and (string=? message-id "<msgid-v>")
               (string=? mailing-list "mailing-list")
               (= version 3)
               (= number-patches 1)))))))

  (test "counter"
    (is
     (with-environment '(("GIT_SENDEMAIL_FILE_COUNTER" . "2")
                         ("GIT_SENDEMAIL_FILE_TOTAL" . "2"))
       (with-email-headers
        "Message-ID: <msgid-v>\nTo: mailing-list\nSubject: [PATCH 2/2] Another patch"
        (let ((mailing-list message-id version number-patches
                            (parse-hook-output (hook-eval))))
          (and (string=? message-id "<msgid-v>")
               (string=? mailing-list "mailing-list")
               (= version 1)
               (= number-patches 2)))))))

  (test "version+counter"
    (is
     (with-environment '(("GIT_SENDEMAIL_FILE_COUNTER" . "3")
                         ("GIT_SENDEMAIL_FILE_TOTAL" . "3"))
       (with-email-headers
        "Message-ID: <msgid>\nTo: mailing-list\nSubject: [PATCH v2 3/3]"
        (let ((mailing-list message-id version number-patches
                            (parse-hook-output (hook-eval))))
          (and (string=? mailing-list "mailing-list")
               (string=? message-id "<msgid>")
               (= version 2)
               (= number-patches 3)))))))

  (test "cover-letter"
  (is
   (with-environment '(("GIT_SENDEMAIL_FILE_COUNTER" . "4")
                       ("GIT_SENDEMAIL_FILE_TOTAL" . "4"))
     (with-email-headers
      "Message-ID: <msgid>\nTo: mailing-list\nSubject: [PATCH 3/3]"
      (let ((mailing-list message-id version number-patches
                          (parse-hook-output (hook-eval))))
        (and (string=? message-id "<msgid>")
             (string=? mailing-list "mailing-list")
             (= version 1)
             (= number-patches 3)))))))
(test "cover-letter"
  (is
   (with-environment '(("GIT_SENDEMAIL_FILE_COUNTER" . "4")
                       ("GIT_SENDEMAIL_FILE_TOTAL" . "4"))
     (with-email-headers
      "Message-ID: <msgid>\nTo: mailing-list\nSubject: [PATCH 3/3]"
      (let ((mailing-list message-id version number-patches
                          (parse-hook-output (hook-eval))))
        (and (string=? message-id "<msgid>")
             (string=? mailing-list "mailing-list")
             (= version 1)
             (= number-patches 3))))))))

(guix-stack-hook-suite)

;; Local Variables:
;; eval: (put 'test 'scheme-indent-function 1)
;; eval: (put 'with-environment 'scheme-indent-function 1)
;; End:
