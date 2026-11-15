let t = require("t");
let paths = require("singbox.constants");

t.test("backend paths survive missing, empty and repeatedly saved UCI defaults", () => {
    for (let settings in [ {}, { config_path: "", cache_path: "" },
        { config_path: "/etc/sing-box/config.json", cache_path: "/tmp/sing-box/cache.db" } ]) {
        t.eq(paths.config_path(settings), "/etc/sing-box/config.json");
        t.eq(paths.cache_path(settings), "/tmp/sing-box/cache.db");
    }
    let custom = { config_path: "/tmp/custom/config.json", cache_path: "/srv/custom/cache.db" };
    t.eq(paths.config_path(custom), custom.config_path);
    t.eq(paths.cache_path(custom), custom.cache_path);
    t.eq(paths.config_path(custom), custom.config_path, "reads never rewrite the user's choice");
});
t.done();
