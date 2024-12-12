# SPDX-License-Identifier: GPL-3.0-or-later
# Stacked Guix (stguix) - Tools for local development on GNU Guix

include guile.am

moddir=$(prefix)/share/guile/site/$(GUILE_EFFECTIVE_VERSION)
godir=$(libdir)/guile/$(GUILE_EFFECTIVE_VERSION)/site-ccache

SOURCES =                                                 \
  stguix/main.scm                                         \
  stguix/scripts/pull.scm

extensionsdir = $(prefix)/share/guix/extensions
dist_extensions_DATA =                                    \
  guix/extensions/stacked.scm

EXTRA_DIST +=      \
  guix/extensions/stacked.scm.in \
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

guix/extensions/stacked.scm: guix/extensions/stacked.scm.in Makefile
	$(AM_V_at)rm -f $@ $@-t
	$(AM_V_at)$(MKDIR_P) "$(@D)"
	$(AM_V_GEN)$(do_subst) < "$(srcdir)/$@.in" > "$@-t"
	mv -f "$@-t" "$@"

CLEANFILES += \
  guix/extensions/stguix.scm
