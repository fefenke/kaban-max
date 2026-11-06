let t = require("t");
let fs = require("fs");
let constants = require("core.constants");
t.test("runtime identity belongs to K.A.B.A.N.-MAX", () => {
    t.eq(constants.KABANMAX_CONFIG_NAME, "kabanmax");
    t.eq(constants.KABANMAX_BIN, "/usr/bin/kabanmax");
    t.eq(constants.KABANMAX_SERVICE_INIT, "/etc/init.d/kabanmax");
    t.eq(constants.RT_TABLE_NAME, "kabanmax");
    t.eq(constants.NFT_TABLE_NAME, "KabanMaxTable");
    t.ok(fs.stat("../luci-app-kabanmax/root/usr/share/luci/menu.d/luci-app-kabanmax.json") != null);
});
t.done();
