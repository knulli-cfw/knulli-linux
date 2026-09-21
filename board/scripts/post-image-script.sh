#!/bin/bash -e

# Enable for debug
# set -x

# PWD = source dir
# BASE_DIR = build dir
# BUILD_DIR = base dir/build
# HOST_DIR = base dir/host
# BINARIES_DIR = images dir
# TARGET_DIR = target dir

##### constants ################
KNULLI_BINARIES_DIR="${BINARIES_DIR}/knulli"
GENIMAGE_TMP="${BUILD_DIR}/genimage.tmp"
RELEASES_DIR="${BASE_DIR}/releases"
UPDATES_DIR="${BASE_DIR}/updates"
################################

##### find images to build #####
KNULLI_TARGET=$(grep -E "^BR2_PACKAGE_BATOCERA_TARGET_[A-Z_0-9]*=y$" "${BR2_CONFIG}" | grep -vE "_ANY=" | grep -vE "_GLES[0-9]*=" | sed -e s+'^BR2_PACKAGE_BATOCERA_TARGET_\([A-Z_0-9]*\)=y$'+'\1'+)
KNULLI_LOWER_TARGET=$(echo "${KNULLI_TARGET}" | tr '[:upper:]' '[:lower:]')
KNULLI_IMAGES_TARGETS=$(grep -E "^BR2_TARGET_KNULLI_IMAGES[ ]*=[ ]*\".*\"[ ]*$" "${BR2_CONFIG}" | sed -e s+"^BR2_TARGET_KNULLI_IMAGES[ ]*=[ ]*\"\(.*\)\"[ ]*$"+"\1"+)
if test -z "${KNULLI_IMAGES_TARGETS}"
then
    echo "no BR2_TARGET_KNULLI_IMAGES defined." >&2
    exit 1
fi
################################

#### common parent dir to al images #
if echo "${KNULLI_IMAGES_TARGETS}" | grep -qE '^[^ ]*$'
then
    # single board directory
    IMGMODE=single
else
    # when there are several one, the first one is the common directory where to find the create-boot-script.sh directory
    IMGMODE=multi
fi

#### clean the (previous if exists) target directory ###
if test -d "${KNULLI_BINARIES_DIR}"
then
    rm -rf "${KNULLI_BINARIES_DIR}" || exit 1
fi
mkdir -p "${KNULLI_BINARIES_DIR}/images" || exit 1

##### build images #############
#SUFFIXVERSION=$(cat "${TARGET_DIR}/usr/share/knulli/knulli.version" | sed -e s+'^\([0-9\.]*\).*$'+'\1'+) # xx.yy version
SUFFIXVERSION=$(awk '{if ($1 ~ /^[0-9\.]+$/) print $1; else print $1}' "${TARGET_DIR}/usr/share/knulli/knulli.version") # Handle numeric and codename strings versions

SUFFIXDATE=$(date +%Y%m%d)

# the rootfs is the same for every image: hash it once for generate_signature.sh
export KNULLI_ROOTFS_MD5=$(md5sum "${BINARIES_DIR}/rootfs.squashfs" | cut -d' ' -f1)

#### fast multi-image mode ######
# Every image of these targets carries the same rootfs and the same boot.vfat /
# userdata.ext4 definitions; they only differ in a few small files inside the
# boot.vfat and in the raw partitions of the knulli.img layout.  So the big
# boot.vfat (holding the rootfs) and userdata.ext4 are built once, and each
# image then gets a copy of that boot.vfat with its own small files added,
# which genimage only has to assemble into knulli.img.
# A board whose genimage.cfg defines boot.vfat/userdata.ext4 differently from
# the first board is built the normal way.
KNULLI_FAST_IMAGE_TARGETS="h700"

# genimage.cfg up to the knulli.img definition (boot.vfat and userdata.ext4)
genimage_common_part() {
    sed -n '/^image knulli\.img/q;p' "$1"
}

FASTIMG=no
if test "${IMGMODE}" = "multi" && echo " ${KNULLI_FAST_IMAGE_TARGETS} " | grep -q " ${KNULLI_LOWER_TARGET} " && ! grep -qE "^BR2_TARGET_SYSLINUX=y$" "${BR2_CONFIG}"
then
    FASTIMG=yes
    COMMONDIR="${KNULLI_BINARIES_DIR}/common"
    COMMONCFG="${BR2_EXTERNAL_KNULLI_PATH}/board/$(echo ${KNULLI_IMAGES_TARGETS} | cut -d' ' -f1)/genimage.cfg"
    echo "creating the boot.vfat and userdata.ext4 shared by all images" >&2
    mkdir -p "${COMMONDIR}/boot/boot" "${COMMONDIR}/emptyroot" || exit 1
    ln -f "${BINARIES_DIR}/rootfs.squashfs" "${COMMONDIR}/boot/boot/knulli" 2>/dev/null || cp "${BINARIES_DIR}/rootfs.squashfs" "${COMMONDIR}/boot/boot/knulli" || exit 1
    {
        genimage_common_part "${COMMONCFG}" | sed -n '1,/@files/p' | sed '/@files/d'
        echo '                        file "boot/knulli" { image = "boot/knulli" }'
        genimage_common_part "${COMMONCFG}" | sed -n '/@files/,$p' | sed '1d'
    } > "${COMMONDIR}/genimage.cfg" || exit 1
    rm -rf "${GENIMAGE_TMP}" || exit 1
    "${HOST_DIR}/bin/genimage" --rootpath="${TARGET_DIR}" --inputpath="${COMMONDIR}/boot" --outputpath="${COMMONDIR}" --config="${COMMONDIR}/genimage.cfg" --tmppath="${GENIMAGE_TMP}" || exit 1
fi

#### build the images ###########
for KNULLI_PATHSUBTARGET in ${KNULLI_IMAGES_TARGETS}
do
    KNULLI_SUBTARGET=$(basename "${KNULLI_PATHSUBTARGET}")

    #### prepare the boot dir ######
    BOOTNAMEDDIR="${KNULLI_BINARIES_DIR}/boot_${KNULLI_SUBTARGET}"
    rm -rf "${BOOTNAMEDDIR}" || exit 1 # remove in case or rerun
    KNULLI_POST_IMAGE_SCRIPT="${BR2_EXTERNAL_KNULLI_PATH}/board/${KNULLI_PATHSUBTARGET}/create-boot-script.sh"
    bash "${KNULLI_POST_IMAGE_SCRIPT}" "${HOST_DIR}" "${BR2_EXTERNAL_KNULLI_PATH}/board/${KNULLI_PATHSUBTARGET}" "${BUILD_DIR}" "${BINARIES_DIR}" "${TARGET_DIR}" "${KNULLI_BINARIES_DIR}" || exit 1
    # add some common files
    cp     "${BINARIES_DIR}/knulli-boot.conf" "${KNULLI_BINARIES_DIR}/boot/" || exit 1
    echo   "${KNULLI_SUBTARGET}" > "${KNULLI_BINARIES_DIR}/boot/boot/knulli.board" || exit 1

    #### create the update signatures (after boot dir is assembled so we hash the actual on-device files) #####
    KNULLI_SIGNATURES_SCRIPT="${BR2_EXTERNAL_KNULLI_PATH}/board/scripts/generate_signature.sh"
    bash "${KNULLI_SIGNATURES_SCRIPT}" "${BR2_EXTERNAL_KNULLI_PATH}/board/${KNULLI_PATHSUBTARGET}" "${BINARIES_DIR}" "${KNULLI_BINARIES_DIR}/boot" || exit 1
    # copy firmware.sig into the boot dir so it is included in the archive and the final image
    cp "${BINARIES_DIR}/firmware.sig" "${KNULLI_BINARIES_DIR}/boot/boot/firmware.sig" || exit 1

    #### boot.tar.gz ###############
    echo "creating images/${KNULLI_SUBTARGET}/boot.tar.gxz"
    mkdir -p "${KNULLI_BINARIES_DIR}/images/${KNULLI_SUBTARGET}" || exit 1
    (cd "${KNULLI_BINARIES_DIR}/boot" && tar -cf - * | pigz -9 > "${KNULLI_BINARIES_DIR}/images/${KNULLI_SUBTARGET}/knulli-${KNULLI_LOWER_TARGET}-${KNULLI_SUBTARGET}-${SUFFIXVERSION}-${SUFFIXDATE}_boot.tar.gz") || exit 1

    # rename the squashfs : the .update is the version that will be renamed at boot to replace the old version
    mv "${KNULLI_BINARIES_DIR}/boot/boot/knulli.update" "${KNULLI_BINARIES_DIR}/boot/boot/knulli" || exit 1

    # create *.img
    if [ "${KNULLI_LOWER_TARGET}" = "${KNULLI_SUBTARGET}" ]; then
        KNULLIIMG="${KNULLI_BINARIES_DIR}/images/${KNULLI_SUBTARGET}/knulli-${KNULLI_SUBTARGET}-${SUFFIXVERSION}-${SUFFIXDATE}.img"
    else
        KNULLIIMG="${KNULLI_BINARIES_DIR}/images/${KNULLI_SUBTARGET}/knulli-${KNULLI_LOWER_TARGET}-${KNULLI_SUBTARGET}-${SUFFIXVERSION}-${SUFFIXDATE}.img"
    fi
    echo "creating images/${KNULLI_SUBTARGET}/"$(basename "${KNULLIIMG}")"..." >&2
    rm -rf "${GENIMAGE_TMP}" || exit 1
    GENIMAGEDIR="${BR2_EXTERNAL_KNULLI_PATH}/board/${KNULLI_PATHSUBTARGET}"
    GENIMAGEFILE="${GENIMAGEDIR}/genimage.cfg"

    if test "${FASTIMG}" = "yes" && test "$(genimage_common_part "${GENIMAGEFILE}")" = "$(genimage_common_part "${COMMONCFG}")"
    then
        # the shared boot.vfat already holds boot/knulli: add the other files of this board
        cp --sparse=always "${COMMONDIR}/boot.vfat" "${KNULLI_BINARIES_DIR}/boot.vfat" || exit 1
        # mmd fails when it skips an existing directory (e.g. boot); a directory
        # really missing makes the mcopy below fail
        (cd "${KNULLI_BINARIES_DIR}/boot" && find . -mindepth 1 -type d | sort) | while read -r D
        do
            MTOOLS_SKIP_CHECK=1 "${HOST_DIR}/bin/mmd" -D s -i "${KNULLI_BINARIES_DIR}/boot.vfat" "::${D#./}" || true
        done
        (cd "${KNULLI_BINARIES_DIR}/boot" && find . -type f ! -path ./boot/knulli | sort) | while read -r F
        do
            MTOOLS_SKIP_CHECK=1 "${HOST_DIR}/bin/mcopy" -p -o -i "${KNULLI_BINARIES_DIR}/boot.vfat" "${KNULLI_BINARIES_DIR}/boot/${F#./}" "::${F#./}" || exit 1
        done || exit 1

        # only assemble knulli.img, from this boot.vfat and the shared userdata.ext4
        sed -n '/^image knulli\.img/,$p' "${GENIMAGEFILE}" | sed -e 's+image = "boot.vfat"+image = "'"${KNULLI_BINARIES_DIR}/boot.vfat"'"+' \
                                                               -e 's+image = "userdata.ext4"+image = "'"${COMMONDIR}/userdata.ext4"'"+' > "${KNULLI_BINARIES_DIR}/genimage.cfg" || exit 1
        "${HOST_DIR}/bin/genimage" --rootpath="${COMMONDIR}/emptyroot" --inputpath="${KNULLI_BINARIES_DIR}/boot" --outputpath="${KNULLI_BINARIES_DIR}" --config="${KNULLI_BINARIES_DIR}/genimage.cfg" --tmppath="${GENIMAGE_TMP}" || exit 1
    else
        # Generate the genimage config with proper file entries
        {
            # Copy everything before @files
            sed -n '1,/@files/p' "${GENIMAGEFILE}" | sed '/@files/d'
            
            # Generate file entries
            find "${KNULLI_BINARIES_DIR}/boot" -type f | sed -e "s|^${KNULLI_BINARIES_DIR}/boot/\(.*\)$|                        file \"\1\" { image = \"\1\" }|"
            
            # Copy everything after @files
            sed -n '/@files/,$p' "${GENIMAGEFILE}" | sed '1d'
            
        } > "${KNULLI_BINARIES_DIR}/genimage.cfg" || exit 1

        # install syslinux
        if grep -qE "^BR2_TARGET_SYSLINUX=y$" "${BR2_CONFIG}"
        then
            GENIMAGEBOOTFILE="${GENIMAGEDIR}/genimage-boot.cfg"
            echo "installing syslinux" >&2
            cat "${GENIMAGEBOOTFILE}" | sed -e s+'@files'+"${FILES}"+ | tr '@' '\n' > "${KNULLI_BINARIES_DIR}/genimage-boot.cfg" || exit 1
            genimage --rootpath="${TARGET_DIR}" --inputpath="${KNULLI_BINARIES_DIR}/boot" --outputpath="${KNULLI_BINARIES_DIR}" --config="${KNULLI_BINARIES_DIR}/genimage-boot.cfg" --tmppath="${GENIMAGE_TMP}" || exit 1
            "${HOST_DIR}/bin/syslinux" -i "${KNULLI_BINARIES_DIR}/boot.vfat" -d "/boot/syslinux" || exit 1
            # remove genimage temp path as sometimes genimage v14 fails to start
            rm -rf ${GENIMAGE_TMP}
            mkdir ${GENIMAGE_TMP}
        fi

        # Generate knulli.img
        "${HOST_DIR}/bin/genimage" --rootpath="${TARGET_DIR}" --inputpath="${KNULLI_BINARIES_DIR}/boot" --outputpath="${KNULLI_BINARIES_DIR}" --config="${KNULLI_BINARIES_DIR}/genimage.cfg" --tmppath="${GENIMAGE_TMP}" || exit 1
    fi

    # Remove temporary images
    rm -f "${KNULLI_BINARIES_DIR}/boot.vfat" || exit 1
    rm -f "${KNULLI_BINARIES_DIR}/userdata.ext4" || exit 1
    mv "${KNULLI_BINARIES_DIR}/knulli.img" "${KNULLIIMG}" || exit 1
    pigz "${KNULLIIMG}" || exit 1

    # rename the boot to boot_arch
    mv "${KNULLI_BINARIES_DIR}/boot" "${BOOTNAMEDDIR}" || exit 1

    # copy the version file needed for version check
    cp "${TARGET_DIR}/usr/share/knulli/knulli.version" "${KNULLI_BINARIES_DIR}/images/${KNULLI_SUBTARGET}" || exit 1

    # copy the update signature files
    cp "${BINARIES_DIR}/firmware.sig" "${KNULLI_BINARIES_DIR}/images/${KNULLI_SUBTARGET}" || exit 1
done
if test "${FASTIMG}" = "yes"
then
    rm -rf "${COMMONDIR}" || exit 1
fi

#### Create the rootfs patches ##########
# Only process if there are previous rootfs files to diff against
if ls "${RELEASES_DIR}/"*"_rootfs.squashfs" 1> /dev/null 2>&1; then
    # Calculate the current rootfs.squashfs md5sum
    CURRENT_ROOTFS_MD5SUM="${KNULLI_ROOTFS_MD5}"
    for ROOTFS_TARGET in "${RELEASES_DIR}/"*"_rootfs.squashfs"
    do
        # ROOTFS_TARGET is in the form of md5sum_rootfs.squashfs. We need to extract the md5sum into a variable
        ROOTFS_MD5SUM=$(basename "${ROOTFS_TARGET}" | sed -e s+'^\([0-9a-f]*\)_rootfs.squashfs$'+'\1'+)
        echo "Creating delta from ${ROOTFS_TARGET} (source) to current rootfs.squashfs (target) with source md5sum ${ROOTFS_MD5SUM}"
        # Create patches directory if it does not exist
        mkdir -p "${UPDATES_DIR}/patches" || exit 1
        echo "Creating patch file ${UPDATES_DIR}/patches/${ROOTFS_MD5SUM}_to_${CURRENT_ROOTFS_MD5SUM}.patch"
        # create the delta.xdelta3 patch that can be applied to the old rootfs to get the new rootfs
        xdelta3 -e -S none -s "${ROOTFS_TARGET}" "${BINARIES_DIR}/rootfs.squashfs" "${UPDATES_DIR}/patches/${ROOTFS_MD5SUM}_to_${CURRENT_ROOTFS_MD5SUM}.patch" || exit 1
    done
else
    echo "No previous rootfs files found in ${RELEASES_DIR} - skipping delta creation"
fi

#### md5 and sha256 #######################
# hash all files in parallel (several GB each), then collect the sums in order
CKSFILES=("${KNULLI_BINARIES_DIR}/images/"*"/knulli-"*"_boot.tar.gz" "${KNULLI_BINARIES_DIR}/images/"*"/knulli-"*".img.gz")
printf '%s\0' "${CKSFILES[@]}" | xargs -0 -n 1 -P "$(nproc)" sh -c 'md5sum "$1" | cut -d" " -f1 > "$1.md5" && sha256sum "$1" | cut -d" " -f1 > "$1.sha256"' sh || exit 1
for FILE in "${CKSFILES[@]}"
do
    echo "creating ${FILE}.md5"
    echo "$(cat "${FILE}.md5")  $(basename "${FILE}")" >> "${KNULLI_BINARIES_DIR}/MD5SUMS"
    echo "creating ${FILE}.sha256"
    echo "$(cat "${FILE}.sha256")  $(basename "${FILE}")" >> "${KNULLI_BINARIES_DIR}/SHA256SUMS"
done

#### update the target dir with some information files
cp "${TARGET_DIR}/usr/share/knulli/knulli.version" "${KNULLI_BINARIES_DIR}" || exit 1
"${BR2_EXTERNAL_KNULLI_PATH}"/scripts/linux/systemsReport.sh "${PWD}" "${KNULLI_BINARIES_DIR}" || exit 1
