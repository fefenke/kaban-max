// KabanMax's own names, paths and marks; the sing-box configuration's are in singbox/constants.uc.

return {
    KABANMAX_VERSION: "__COMPILED_VERSION_VARIABLE__",
    KABANMAX_CONFIG_NAME: "kabanmax",
    KABANMAX_BIN: "/usr/bin/kabanmax",
    KABANMAX_SERVICE_INIT: "/etc/init.d/kabanmax",
    // START in the init script, which names its rc.d links.
    KABANMAX_START_PRIORITY: "99",
    KABANMAX_RELEASE_REPO: "fefenke/kaban-max",
    KABANMAX_LUCI_VIEW_DIR: "/www/luci-static/resources/view/kabanmax",
    KABANMAX_LUCI_I18N_DOMAIN: "kabanmax",
    // Tags match at the start of a message, so a LuCI login on a KabanMax page stays out.
    KABANMAX_LOG_PATTERN: "^\\(kabanmax\\|sing-box\\)\\|^procd: .*\\(kabanmax\\|sing-box\\)",

    RT_TABLE_NAME: "kabanmax",

    NFT_TABLE_NAME: "KabanMaxTable",
    NFT_LOCALV4_SET_NAME: "localv4",
    NFT_LOCALV6_SET_NAME: "localv6",
    NFT_INTERFACE_SET_NAME: "kabanmax_interfaces",
    NFT_PAUSE_CHAIN_NAME: "capture_pause",
    NFT_FAKEIP_MARK: "0x04000000",
    NFT_OUTBOUND_MARK: "0x08000000",
    // What the router itself sends to sing-box: a mark of its own keeps rule 104 off its lookups.
    NFT_ROUTER_MARK: "0x10000000",
    // A redirect hooked earlier would take a query before KabanMax sees it.
    NFT_DNS_REDIRECT_PRIORITY: -101,
    NFT_SYSTEM_DNS_REDIRECT_PRIORITY: -100,

    SB_REQUIRED_VERSION: "1.14.4-r8"
};
