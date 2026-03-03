# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY build_files /

# Base Image
FROM ghcr.io/ublue-os/bazzite-deck-nvidia:stable

## Other possible base images include:
# FROM ghcr.io/ublue-os/bazzite:latest
# FROM ghcr.io/ublue-os/bluefin-nvidia:stable
# 
# ... and so on, here are more base images
# Universal Blue Images: https://github.com/orgs/ublue-os/packages
# Fedora base image: quay.io/fedora/fedora-bootc:41
# CentOS base images: quay.io/centos-bootc/centos-bootc:stream10

### [IM]MUTABLE /opt
## Some bootable images, like Fedora, have /opt symlinked to /var/opt, in order to
## make it mutable/writable for users. However, some packages write files to this directory,
## thus its contents might be wiped out when bootc deploys an image, making it troublesome for
## some packages. Eg, google-chrome, docker-desktop.
##
## Uncomment the following line if one desires to make /opt immutable and be able to be used
## by the package manager.

# RUN rm /opt && mkdir /opt

### MODIFICATIONS
## make modifications desired in your image and install packages by modifying the build.sh script
## the following RUN directive does all the things required to run "build.sh" as recommended.

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh

# ── Driver MT7927 ─────────────────────────────────────────────────────────────
ARG MT7927_VER="3.1"

RUN dnf5 -y install dkms git make gcc \
      kernel-devel-$(rpm -q --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}' kernel) \
    && dnf5 clean all

RUN git clone https://github.com/marcin-fm/mediatek-mt7927-dkms.git \
      /tmp/mediatek-mt7927-dkms

RUN install -d /usr/src/mediatek-mt7927-${MT7927_VER} \
    && cp -r /tmp/mediatek-mt7927-dkms/. /usr/src/mediatek-mt7927-${MT7927_VER}/

RUN KERNEL_VER=$(ls /usr/lib/modules/ | grep bazzite | head -1) \
    && dkms add -m mediatek-mt7927 -v ${MT7927_VER} \
    && dkms build -m mediatek-mt7927 -v ${MT7927_VER} -k ${KERNEL_VER} \
    && dkms install --force -m mediatek-mt7927 -v ${MT7927_VER} -k ${KERNEL_VER}

RUN KERNEL_VER=$(ls /usr/lib/modules/ | grep bazzite | head -1) \
    && MODULE_DIR="/usr/lib/modules/${KERNEL_VER}/updates/dkms" \
    && test -f "${MODULE_DIR}/mt76.ko"    || (echo "ERREUR: mt76.ko manquant!"    && exit 1) \
    && test -f "${MODULE_DIR}/mt7925e.ko" || (echo "ERREUR: mt7925e.ko manquant!" && exit 1) \
    && echo "OK: mt76.ko et mt7925e.ko présents"

RUN echo -e 'blacklist mt7925e\nblacklist mt76\ninstall mt7925e modprobe --ignore-install mt7925e\ninstall mt76 modprobe --ignore-install mt76' \
      > /etc/modprobe.d/mt7927-override.conf

RUN echo 'add_drivers+=" mt76 mt7925e mt76_connac_lib "' \
      > /etc/dracut.conf.d/mt7927.conf \
    && KERNEL_VER=$(ls /usr/lib/modules/ | grep bazzite | head -1) \
    && dracut --force --kver ${KERNEL_VER}

RUN rm -rf /tmp/mediatek-mt7927-dkms

### LINTING
## Verify final image and contents are correct.
RUN bootc container lint
