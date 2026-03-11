#!/usr/bin/env bash
# build-mt7927.sh — Compile et installe le driver WiFi MediaTek MT7927 (MT6639)
# Variables attendues en entrée :
#   MT7927_VER  : version du package DKMS (ex: "2.4")
#   MT76_KVER   : version du tarball kernel.org (ex: "6.19.4")
set -euo pipefail

: "${MT7927_VER:?MT7927_VER non défini}"
: "${MT76_KVER:?MT76_KVER non défini}"

DKMSDIR="/usr/src/mediatek-mt7927-${MT7927_VER}"
KERNEL_VER=$(ls /usr/lib/modules/ | head -1)
REPO_URL="https://github.com/jetm/mediatek-mt7927-dkms.git"
TARBALL_URL="https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${MT76_KVER}.tar.xz"

# URL firmware ASUS (ROG Crosshair X870E Hero — contient les binaires MT6639)
ASUS_ZIP_URL="https://dlcdnta.asus.com/pub/ASUS/mb/08WIRELESS/DRV_WiFi_MTK_MT7925_MT7927_TP_W11_64_V5603998_20250709R.zip?model=ROG%20CROSSHAIR%20X870E%20HERO"
ASUS_TOKEN_URL="https://cdnta.asus.com/api/v1/TokenHQ?filePath=https:%2F%2Fdlcdnta.asus.com%2Fpub%2FASUS%2Fmb%2F08WIRELESS%2FDRV_WiFi_MTK_MT7925_MT7927_TP_W11_64_V5603998_20250709R.zip%3Fmodel%3DROG%2520CROSSHAIR%2520X870E%2520HERO&systemCode=rog"

echo "=== Build MT7927 ==="
echo "  Kernel   : ${KERNEL_VER}"
echo "  DKMS ver : ${MT7927_VER}"
echo "  MT76 src : kernel ${MT76_KVER}"

# ── 1. Dépendances ────────────────────────────────────────────────────────────
echo "--- Dépendances"
dnf5 -y install dkms git make gcc patch wget curl python3 bsdtar \
    "kernel-devel-${KERNEL_VER}"
dnf5 clean all

# ── 2. Sources ────────────────────────────────────────────────────────────────
echo "--- Téléchargement sources"
git clone "${REPO_URL}" /tmp/mediatek-mt7927-dkms

wget -q "${TARBALL_URL}" -O /tmp/linux-${MT76_KVER}.tar.xz

# ── 3. Extraction mt76 et bluetooth ──────────────────────────────────────────
echo "--- Extraction mt76"
mkdir -p /tmp/mt76
tar -xf /tmp/linux-${MT76_KVER}.tar.xz \
    --strip-components=6 \
    -C /tmp/mt76 \
    "linux-${MT76_KVER}/drivers/net/wireless/mediatek/mt76"

echo "--- Extraction bluetooth"
mkdir -p /tmp/bluetooth
tar -xf /tmp/linux-${MT76_KVER}.tar.xz \
    --strip-components=3 \
    -C /tmp/bluetooth \
    "linux-${MT76_KVER}/drivers/bluetooth"

# ── 4. Patches WiFi ───────────────────────────────────────────────────────────
echo "--- Application des patches WiFi"
cd /tmp/mt76
patch -p1 < /tmp/mediatek-mt7927-dkms/mt7902-wifi-6.19.patch
for p in /tmp/mediatek-mt7927-dkms/mt7927-wifi-*.patch; do
    echo "  Applying $(basename $p)..."
    patch -p1 < "$p"
done
echo "Patches WiFi appliqués"

# ── 5. Kbuild (fournis par le repo jetm) ─────────────────────────────────────
echo "--- Kbuild"
cp /tmp/mediatek-mt7927-dkms/mt76.Kbuild    /tmp/mt76/Kbuild
cp /tmp/mediatek-mt7927-dkms/mt7921.Kbuild  /tmp/mt76/mt7921/Kbuild
cp /tmp/mediatek-mt7927-dkms/mt7925.Kbuild  /tmp/mt76/mt7925/Kbuild

# ── 6. Assemblage tree DKMS ──────────────────────────────────────────────────
echo "--- Assemblage DKMS source tree"
install -d "${DKMSDIR}"

# Configuration DKMS
install -Dm644 /tmp/mediatek-mt7927-dkms/dkms.conf "${DKMSDIR}/dkms.conf"

# Patches (pour référence — pas appliqués par DKMS, déjà pré-appliqués)
install -Dm644 /tmp/mediatek-mt7927-dkms/mt6639-bt-6.19.patch \
    "${DKMSDIR}/patches/bt/mt6639-bt-6.19.patch"
install -dm755 "${DKMSDIR}/patches/wifi"
install -m644 /tmp/mediatek-mt7927-dkms/mt7902-wifi-6.19.patch \
    "${DKMSDIR}/patches/wifi/"
install -m644 /tmp/mediatek-mt7927-dkms/mt7927-wifi-*.patch \
    "${DKMSDIR}/patches/wifi/"

# Sources bluetooth
install -dm755 "${DKMSDIR}/drivers/bluetooth"
install -m644 \
    /tmp/bluetooth/btusb.c \
    /tmp/bluetooth/btmtk.c \
    /tmp/bluetooth/btmtk.h \
    /tmp/bluetooth/btbcm.c \
    /tmp/bluetooth/btbcm.h \
    /tmp/bluetooth/btintel.h \
    /tmp/bluetooth/btrtl.h \
    "${DKMSDIR}/drivers/bluetooth/"
install -m644 /tmp/mediatek-mt7927-dkms/bluetooth.Makefile \
    "${DKMSDIR}/drivers/bluetooth/Makefile"

# Sources mt76 (patchées)
install -dm755 "${DKMSDIR}/mt76/mt7921" "${DKMSDIR}/mt76/mt7925"
install -m644 /tmp/mt76/*.c /tmp/mt76/*.h "${DKMSDIR}/mt76/"
install -m644 /tmp/mt76/Kbuild            "${DKMSDIR}/mt76/"
install -m644 /tmp/mt76/mt7921/*.c /tmp/mt76/mt7921/*.h "${DKMSDIR}/mt76/mt7921/"
install -m644 /tmp/mt76/mt7921/Kbuild                   "${DKMSDIR}/mt76/mt7921/"
install -m644 /tmp/mt76/mt7925/*.c /tmp/mt76/mt7925/*.h "${DKMSDIR}/mt76/mt7925/"
install -m644 /tmp/mt76/mt7925/Kbuild                   "${DKMSDIR}/mt76/mt7925/"

echo "Tree DKMS assemblé"

# ── 7. Header manquant (airoha_offload.h) ────────────────────────────────────
echo "--- Injection header airoha"
tar -xf /tmp/linux-${MT76_KVER}.tar.xz \
    "linux-${MT76_KVER}/include/linux/soc/airoha/airoha_offload.h"
mkdir -p "/usr/src/kernels/${KERNEL_VER}/include/linux/soc/airoha/"
cp "linux-${MT76_KVER}/include/linux/soc/airoha/airoha_offload.h" \
    "/usr/src/kernels/${KERNEL_VER}/include/linux/soc/airoha/"
rm -rf "linux-${MT76_KVER}"

# ── 8. Firmware ───────────────────────────────────────────────────────────────
echo "--- Téléchargement firmware ASUS"
JSON=$(curl -sf "${ASUS_TOKEN_URL}" -X POST -H 'Origin: https://rog.asus.com')
EXPIRES=$(echo "$JSON" | grep -oP '"expires":"\K[^"]+')
SIG=$(echo "$JSON"     | grep -oP '"signature":"\K[^"]+')
KID=$(echo "$JSON"     | grep -oP '"keyPairId":"\K[^"]+')

wget -q "${ASUS_ZIP_URL}&Signature=${SIG}&Expires=${EXPIRES}&Key-Pair-Id=${KID}" \
    -O /tmp/asus-mt7927.zip

bsdtar -xf /tmp/asus-mt7927.zip -C /tmp mtkwlan.dat
python3 /tmp/mediatek-mt7927-dkms/extract_firmware.py /tmp/mtkwlan.dat /tmp/firmware

install -Dm644 /tmp/firmware/BT_RAM_CODE_MT6639_2_1_hdr.bin \
    /usr/lib/firmware/mediatek/mt6639/BT_RAM_CODE_MT6639_2_1_hdr.bin
install -Dm644 /tmp/firmware/WIFI_MT6639_PATCH_MCU_2_1_hdr.bin \
    /usr/lib/firmware/mediatek/mt7927/WIFI_MT6639_PATCH_MCU_2_1_hdr.bin
install -Dm644 /tmp/firmware/WIFI_RAM_CODE_MT6639_2_1.bin \
    /usr/lib/firmware/mediatek/mt7927/WIFI_RAM_CODE_MT6639_2_1.bin
echo "Firmware installé"

# ── 9. Build DKMS ─────────────────────────────────────────────────────────────
echo "--- DKMS build"
dkms add    -m mediatek-mt7927 -v "${MT7927_VER}"
dkms build  -m mediatek-mt7927 -v "${MT7927_VER}" -k "${KERNEL_VER}" \
    || (cat "/var/lib/dkms/mediatek-mt7927/${MT7927_VER}/build/make.log" && exit 1)
dkms install --force -m mediatek-mt7927 -v "${MT7927_VER}" -k "${KERNEL_VER}"

# ── 10. Vérification ──────────────────────────────────────────────────────────
echo "--- Vérification modules"
find "/usr/lib/modules/${KERNEL_VER}/extra/" -name "*.ko*" | sort
test -f "/usr/lib/modules/${KERNEL_VER}/extra/mt76.ko.xz" \
    || (echo "ERREUR: mt76.ko.xz manquant!" && exit 1)
test -f "/usr/lib/modules/${KERNEL_VER}/extra/mt7925e.ko.xz" \
    || (echo "ERREUR: mt7925e.ko.xz manquant!" && exit 1)
echo "OK: modules présents"

# ── 11. Configuration chargement ─────────────────────────────────────────────
echo "--- Configuration modprobe / dracut"
printf 'install mt7925e modprobe --ignore-install mt7925e\ninstall mt76 modprobe --ignore-install mt76\n' \
    > /etc/modprobe.d/mt7927-override.conf

printf 'add_drivers+=" mt76 mt7925e mt76_connac_lib "\n' \
    > /etc/dracut.conf.d/mt7927.conf
dracut --force --kver "${KERNEL_VER}"

echo 'mt7925e' > /etc/modules-load.d/mt7927.conf

# ── 12. Nettoyage ─────────────────────────────────────────────────────────────
echo "--- Nettoyage"
rm -rf /tmp/mediatek-mt7927-dkms /tmp/mt76 /tmp/bluetooth \
       /tmp/linux-*.tar.xz /tmp/asus-mt7927.zip /tmp/firmware

echo "=== MT7927 installé avec succès ==="
