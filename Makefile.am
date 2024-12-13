# SPDX-License-Identifier: GPL-3.0-or-later
# Guix Stack - Tools for local development on GNU Guix

include guile.am

moddir=$(prefix)/share/guile/site/$(GUILE_EFFECTIVE_VERSION)
godir=$(libdir)/guile/$(GUILE_EFFECTIVE_VERSION)/site-ccache

SOURCES =                                                 \
  src/guix-stack/main.scm                                         \
  src/guix-stack/scripts/pull.scm

extensionsdir = $(prefix)/share/guix/extensions
dist_extensions_DATA =                                    \
  src/guix/extensions/stack.scm

EXTRA_DIST +=      \
  src/guix/extensions/stack.scm.in \
  pre-inst-env.in

# Handle substitution of fully-expanded Autoconf variables.
do_subst = $(SED)					\
  -e 's,[@]GUILE[@],$(GUILE),g'											\
  -e 's,[@]GUILE_LOAD_COMPILED_PATH[@],$(GUILE_LOAD_COMPILED_PATH),g'	\
  -e 's,[@]GUILE_LOAD_PATH[@],$(GUILE_LOAD_PATH),g'						\
  -e 's,[@]guilemoduledir[@],$(guilemoduledir),g'	\
  -e 's,[@]guileobjectdir[@],$(guileobjectdir),g'	\
  -e 's,[@]abs_top_srcdir[@],$(abs_top_srcdir),g'	\
  -e 's,[@]abs_top_builddir[@],$(abs_top_builddir),g'	\
  -e 's,[@]localedir[@],$(localedir),g'

guix/extensions/stack.scm: guix/extensions/stack.scm.in Makefile
	$(AM_V_at)rm -f $@ $@-t
	$(AM_V_at)$(MKDIR_P) "$(@D)"
	$(AM_V_GEN)$(do_subst) < "$(srcdir)/$@.in" > "$@-t"
	mv -f "$@-t" "$@"

CLEANFILES += \
  src/guix/extensions/stack.scm
