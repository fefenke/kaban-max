let t = require("t");
let release = require("service.release");
let stub = require("stub");
let fs = require("fs");
let constants = require("core.constants");
let app = { schema: 1, name: "kabanmax", version: "0.1.0", tag: "0.1.0" };
let core = { schema: 1, name: "sing-box-kabanmax", version: "1.14.4-r6", tag: "0.1.0" };
t.test("same app release detects a newer core revision", () => {
    let result = release.evaluate(app, core, "0.1.0", "0.1.0", "1.14.4-r5");
    t.eq(result.update_available, true);
    t.eq(result.release, "0.1.0");
    t.eq(result.core_latest, "1.14.4-r6");
    t.eq(release.evaluate(app, core, "0.1.0", "0.1.0", "1.14.4-r6").update_available, false);
});
t.test("metadata and pinned tags fail closed", () => {
    for (let tag in [ "latest", "0.1.0;id", "../0.1.0", "v0.1.0", "" ])
        t.eq(release.valid_tag(tag), false);
    t.eq(release.valid_manifest({ ...app, tag: "0.2.0" }, "kabanmax", "0.1.0"), false);
    t.eq(release.valid_manifest({ ...core, version: "unknown" }, "sing-box-kabanmax", "0.1.0"), false);
    let failed = false;
    try { release.evaluate(app, core, "0.1.0", "0.1.0", "1.14.4-r7"); } catch (e) { failed = true; }
    t.eq(failed, true);
});
t.test("numeric prereleases participate in release selection", () => {
    let stable = { tag_name: "0.1.0", prerelease: false };
    let previous = { tag_name: "0.0.9", prerelease: true };
    let latest = { tag_name: "0.1.1", prerelease: true };
    t.eq(release.select_release([ stable, previous, latest ]), latest);
    t.eq(release.select_release([ latest, stable, previous ]), latest);
    t.eq(release.select_release([ { ...stable, prerelease: true }, latest ]), latest);
    t.eq(release.select_release([ { tag_name: "0.1.9" }, { tag_name: "0.1.10", prerelease: true } ]).tag_name, "0.1.10");
});
t.test("release selection excludes drafts and unsupported tags", () => {
    let supported = { tag_name: "0.1.1", prerelease: true };
    t.eq(release.select_release([ null, {}, { tag_name: "0.9.0", draft: true },
        { tag_name: "v9.0.0" }, { tag_name: "9.0.0-rc1" }, supported ]), supported);
    t.contains(t.throws(() => release.select_release([])).message, "No supported published");
    t.contains(t.throws(() => release.select_release([ { tag_name: "0.9.0", draft: true } ])).message, "No supported published");
    t.contains(t.throws(() => release.select_release({})).message, "Invalid release listing");
});
t.test("release checks work when the router has no timeout applet", () => {
    let installed = constants.KABANMAX_VERSION;
    constants.KABANMAX_VERSION = "0.1.1";
    let tag = constants.KABANMAX_VERSION;
    let api = "https://api.github.com/repos/" + constants.KABANMAX_RELEASE_REPO;
    let assets = map([ "install.sh", "release.json", "core-release.json" ], (name, i) => ({ name, url: api + "/releases/assets/" + i }));
    let listing = [ { tag_name: tag, prerelease: true, assets } ];
    stub.env({ KABANMAX_DOWNLOAD_URL: "" });
    stub.commands([ [ () => true, (argv) => {
        if (argv[0] != "sh") return { status: 1 };
        if (index(argv[2], "exec timeout") >= 0) return { status: 127 };
        let path = argv[index(argv, "-O") + 1];
        let url = argv[length(argv)-1];
        let value = index(url, "/releases?") >= 0 ? listing
            : url == assets[1].url ? { schema: 1, name: "kabanmax", tag, version: tag }
            : { schema: 1, name: "sing-box-kabanmax", tag, version: "1.14.4-r6" };
        fs.writefile(path, sprintf("%J", value));
        return { status: 0 };
    } ] ]);
    let result = release.check();
    t.eq(result.release, tag);
    t.eq(result.prerelease, true);
    constants.KABANMAX_VERSION = installed;
    stub.restore();
});

t.done();
