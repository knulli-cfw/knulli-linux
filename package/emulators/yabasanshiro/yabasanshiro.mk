################################################################################
#
# yabasanshiro
#
################################################################################
YABASANSHIRO_VERSION = pi4-update
YABASANSHIRO_SITE = https://github.com/sydarn/yabause.git
YABASANSHIRO_SITE_METHOD = git
YABASANSHIRO_GIT_SUBMODULES = YES
YABASANSHIRO_LICENSE = GPLv2
YABASANSHIRO_LICENSE_FILE = LICENSE
YABASANSHIRO_SUBDIR = yabause
YABASANSHIRO_CMAKE_BACKEND = make

YABASANSHIRO_DEPENDENCIES = sdl2 libcurl boost libglfw zlib libpng

# gcc-14 / custom compile flags (keep original - append other flags via CONF_ENV for cross builds)
YABASANSHIRO_TARGET_CFLAGS = -Wno-implicit-function-declaration -Wno-incompatible-pointer-types -Wno-int-conversion

# Remove any global LTO flags before applying a consistent package-local
# configuration to compilation and linking.
YABASANSHIRO_NO_LTO_FLAGS = -flto -flto=% -fuse-linker-plugin -ffat-lto-objects -fno-fat-lto-objects

YABASANSHIRO_CFLAGS = $(filter-out $(YABASANSHIRO_NO_LTO_FLAGS),$(TARGET_CFLAGS))
YABASANSHIRO_CXXFLAGS = $(filter-out $(YABASANSHIRO_NO_LTO_FLAGS),$(TARGET_CXXFLAGS))
YABASANSHIRO_LDFLAGS = $(filter-out $(YABASANSHIRO_NO_LTO_FLAGS),$(TARGET_LDFLAGS))

YABASANSHIRO_LTO_FLAGS = -flto=auto -fuse-linker-plugin -ffat-lto-objects

# Extra linker flags from the custom script
# include -lstdc++fs as the script used
YABASANSHIRO_CONF_ENV += LDFLAGS="$(YABASANSHIRO_LDFLAGS) $(YABASANSHIRO_LTO_FLAGS) -L$(STAGING_DIR)/usr/lib -lpthread -ludev -lstdc++fs"

# Provide CMake install prefix (use /usr for library/binary layout)
YABASANSHIRO_CONF_OPTS += -DCMAKE_INSTALL_PREFIX="/usr"

# Ports / features from the script
YABASANSHIRO_CONF_OPTS += -DYAB_PORTS=retro_arena
YABASANSHIRO_CONF_OPTS += -DUSE_EGL=ON -DUSE_OPENGL=OFF
YABASANSHIRO_CONF_OPTS += -DYAB_WANT_VULKAN=OFF
YABASANSHIRO_CONF_OPTS += -DYAB_WANT_ARM7=ON
YABASANSHIRO_CONF_OPTS += -DYAB_WANT_DYNAREC_DEVMIYAX=ON
YABASANSHIRO_CONF_OPTS += -DSH2_TRACE=OFF
YABASANSHIRO_CONF_OPTS += -DCMAKE_BUILD_TYPE=Release
# Match the working precompiled binary's monolithic linkage.
YABASANSHIRO_CONF_OPTS += -DBUILD_SHARED_LIBS=OFF

# Ensure CMake picks up SDL2 headers from the target sysroot
YABASANSHIRO_CONF_OPTS += -DSDL2_INCLUDE_DIR=$(STAGING_DIR)/usr/include/SDL2
# zlib path used in the custom script
YABASANSHIRO_CONF_OPTS += -DZLIB_INSTALL=$(STAGING_DIR)/usr

# Use standard system OpenGL/EGL libraries instead of specific Mali paths
# Let CMake find the appropriate libraries automatically

# If you want to force a particular C and C++ compiler (host-side cross compiler)
YABASANSHIRO_CONF_OPTS += -DCMAKE_C_COMPILER=$(HOST_DIR)/bin/$(GNU_TARGET_NAME)-gcc
YABASANSHIRO_CONF_OPTS += -DCMAKE_CXX_COMPILER=$(HOST_DIR)/bin/$(GNU_TARGET_NAME)-g++

# Use GCC's linker-plugin-aware archive tools for LTO objects.
YABASANSHIRO_CONF_OPTS += -DCMAKE_AR=$(HOST_DIR)/bin/$(GNU_TARGET_NAME)-gcc-ar
YABASANSHIRO_CONF_OPTS += -DCMAKE_RANLIB=$(HOST_DIR)/bin/$(GNU_TARGET_NAME)-gcc-ranlib
YABASANSHIRO_CONF_OPTS += -DCMAKE_NM=$(HOST_DIR)/bin/$(GNU_TARGET_NAME)-gcc-nm
YABASANSHIRO_CONF_OPTS += -DCMAKE_C_COMPILER_AR=$(HOST_DIR)/bin/$(GNU_TARGET_NAME)-gcc-ar
YABASANSHIRO_CONF_OPTS += -DCMAKE_CXX_COMPILER_AR=$(HOST_DIR)/bin/$(GNU_TARGET_NAME)-gcc-ar
YABASANSHIRO_CONF_OPTS += -DCMAKE_C_COMPILER_RANLIB=$(HOST_DIR)/bin/$(GNU_TARGET_NAME)-gcc-ranlib
YABASANSHIRO_CONF_OPTS += -DCMAKE_CXX_COMPILER_RANLIB=$(HOST_DIR)/bin/$(GNU_TARGET_NAME)-gcc-ranlib

# Point png static library if needed (kept from your original)
YABASANSHIRO_CONF_OPTS += -Dpng_STATIC_LIBRARIES=$(STAGING_DIR)/usr/lib/libpng16.so

# Disable external dependency downloads and use system libraries where possible
YABASANSHIRO_CONF_OPTS += -DYAB_USE_SYSTEM_ZLIB=ON
YABASANSHIRO_CONF_OPTS += -DYAB_USE_SYSTEM_LIBPNG=ON
YABASANSHIRO_CONF_OPTS += -DCMAKE_FIND_PACKAGE_PREFER_CONFIG=OFF
YABASANSHIRO_CONF_OPTS += -DYAB_DISABLE_EXTERNAL_DEPS=ON

# Standard buildroot cross-compilation flags
ifeq ($(BR2_aarch64),y)
    YABASANSHIRO_CONF_ENV += CFLAGS="$(YABASANSHIRO_CFLAGS) $(YABASANSHIRO_LTO_FLAGS) -O3 -std=c99"
    YABASANSHIRO_CONF_ENV += CXXFLAGS="$(YABASANSHIRO_CXXFLAGS) $(YABASANSHIRO_LTO_FLAGS) -O3 -std=c++17"
endif

# Use buildroot PKG_CONFIG_PATH
YABASANSHIRO_CONF_ENV += PKG_CONFIG_PATH="$(STAGING_DIR)/usr/lib/pkgconfig:$(STAGING_DIR)/usr/share/pkgconfig"

# Keep using the BR2 conditional behavior you had earlier for ARM vs PC
ifeq ($(BR2_arm)$(BR2_aarch64),y)
    YABASANSHIRO_CONF_OPTS += -DYAB_WANT_ARM7=ON
    YABASANSHIRO_CONF_OPTS += -DYAB_ASYNC_RENDERING=ON
    YABASANSHIRO_CONF_OPTS += -DYAB_WANT_DYNAREC_DEVMIYAX=ON
    # add build-time target flags (note: CMake/Cross toolchain will also apply TARGET_CFLAGS)
    YABASANSHIRO_CONF_OPTS += -DCMAKE_C_FLAGS="$(YABASANSHIRO_CFLAGS) $(YABASANSHIRO_TARGET_CFLAGS) $(YABASANSHIRO_LTO_FLAGS) -O3"
    YABASANSHIRO_CONF_OPTS += -DCMAKE_CXX_FLAGS="$(YABASANSHIRO_CXXFLAGS) $(YABASANSHIRO_LTO_FLAGS) -O3"
else ifeq ($(BR2_x86_64),y)
    YABASANSHIRO_CONF_OPTS += -DYAB_WANT_DYNAREC_DEVMIYAX=OFF
    YABASANSHIRO_CONF_OPTS += -DCMAKE_C_FLAGS="$(TARGET_CFLAGS) $(YABASANSHIRO_TARGET_CFLAGS) -D__PC__"
    YABASANSHIRO_CONF_OPTS += -DCMAKE_CXX_FLAGS="$(TARGET_CFLAGS) -D__PC__"
endif

# Use buildroot host tools
YABASANSHIRO_CONF_ENV += CMAKE_MAKE_PROGRAM="$(HOST_DIR)/usr/bin/make"
YABASANSHIRO_CONF_ENV += GIT_EXECUTABLE="$(HOST_DIR)/usr/bin/git"
YABASANSHIRO_CONF_ENV += BR2_VERSION="1"

# Set git hash for build
define YABASANSHIRO_GIT_HASH
	# Get git hash and patch config.h.in if it exists
	if [ -f $(@D)/yabause/src/config.h.in ]; then \
		sed -i 's/@GIT_SHA1@/$(shell echo $(YABASANSHIRO_VERSION) | cut -c1-7)/g' \
			$(@D)/yabause/src/config.h.in; \
	fi
endef

# Fix vidogl.c conditional compilation for Linux OpenGL ES
define YABASANSHIRO_FIX_VIDOGL_CONDITION
	sed -i 's/#if defined(HAVE_LIBGL) || defined(__ANDROID__) || defined(IOS) || defined(NX)/#if defined(HAVE_LIBGL) || defined(__ANDROID__) || defined(IOS) || defined(NX) || (defined(__linux__) \&\& defined(_OGLES3_))/' \
		$(@D)/yabause/src/vidogl.c
endef

# Add missing Musashi M68K disassembler callback functions
define YABASANSHIRO_ADD_MUSASHI_CALLBACKS
	echo '' >> $(@D)/yabause/src/m68kmusashi.c
	echo '/* Required disassembler callback functions for Musashi M68K emulator */' >> $(@D)/yabause/src/m68kmusashi.c
	echo 'unsigned int m68k_read_disassembler_8(unsigned int address)' >> $(@D)/yabause/src/m68kmusashi.c
	echo '{' >> $(@D)/yabause/src/m68kmusashi.c
	echo '   return rw_funcs.r_8 ? rw_funcs.r_8(address) : 0;' >> $(@D)/yabause/src/m68kmusashi.c
	echo '}' >> $(@D)/yabause/src/m68kmusashi.c
	echo '' >> $(@D)/yabause/src/m68kmusashi.c
	echo 'unsigned int m68k_read_disassembler_16(unsigned int address)' >> $(@D)/yabause/src/m68kmusashi.c
	echo '{' >> $(@D)/yabause/src/m68kmusashi.c
	echo '   return rw_funcs.r_16 ? rw_funcs.r_16(address) : 0;' >> $(@D)/yabause/src/m68kmusashi.c
	echo '}' >> $(@D)/yabause/src/m68kmusashi.c
	echo '' >> $(@D)/yabause/src/m68kmusashi.c
	echo 'unsigned int m68k_read_disassembler_32(unsigned int address)' >> $(@D)/yabause/src/m68kmusashi.c
	echo '{' >> $(@D)/yabause/src/m68kmusashi.c
	echo '   return (rw_funcs.r_16 ? (rw_funcs.r_16(address) << 16) | rw_funcs.r_16(address + 2) : 0);' >> $(@D)/yabause/src/m68kmusashi.c
	echo '}' >> $(@D)/yabause/src/m68kmusashi.c
endef

# Pre-configure hook to build host tools
define YABASANSHIRO_BUILD_HOST_TOOLS
	# Build bin2c host tool
	$(HOSTCC) $(HOST_CFLAGS) $(@D)/yabause/src/retro_arena/nanogui-sdl/resources/bin2c.c \
		-o $(@D)/yabause/bin2c_host

	# Build m68kmake host tool
	$(HOSTCC) $(HOST_CFLAGS) $(@D)/yabause/src/musashi/m68kmake.c \
		-o $(@D)/m68kmake_host

	# Patch CMakeLists to use host-built tools
	sed -i "s|COMMAND ./bin2c|COMMAND $(@D)/bin2c_host|" \
		$(@D)/yabause/src/retro_arena/nanogui-sdl/CMakeLists.txt
	sed -i "s|COMMAND m68kmake|COMMAND $(@D)/m68kmake_host|" \
		$(@D)/yabause/src/musashi/CMakeLists.txt
endef

# Post-install: install library and extra files; attempt to strip the main binary if present
define YABASANSHIRO_POST_PROCESS
	# install libyabause into target lib dir
	if [ -f $(@D)/yabause/src/libyabause.so ]; then \
		$(INSTALL) -m 0755 $(@D)/yabause/src/libyabause.so -D $(TARGET_DIR)/usr/lib/libyabause.so; \
	fi

	# evmapy config
	mkdir -p $(TARGET_DIR)/usr/share/evmapy
	cp -f $(BR2_EXTERNAL_KNULLI_PATH)/package/emulators/yabasanshiro/saturn.yabasanshiro.keys $(TARGET_DIR)/usr/share/evmapy

	# if the retro_arena binary exists in the build tree, copy + strip it into target bin
	if [ -f $(@D)/yabause/src/retro_arena/yabasanshiro ]; then \
		install -m 0755 $(@D)/yabause/src/retro_arena/yabasanshiro $(TARGET_DIR)/usr/bin/; \
		if [ -x "$(HOST_DIR)/bin/$(GNU_TARGET_NAME)-strip" ]; then \
			$(HOST_DIR)/bin/$(GNU_TARGET_NAME)-strip $(TARGET_DIR)/usr/bin/yabasanshiro || true; \
		fi; \
	fi
endef

YABASANSHIRO_PRE_CONFIGURE_HOOKS = YABASANSHIRO_GIT_HASH YABASANSHIRO_FIX_VIDOGL_CONDITION YABASANSHIRO_ADD_MUSASHI_CALLBACKS YABASANSHIRO_BUILD_HOST_TOOLS
YABASANSHIRO_POST_INSTALL_TARGET_HOOKS += YABASANSHIRO_POST_PROCESS

# Use cmake package infrastructure
$(eval $(cmake-package))
