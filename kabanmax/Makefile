include $(TOPDIR)/rules.mk

PKG_NAME:=kabanmax

KABANMAX_SOURCE_VERSION:=$(or $(KABANMAX_PACKAGE_VERSION),$(KABANMAX_VERSION))
KABANMAX_HAS_RELEASE_VERSION:=$(if $(filter dev,$(KABANMAX_SOURCE_VERSION)),,$(KABANMAX_SOURCE_VERSION))
KABANMAX_COMPILED_VERSION:=$(if $(KABANMAX_HAS_RELEASE_VERSION),$(KABANMAX_SOURCE_VERSION),$(or $(KABANMAX_SOURCE_VERSION),dev))
KABANMAX_RELEASE_VERSION_VALID:=$(if $(KABANMAX_HAS_RELEASE_VERSION),$(shell printf '%s\n' '$(KABANMAX_SOURCE_VERSION)' | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$$' && printf '1'),1)

ifeq ($(KABANMAX_RELEASE_VERSION_VALID),)
$(error KABANMAX_PACKAGE_VERSION and KABANMAX_VERSION must use x.y.z format)
endif

PKG_VERSION:=$(or $(KABANMAX_HAS_RELEASE_VERSION),0.0.0)
PKG_RELEASE:=

PKG_MAINTAINER:=K.A.B.A.N.-MAX contributors <341400787+fefenke@users.noreply.github.com>
PKG_LICENSE:=GPL-2.0-or-later

include $(INCLUDE_DIR)/package.mk

define Package/kabanmax
	SECTION:=net
	CATEGORY:=Network
	DEPENDS:=+ca-bundle +ucode +ucode-mod-fs +ucode-mod-resolv +ucode-mod-socket +ucode-mod-ubus +ucode-mod-uloop +ucode-mod-uci +uclient-fetch +kmod-nft-tproxy +nftables +kmod-nft-nat +kmod-nfnetlink-queue +kmod-nft-queue +ip-tiny +sing-box-kabanmax
	TITLE:=K.A.B.A.N.-MAX backend service
	URL:=https://github.com/fefenke/kaban-max
	PKGARCH:=all
endef

define Package/kabanmax/description
	Rule-based traffic routing for OpenWrt
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/kabanmax/prerm
#!/usr/bin/ucode

if (getenv("IPKG_INSTROOT") == null || getenv("IPKG_INSTROOT") == "")
	system("/usr/bin/kabanmax package_prerm " + (ARGV[0] || "") + " >/dev/null 2>&1");

exit(0);
endef

define Package/kabanmax/postinst
#!/bin/sh

[ -n "$${IPKG_INSTROOT}" ] && exit 0
KABANMAX_LIB=/usr/lib/kabanmax ucode -L /usr/lib/kabanmax /usr/lib/kabanmax/config/migration.uc migrate || exit $$?
KABANMAX_BYTECODE_VALIDATION_TTL=0 /usr/bin/kabanmax package_postinst
endef

define Package/kabanmax/conffiles
/etc/config/kabanmax
endef

define Package/kabanmax/install
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/etc/init.d/kabanmax $(1)/etc/init.d/kabanmax
	$(INSTALL_BIN) ./files/etc/init.d/kabanmax-state $(1)/etc/init.d/kabanmax-state
	$(INSTALL_BIN) ./files/etc/init.d/kabanmax-zapret2 $(1)/etc/init.d/kabanmax-zapret2

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/etc/config/kabanmax $(1)/etc/config/kabanmax
	$(INSTALL_DIR) $(1)/usr/share/kabanmax
	$(INSTALL_DATA) ./files/etc/config/kabanmax $(1)/usr/share/kabanmax/default-config

	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./files/usr/bin/kabanmax $(1)/usr/bin/kabanmax

	$(INSTALL_DIR) $(1)/usr/lib/kabanmax
	$(CP) ./files/usr/lib/. $(1)/usr/lib/kabanmax/

	$(INSTALL_DIR) $(1)/usr/share/nftables.d/chain-pre/input
	$(INSTALL_DATA) ./files/usr/share/nftables.d/chain-pre/input/kabanmax.nft $(1)/usr/share/nftables.d/chain-pre/input/kabanmax.nft

	$(INSTALL_DIR) $(1)/lib/upgrade/keep.d
	$(INSTALL_DATA) ./files/lib/upgrade/keep.d/kabanmax $(1)/lib/upgrade/keep.d/kabanmax

	sed -i -e 's/__COMPILED_VERSION_VARIABLE__/$(KABANMAX_COMPILED_VERSION)/g' $(1)/usr/lib/kabanmax/core/constants.uc
endef

$(eval $(call BuildPackage,kabanmax))
