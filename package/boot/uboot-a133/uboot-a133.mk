################################################################################
#
# uboot-a133
#
################################################################################

UBOOT_A133_VERSION = 1.0
UBOOT_A133_SOURCE = 
UBOOT_A133_SITE = 
UBOOT_A133_LICENSE = GPL-2.0
UBOOT_A133_DEPENDENCIES = host-dtc host-allwinner-utils

# List of supported A133 devices
UBOOT_A133_DEVICES = trimui-smart-pro trimui-brick powkiddy-v20 powkiddy-v90s magicx-zero-28 magicx-zero-40 xu20-v32

define UBOOT_A133_EXTRACT_CMDS
    # Copy all device configurations to build directory
    cp -r $(UBOOT_A133_PKGDIR)/* $(@D)/
endef

define UBOOT_A133_BUILD_CMDS
    # Build DTB and boot_package.fex for each device
    $(foreach device,$(UBOOT_A133_DEVICES), \
        if [ -d "$(@D)/$(device)" ]; then \
            echo "Building DTB for $(device)..."; \
            $(HOST_DIR)/bin/dtc -I dts -O dtb \
                -o $(@D)/$(device)/boot_package/dtb.bin \
                $(@D)/$(device)/boot_package/$(device).dts || exit 1; \
            echo "Building boot_package.fex for $(device)..."; \
            cd $(@D)/$(device)/boot_package/ && \
            $(HOST_DIR)/bin/dragonsecboot -pack boot_package.cfg || exit 1; \
        fi; \
    )
endef

define UBOOT_A133_INSTALL_IMAGES_CMDS
    # Create A133 boot packages directory
    mkdir -p $(BINARIES_DIR)/a133-boot-packages
    
    # Install boot_package.fex files for each device
    $(foreach device,$(UBOOT_A133_DEVICES), \
        if [ -f "$(@D)/$(device)/boot_package/boot_package.fex" ]; then \
            echo "Installing $(device) boot package..."; \
            cp $(@D)/$(device)/boot_package/boot_package.fex \
                $(BINARIES_DIR)/a133-boot-packages/$(device)_boot_package.fex; \
        fi; \
    )
    
    # Create a summary file
    echo "A133 Boot Packages:" > $(BINARIES_DIR)/a133-boot-packages/README.txt
    echo "==================" >> $(BINARIES_DIR)/a133-boot-packages/README.txt
    echo "" >> $(BINARIES_DIR)/a133-boot-packages/README.txt
    $(foreach device,$(UBOOT_A133_DEVICES), \
        if [ -f "$(BINARIES_DIR)/a133-boot-packages/$(device)_boot_package.fex" ]; then \
            echo "- $(device)_boot_package.fex" >> $(BINARIES_DIR)/a133-boot-packages/README.txt; \
        fi; \
    )
    
    echo "" >> $(BINARIES_DIR)/a133-boot-packages/README.txt
    echo "Generated on: $$(date)" >> $(BINARIES_DIR)/a133-boot-packages/README.txt
endef

# This package installs to images directory, not target
UBOOT_A133_INSTALL_TARGET = NO
UBOOT_A133_INSTALL_STAGING = NO
UBOOT_A133_INSTALL_IMAGES = YES

$(eval $(generic-package))
