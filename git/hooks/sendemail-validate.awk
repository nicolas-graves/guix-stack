#!/usr/bin/env -S awk -f

# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright © 2025 Nicolas Graves <ngraves@ngraves.fr>
# This hook will add a `git note` to the last commit of a patch series,
# in recutils format, such as:
# List:
# Message-ID:
# Version:
# Number-Patches:

BEGIN {
    NUMBER_PATCHES = ENVIRON["GIT_SENDEMAIL_FILE_TOTAL"]
    VERSION = 1
    if (ENVIRON["GIT_SENDEMAIL_FILE_COUNTER"] != NUMBER_PATCHES) {
        print "Skipping commit: Not the last patch in the series."
        exit 0
    }

    EMAIL_HEADERS = ARGV[2]
    ARGV[2] = ""

    # Note: Only for lines, but multiline is not needed for those fields.
    while ((getline line < EMAIL_HEADERS) > 0) {
        if (match(line, /^(Message-ID|To|In-Reply-To|Subject): (.*)/, arr)) {
            if (arr[1] == "Message-ID") {
                MESSAGE_ID = arr[2]
            } else if (arr[1] == "To") {
                MAILING_LIST = arr[2]
            } else if (arr[1] == "In-Reply-To") {
                MAILING_LIST = arr[2]
            } else if (arr[1] == "Subject") {
                if (match(arr[2], /^\[PATCH((\s[^ ]+)+)\]/, out)) {
                    n = split(out[1], parts, " ")
                    for (i = 1; i in parts; i++) {
                        if (match (parts[i], /v([0-9]+)/, ver)) {
                            VERSION = ver[1]
                        } else if (match (parts[i], /[0-9]+\/([0-9]+)/, nb)) {
                            # Useful when there is a cover letter.
                            NUMBER_PATCHES = nb[1]
                        }
                        # We can possibly match a subjectPrefix in the last case.
                        # But we already know the project at that point, so why would we?
                    }
                }
            }
        }
    }
    close(EMAIL_HEADERS)

    MESSAGE =                                                      \
        "guix-stack metadata v1\n\n"                               \
        "List: " MAILING_LIST "\n"                                 \
        "Message-ID: " MESSAGE_ID "\n"                             \
        (IN_REPLY_TO ? "In-Reply-To: " IN_REPLY_TO "\n" : "")      \
        "Version: " VERSION "\n"                                   \
        "Number-Patches: " NUMBER_PATCHES
    # print "DEBUG: MESSAGE = " MESSAGE > /dev/stderr


    if ("GUIX_STACK_TEST" in ENVIRON) {
        print MESSAGE
    } else {
        print "Adding a git note for the patch"
        system("git notes add HEAD --force --message \"" MESSAGE "\"")
    }
    exit 0
}
