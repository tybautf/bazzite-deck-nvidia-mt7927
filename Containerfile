# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY build_files /

# Base Image
FROM ghcr.io/ublue-os/bazzite-deck-nvidia:stable

# ── Modifications générales Bazzite ──────────────────────────────────────────
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh

# ── Driver WiFi MT7927 ────────────────────────────────────────────────────────
# MT7927_VER : version du package DKMS jetm
# MT76_KVER  : version du tarball kernel.org servant de base aux sources mt76
# CACHE_BUST : incrémenter pour forcer le re-clone du repo jetm
ARG MT7927_VER="2.4"
ARG MT76_KVER="6.19.4"
ARG CACHE_BUST=1
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=tmpfs,dst=/tmp \
    MT7927_VER=${MT7927_VER} MT76_KVER=${MT76_KVER} \
    bash /ctx/build-mt7927.sh

# ── Drivers Nvidia beta ───────────────────────────────────────────────────────
# Décommenter quand build-nvidia-beta.sh est prêt
# RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
#     --mount=type=cache,dst=/var/cache \
#     --mount=type=tmpfs,dst=/tmp \
#     /ctx/build-nvidia-beta.sh

### LINTING
RUN bootc container lint
