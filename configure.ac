dnl SPDX-License-Identifier: GPL-3.0-or-later
dnl Guix Stack - Tools for local development on GNU Guix
dnl Copyright © 2024 Nicolas Graves <ngraves@ngraves.fr>
dnl -*- Autoconf -*-

AC_INIT([GUIX STACK],
  [0.0.0],
  [ngraves@ngraves.fr], [guix-stack],
  [https://git.sr.ht/~ngraves/guix-stack/])
AC_CONFIG_AUX_DIR([build-aux])
AM_INIT_AUTOMAKE([color-tests -Wall -Wno-portability foreign])
AM_SILENT_RULES([yes])

GUILE_PKG([3.0])
GUILE_PROGS

if test "x$GUILD" = "x"; then
   AC_MSG_ERROR(['guild' binary not found; please check your Guile installation.])
fi

dnl Installation directories for .scm and .go files.
guilemoduledir="${datarootdir}/guile/site/$GUILE_EFFECTIVE_VERSION"
guileobjectdir="${libdir}/guile/$GUILE_EFFECTIVE_VERSION/site-ccache"
AC_SUBST([guilemoduledir])
AC_SUBST([guileobjectdir])

GUILE_MODULE_REQUIRED(git)

AC_PATH_PROG([SED], [sed])
if test "x$SED" = "x"; then
   AC_MSG_ERROR(['sed' could not be found; it is needed during the build.])
fi

AC_ARG_VAR(GUILE_LOAD_PATH, [The Guile load path to be embedded in the main script])
AC_ARG_VAR(GUILE_LOAD_COMPILED_PATH, [The Guile load path for compiled modules to be embedded in the main script])

AC_CONFIG_FILES([Makefile])
AC_CONFIG_FILES([pre-inst-env], [chmod +x pre-inst-env])

AC_OUTPUT
