let t = require("t");
let model = require("zapret2.model");
let updates = require("zapret2.updater");

t.test("disabling or reordering sections does not reassign active connection marks", () => {
    let fs = require("fs"), fixture = require("fixture");
    model.paths.slots = require("stub").tmpdir() + "/slots.json";
    fixture.seed({ section: [{ ".name": "first", action: "zapret2" }, { ".name": "second", action: "zapret2" }] });
    model.persist_slots();
    let before = model.mark("second");
    fixture.seed({ section: [{ ".name": "second", action: "zapret2" }, { ".name": "third", action: "zapret2" }] });
    model.persist_slots();
    t.eq(model.mark("second"), before);
    t.ok(model.mark("third") != 0x02000001, "retired marks must not be reused for another strategy");
    model.paths.slots = "/etc/kabanmax/zapret2-slots.json";
});

t.test("strategies are parsed without shell evaluation and cannot replace queue ownership", () => {
    t.eq(model.arguments('--filter-tcp=443 --lua-desync="multisplit:pos=1,midsld"'),
        ["--filter-tcp=443", "--lua-desync=multisplit:pos=1,midsld"]);
    t.eq(model.arguments("--lua-init='$(touch /tmp/no)'"), ["--lua-init=$(touch /tmp/no)"]);
    for (let arg in ["--qnum=1", "--daemon", "--pidfile=/tmp/p", "--fwmark=0", "--lua-desync='unfinished"])
        t.throws(() => model.arguments(arg));
});
t.test("legacy bundled files and Lua resolve inside the managed release", () => {
    require("fixture").seed({ section: [{ ".name": "legacy", action: "zapret2",
        nfqws2_opt: "--blob=fake_quic:@/opt/zapret2/files/fake/quic_initial_www_google_com.bin --lua-init=@/opt/zapret2/lua/zapret-obfs.lua" }] });
    let args = model.instances()[0].argv;
    t.contains(args, "--blob=fake_quic:@/opt/kabanmax-zapret2/current/files/fake/quic_initial_www_google_com.bin");
    t.contains(args, "--lua-init=@/opt/kabanmax-zapret2/current/lua/zapret-obfs.lua");
});
t.test("updater uses official embedded releases with a digest and supported architectures", () => {
    let url = "https://github.com/bol-van/zapret2/releases/download/v1.0.6/zapret2-v1.0.6-openwrt-embedded.tar.gz";
    let asset = { name: "zapret2-v1.0.6-openwrt-embedded.tar.gz", browser_download_url: url,
        url: "https://api.github.com/repos/bol-van/zapret2/releases/assets/1", digest: "sha256:" + sprintf("%064d", 0) };
    t.eq(updates.select_release({ tag_name: "v1.0.6", assets: [asset] }).version, "v1.0.6");
    t.throws(() => updates.select_release({ tag_name: "v1.0.6", assets: [{...asset, digest: ""}] }));
    t.eq(updates.architecture("aarch64_cortex-a53", "aarch64"), "arm64");
    t.eq(updates.architecture("mipsel_24kc", "mips"), "mipsel");
    t.eq(updates.architecture("x86_64", "x86_64"), "x86_64");
    t.throws(() => updates.architecture("unknown", "mystery"));
});
t.test("failed activation restores the old release and restarts it", () => {
    let calls = [], starts = 0;
    let ops = {
        stop: () => { push(calls, "stop"); },
        select: (target) => { push(calls, target); },
        start: () => { push(calls, "start"); if (++starts == 1) die("new release cannot start"); }
    };
    t.eq(t.throws(() => updates.activate("new", "old", true, ops)).message, "new release cannot start");
    t.eq(calls, ["stop", "new", "start", "stop", "old", "start"]);
});
t.test("an installation on a stopped router keeps KabanMax stopped", () => {
    let calls = [];
    updates.activate("new", null, false, {
        select: (target) => { push(calls, target); },
        stop: () => die("must not stop"), start: () => die("must not start")
    });
    t.eq(calls, ["new"]);
});
t.test("even a fresh installation checks the bundled default strategy", () => {
    require("fixture").seed({ section: [] });
    let instances = model.instances(true);
    t.eq(length(instances), 1);
    t.eq(instances[0].name, "default");
    t.contains(instances[0].argv, "--lua-init=@" + model.LUA + "zapret-antidpi.lua");
    t.contains(instances[0].argv, "--filter-udp=443");
});
t.test("upstream KabanMax installer cannot remove an active Zapret2 integration", () => {
    require("fixture").seed({ section: [{ ".name": "yt", action: "zapret2" }] });
    let constants = require("core.constants");
    let own = constants.KABANMAX_RELEASE_REPO;
    constants.KABANMAX_RELEASE_REPO = "ushan0v/forkop";
    t.contains(t.throws(() => require("service.installer").start("update", "", "0", "en")).message, "Zapret2 fork");
    constants.KABANMAX_RELEASE_REPO = own;
});
t.done();
