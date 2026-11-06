include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-kabanmax

KABANMAX_SOURCE_VERSION:=$(or $(KABANMAX_PACKAGE_VERSION),$(KABANMAX_VERSION))
KABANMAX_HAS_RELEASE_VERSION:=$(if $(filter dev,$(KABANMAX_SOURCE_VERSION)),,$(KABANMAX_SOURCE_VERSION))
KABANMAX_COMPILED_VERSION:=$(if $(KABANMAX_HAS_RELEASE_VERSION),$(KABANMAX_SOURCE_VERSION),$(or $(KABANMAX_SOURCE_VERSION),dev))
KABANMAX_RELEASE_VERSION_VALID:=$(if $(KABANMAX_HAS_RELEASE_VERSION),$(shell printf '%s\n' '$(KABANMAX_SOURCE_VERSION)' | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$$' && printf '1'),1)

ifeq ($(KABANMAX_RELEASE_VERSION_VALID),)
$(error KABANMAX_PACKAGE_VERSION and KABANMAX_VERSION must use x.y.z format)
endif

PKG_VERSION:=$(or $(KABANMAX_HAS_RELEASE_VERSION),0.0.0)
PKG_RELEASE:=
PKG_PO_VERSION:=$(PKG_VERSION)

LUCI_TITLE:=LuCI K.A.B.A.N.-MAX app
LUCI_DEPENDS:=+luci-base +kabanmax
LUCI_PKGARCH:=all
LUCI_LANG.ru:=Русский (Russian)
LUCI_LANG.en:=English
LUCI_MAINTAINER:=ushan0v <ushan0v@users.noreply.github.com>
LUCI_DESCRIPTION:=Web interface for KabanMax
LUCI_MINIFY_JS:=0

PKG_LICENSE:=GPL-2.0-or-later
LUCI_LANGUAGES:=en ru

define Build/Prepare/$(PKG_NAME)
	sed -i -e 's/__COMPILED_VERSION_VARIABLE__/$(KABANMAX_COMPILED_VERSION)/g' $(PKG_BUILD_DIR)/htdocs/luci-static/resources/view/kabanmax/main.js
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
