#!/bin/bash

ARCHS="rk3128 rk3326 rk3566 rk3576 a133 h700 r16 sm6115 smgen t618"

BR_DIR=$1
KNULLI_BINARIES_DIR=$2
if ! test -d "${BR_DIR}"
then
    echo "${0} <BR_DIR>" >&2
    exit 1
fi

CORES_PKGDIR="${BR2_EXTERNAL_KNULLI_PATH}/package/cores/libretro-super"

# create temporary directory
TMP_DIR="/tmp/br_systemreport_${$}"
mkdir -p "${TMP_DIR}" || exit 1

# create configs files
for ARCH in ${ARCHS}
do
    echo "generating .config for ${ARCH}" >&2
    TMP_CONFIG="${TMP_DIR}/configs_tmp/${ARCH}"
    TMP_CONFIGS="${TMP_DIR}/configs"
    mkdir -p "${TMP_CONFIG}" "${TMP_CONFIGS}" || exit 1

    # generate the defconfig
    "${BR2_EXTERNAL_KNULLI_PATH}/configs/createDefconfig.sh" "${BR2_EXTERNAL_KNULLI_PATH}/configs/knulli-${ARCH}"

    (make O="${TMP_CONFIG}" -C ${BR_DIR} BR2_EXTERNAL="${BR2_EXTERNAL_KNULLI_PATH}" "knulli-${ARCH}_defconfig" > /dev/null) || exit 1
    cp "${TMP_CONFIG}/.config" "${TMP_CONFIGS}/config_${ARCH}" || exit 1

    # Cores and standalone emulators come from per-ABI drops, so a board that
    # uses them carries none of the BR2_PACKAGE_LIBRETRO_*/emulator symbols
    # es_systems.yml gates on.  Append the same fragments knulli-es-system
    # merges at image build; without them everything from a drop reads as
    # disabled, and a board whose default core lives in the drop aborts the
    # report as soon as any in-tree emulator offers the same system.
    PROFILE=$(awk '$1 == "PROFILE" { print $2; exit }' \
        "${CORES_PKGDIR}/overlay/devices/${ARCH}.device" 2>/dev/null)
    EXCLUDE_CORES=$(awk '$1 == "EXCLUDE_CORE" { printf "%s ", $2 }' \
        "${CORES_PKGDIR}/overlay/devices/${ARCH}.device" 2>/dev/null)
    EXCLUDE_EMULATORS=$(awk '$1 == "EXCLUDE_EMULATOR" { printf "%s ", $2 }' \
        "${CORES_PKGDIR}/overlay/devices/${ARCH}.device" 2>/dev/null)
    CORES_DROP="${BR2_EXTERNAL_KNULLI_PATH}/cores-cache/drop/${PROFILE}"

    # The emulators drop is keyed on the profile AND the GPU, mali unsuffixed.
    GPU=$(awk '$1 == "GPU" { print $2; exit }' \
        "${CORES_PKGDIR}/overlay/devices/${ARCH}.device" 2>/dev/null)
    EMUS_KEY="${PROFILE}"
    test "${GPU}" = "mali" -o -z "${GPU}" || EMUS_KEY="${PROFILE}-${GPU}"
    EMUS_DROP="${BR2_EXTERNAL_KNULLI_PATH}/emulators-cache/drop/${EMUS_KEY}"

    if grep -q '^BR2_PACKAGE_KNULLI_EXTERNAL_LIBRETRO_CORES=y' "${TMP_CONFIGS}/config_${ARCH}"
    then
        if test -d "${CORES_DROP}/cores"
        then
            "${CORES_PKGDIR}/gen-es-config.sh" "${CORES_DROP}" \
                "${CORES_PKGDIR}/cores.symbols" \
                "${TMP_CONFIG}/libretro-cores.config" \
                "${TMP_CONFIG}/libretro-cores.list" \
                "${EXCLUDE_CORES}" >&2 || exit 1
            cat "${TMP_CONFIG}/libretro-cores.config" >> "${TMP_CONFIGS}/config_${ARCH}"
        else
            # No drop for this ABI in the cache: nothing here knows which cores
            # the board would ship, so report it as absent rather than as a
            # board with no libretro support at all.
            echo "  ${ARCH}: no cores drop for profile ${PROFILE:-?} -- excluded from the report" >&2
            rm -f "${TMP_CONFIGS}/config_${ARCH}"
            continue
        fi
    fi

    if grep -q '^BR2_PACKAGE_KNULLI_EXTERNAL_EMULATORS=y' "${TMP_CONFIGS}/config_${ARCH}" &&
       test -f "${EMUS_DROP}/emulators.config"
    then
        EMUS_FRAGMENT="${EMUS_DROP}/emulators.config"
        if test -n "${EXCLUDE_EMULATORS}"
        then
            for SYM in ${EXCLUDE_EMULATORS}
            do
                printf '^BR2_PACKAGE_%s=y$\n' "${SYM}"
            done > "${TMP_CONFIG}/emulators.exclude"
            grep -v -f "${TMP_CONFIG}/emulators.exclude" "${EMUS_FRAGMENT}" \
                > "${TMP_CONFIG}/emulators.config"
            EMUS_FRAGMENT="${TMP_CONFIG}/emulators.config"
        fi
        cat "${EMUS_FRAGMENT}" >> "${TMP_CONFIGS}/config_${ARCH}"
    fi
done

# reporting
ES_YML="${BR2_EXTERNAL_KNULLI_PATH}/package/emulationstation/knulli-es-system/es_systems.yml"
EXP_YML="${BR2_EXTERNAL_KNULLI_PATH}/package/emulationstation/knulli-es-system/systems-explanations.yml"
PYGEN="${BR2_EXTERNAL_KNULLI_PATH}/package/emulationstation/knulli-es-system/knulli-report-system.py"
HTML_GEN="${BR2_EXTERNAL_KNULLI_PATH}/package/emulationstation/knulli-es-system/knulli_systemsReport.html"
DEFAULTSDIR="${BR2_EXTERNAL_KNULLI_PATH}/package/system/knulli-configgen/configs"
mkdir -p "${KNULLI_BINARIES_DIR}" || exit 1
echo python "${PYGEN}" "${ES_YML}" "${EXP_YML}" "${DEFAULTSDIR}" "${TMP_CONFIGS}"
python "${PYGEN}" "${ES_YML}" "${EXP_YML}" "${DEFAULTSDIR}" "${TMP_CONFIGS}" > "${KNULLI_BINARIES_DIR}/knulli_systemsReport.json" || exit 1
cp "${HTML_GEN}" "${KNULLI_BINARIES_DIR}" || exit 1

rm -rf "${TMP_DIR}"
exit 0
