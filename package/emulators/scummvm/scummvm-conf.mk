################################################################################
#
# scummvm -- knulli configure overrides
#
# Not a package override: batocera's scummvm.mk is still the package, this file
# is included before it (external.mk includes knulli's package/*.mk first) and
# seeds variables that batocera only ever appends to.
#
################################################################################

# scummvm autodetects GTK for its file dialogs.  The aarch64-v8a emulator drop
# is harvested on rk3576, where vita3k pulls gtk3 into the image, so scummvm
# linked libgtk-3/libgdk-3/libatk/libgdk_pixbuf there -- and the drop then
# failed on h700, which has none of them.  No knulli board wants GTK dialogs on
# a handheld; turn it off everywhere so the payload does not depend on which
# board happened to build it.
SCUMMVM_CONF_OPTS = --disable-gtk
