FROM alpine:3.23@sha256:ff7f0c727dd796aa36787bfcd9a64bf35a6ce72a73451b3359fde849b6703d63
RUN apk add --no-cache bash git curl wget tar gzip xz zstd coreutils findutils file \
    build-base cmake json-c-dev pkgconf openssl-dev zlib-dev go nodejs npm python3
# Official LuCI converter, pinned to the source used for the initial release.
RUN git clone --filter=blob:none --no-checkout https://github.com/openwrt/luci.git /tmp/luci \
    && git -C /tmp/luci checkout e405c199a0898da9f61372dfae4d8972c43d2c31 -- modules/luci-base/src \
    && make -C /tmp/luci/modules/luci-base/src po2lmo \
    && cp /tmp/luci/modules/luci-base/src/po2lmo /usr/local/bin/po2lmo \
    && rm -rf /tmp/luci
WORKDIR /work
