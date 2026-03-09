# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY build_files /

# Base Image
FROM ghcr.io/ublue-os/bazzite-deck-nvidia:stable

### MODIFICATIONS
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh

# ── Driver MT7927 ─────────────────────────────────────────────────────────────
ARG MT7927_VER="2.4"
ARG MT76_KVER="6.19.4"

RUN KERNEL_VER=$(ls /usr/lib/modules/ | head -1) \
    && echo "Kernel trouvé: ${KERNEL_VER}" \
    && dnf5 -y install dkms git make gcc patch wget curl python3 bsdtar \
         kernel-devel-${KERNEL_VER} \
    && dnf5 clean all

RUN wget -q https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${MT76_KVER}.tar.xz \
      -O /tmp/linux-${MT76_KVER}.tar.xz

ARG CACHE_BUST=1
RUN git clone https://github.com/jetm/mediatek-mt7927-dkms.git \
      /tmp/mediatek-mt7927-dkms

RUN mkdir -p /tmp/mt76 \
    && tar -xf /tmp/linux-${MT76_KVER}.tar.xz \
         --strip-components=6 \
         -C /tmp/mt76 \
         "linux-${MT76_KVER}/drivers/net/wireless/mediatek/mt76" \
    && echo "mt76 extrait:" && ls /tmp/mt76/ | head -5

RUN mkdir -p /tmp/bluetooth \
    && tar -xf /tmp/linux-${MT76_KVER}.tar.xz \
         --strip-components=3 \
         -C /tmp/bluetooth \
         "linux-${MT76_KVER}/drivers/bluetooth" \
    && echo "bluetooth extrait:" && ls /tmp/bluetooth/ | head -5

RUN cd /tmp/mt76 \
    && patch -p1 < /tmp/mediatek-mt7927-dkms/mt7902-wifi-6.19.patch \
    && for p in /tmp/mediatek-mt7927-dkms/mt7927-wifi-*.patch; do \
         echo "Applying $p..."; \
         patch -p1 < "$p"; \
       done \
    && echo "Patches wifi appliqués"

# Kbuild files fournis directement par le repo jetm
RUN cp /tmp/mediatek-mt7927-dkms/mt76.Kbuild    /tmp/mt76/Kbuild \
    && cp /tmp/mediatek-mt7927-dkms/mt7921.Kbuild /tmp/mt76/mt7921/Kbuild \
    && cp /tmp/mediatek-mt7927-dkms/mt7925.Kbuild /tmp/mt76/mt7925/Kbuild

RUN DKMSDIR="/usr/src/mediatek-mt7927-${MT7927_VER}" \
    && install -d ${DKMSDIR} \
    && install -Dm644 /tmp/mediatek-mt7927-dkms/dkms.conf                    ${DKMSDIR}/dkms.conf \
    && install -Dm644 /tmp/mediatek-mt7927-dkms/mt6639-bt-6.19.patch         ${DKMSDIR}/patches/bt/mt6639-bt-6.19.patch \
    && install -dm755 ${DKMSDIR}/patches/wifi \
    && install -m644 /tmp/mediatek-mt7927-dkms/mt7902-wifi-6.19.patch        ${DKMSDIR}/patches/wifi/ \
    && install -m644 /tmp/mediatek-mt7927-dkms/mt7927-wifi-*.patch           ${DKMSDIR}/patches/wifi/ \
    && install -dm755 ${DKMSDIR}/drivers/bluetooth \
    && install -m644 /tmp/bluetooth/btusb.c  /tmp/bluetooth/btmtk.c \
                     /tmp/bluetooth/btmtk.h  /tmp/bluetooth/btbcm.c \
                     /tmp/bluetooth/btbcm.h  /tmp/bluetooth/btintel.h \
                     /tmp/bluetooth/btrtl.h  ${DKMSDIR}/drivers/bluetooth/ \
    & install -m644 /tmp/mediatek-mt7927-dkms/bluetooth.Makefile \
                     ${DKMSDIR}/drivers/bluetooth/Makefile \
    && install -dm755 ${DKMSDIR}/mt76/mt7921 ${DKMSDIR}/mt76/mt7925 \
    && install -m644 /tmp/mt76/*.c /tmp/mt76/*.h ${DKMSDIR}/mt76/ \
    && install -m644 /tmp/mt76/Kbuild             ${DKMSDIR}/mt76/ \
    && install -m644 /tmp/mt76/mt7921/*.c /tmp/mt76/mt7921/*.h ${DKMSDIR}/mt76/mt7921/ \
    && install -m644 /tmp/mt76/mt7921/Kbuild                   ${DKMSDIR}/mt76/mt7921/ \
    && install -m644 /tmp/mt76/mt7925/*.c /tmp/mt76/mt7925/*.h ${DKMSDIR}/mt76/mt7925/ \
    && install -m644 /tmp/mt76/mt7925/Kbuild                   ${DKMSDIR}/mt76/mt7925/ \
    && echo "Tree DKMS assemblé"

RUN TOKEN_URL="https://cdnta.asus.com/api/v1/TokenHQ?filePath=https:%2F%2Fdlcdnta.asus.com%2Fpub%2FASUS%2Fmb%2F08WIRELESS%2FDRV_WiFi_MTK_MT7925_MT7927_TP_W11_64_V5603998_20250709R.zip%3Fmodel%3DROG%2520CROSSHAIR%2520X870E%2520HERO&systemCode=rog" \
    && JSON=$(curl -sf "${TOKEN_URL}" -X POST -H 'Origin: https://rog.asus.com') \
    && EXPIRES=$(echo $JSON | grep -oP '"expires":"\K[^"]+') \
    && SIG=$(echo $JSON | grep -oP '"signature":"\K[^"]+') \
    && KID=$(echo $JSON | grep -oP '"keyPairId":"\K[^"]+') \
    && wget -q "https://dlcdnta.asus.com/pub/ASUS/mb/08WIRELESS/DRV_WiFi_MTK_MT7925_MT7927_TP_W11_64_V5603998_20250709R.zip?model=ROG%20CROSSHAIR%20X870E%20HERO&Signature=${SIG}&Expires=${EXPIRES}&Key-Pair-Id=${KID}" \
         -O /tmp/asus-mt7927.zip \
    && bsdtar -xf /tmp/asus-mt7927.zip -C /tmp mtkwlan.dat \
    && python3 /tmp/mediatek-mt7927-dkms/extract_firmware.py /tmp/mtkwlan.dat /tmp/firmware \
    && install -Dm644 /tmp/firmware/BT_RAM_CODE_MT6639_2_1_hdr.bin \
         /usr/lib/firmware/mediatek/mt6639/BT_RAM_CODE_MT6639_2_1_hdr.bin \
    && install -Dm644 /tmp/firmware/WIFI_MT6639_PATCH_MCU_2_1_hdr.bin \
         /usr/lib/firmware/mediatek/mt7927/WIFI_MT6639_PATCH_MCU_2_1_hdr.bin \
    && install -Dm644 /tmp/firmware/WIFI_RAM_CODE_MT6639_2_1.bin \
         /usr/lib/firmware/mediatek/mt7927/WIFI_RAM_CODE_MT6639_2_1.bin \
    && echo "Firmware installé"

RUN KERNEL_VER=$(ls /usr/lib/modules/ | head -1) \
    && echo "Injection du header airoha manquant..." \
    && tar -xf /tmp/linux-${MT76_KVER}.tar.xz \
         "linux-${MT76_KVER}/include/linux/soc/airoha/airoha_offload.h" \
    && mkdir -p /usr/src/kernels/${KERNEL_VER}/include/linux/soc/airoha/ \
    && cp linux-${MT76_KVER}/include/linux/soc/airoha/airoha_offload.h \
         /usr/src/kernels/${KERNEL_VER}/include/linux/soc/airoha/ \
    && rm -rf linux-${MT76_KVER} \
    && echo "Header injecté"

RUN KERNEL_VER=$(ls /usr/lib/modules/ | head -1) \
    && dkms add -m mediatek-mt7927 -v ${MT7927_VER} \
    && dkms build -m mediatek-mt7927 -v ${MT7927_VER} -k ${KERNEL_VER} \
    || (cat /var/lib/dkms/mediatek-mt7927/${MT7927_VER}/build/make.log && exit 1) \
    && dkms install --force -m mediatek-mt7927 -v ${MT7927_VER} -k ${KERNEL_VER}

# Vérification — jetm installe dans /updates/dkms/ (pas /extra/)
RUN KERNEL_VER=$(ls /usr/lib/modules/ | head -1) \
    && echo "Modules installés:" \
    && find /usr/lib/modules/${KERNEL_VER}/updates/dkms/ -name "*.ko*" | sort \
    && test -f "/usr/lib/modules/${KERNEL_VER}/updates/dkms/mt76.ko.xz"    || (echo "ERREUR: mt76.ko.xz manquant!"    && exit 1) \
    && test -f "/usr/lib/modules/${KERNEL_VER}/updates/dkms/mt7925e.ko.xz" || (echo "ERREUR: mt7925e.ko.xz manquant!" && exit 1) \
    && echo "OK: mt76.ko.xz et mt7925e.ko.xz présents"

RUN echo -e 'install mt7925e modprobe --ignore-install mt7925e\ninstall mt76 modprobe --ignore-install mt76' \
      > /etc/modprobe.d/mt7927-override.conf

RUN echo 'add_drivers+=" mt76 mt7925e mt76_connac_lib "' \
      > /etc/dracut.conf.d/mt7927.conf \
    && KERNEL_VER=$(ls /usr/lib/modules/ | head -1) \
    && dracut --force --kver ${KERNEL_VER}

RUN rm -rf /tmp/mediatek-mt7927-dkms /tmp/mt76 /tmp/bluetooth \
           /tmp/linux-*.tar.xz /tmp/asus-mt7927.zip /tmp/firmware

RUN echo 'mt7925e' > /etc/modules-load.d/mt7927.conf

### LINTING
RUN bootc container lint
