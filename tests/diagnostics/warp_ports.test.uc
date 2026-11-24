let t = require("t");
let fs = require("fs");
let tmp = require("stub").tmpdir();
let hints = require("diagnostics.warp_ports");
let fixture = require("fixture");
let fake = require("uci");
let common = require("core.common");
let clock = 1000;
let response;
let runtime;
hints.paths.state = tmp + "/warp-hints.json";
hints.paths.lock = tmp + "/warp-hints.lock";
hints.paths.delta = tmp + "/private-uci-delta";
hints.io.now = () => clock;
hints.io.wall = () => clock;
hints.io.request = () => response;
hints.io.config = () => runtime;

function seed(port) {
    fs.unlink(hints.paths.state);
    clock = 1000;
    fixture.seed({ settings: fixture.settings(), section: [{ ".name": "vpn", name: "vpn" }], tunnel: [
        { ".name": "first", section: "vpn", kind: "warp", name: "first", warp_profile_id: "profile1", warp_profile_auth_token: "token", warp_profile_private_key: "key", warp_local_port_hint: "" + port, warp_local_port_profile: "profile1" }
    ] });
    runtime = { endpoints: [{ type: "warp", tag: "vpn/first", profile: { id: "profile1", auth_token: "token", private_key: "key" } }] };
    response = { endpoints: [{ tag: "vpn/first", profile_id:"profile1", port: 42000, handshake_at: clock, data_at: clock, instance: "core1" }] };
}
function sample(at) {
    while (clock + 60 < at) {
        clock += 60;
        response.endpoints[0].handshake_at = clock;
        hints.capture();
    }
    clock = at;
    response.endpoints[0].handshake_at = at;
    return hints.capture();
}
function port() { return fake.cursor().get("kabanmax", "first", "warp_local_port_hint"); }

t.test("a working saved port never commits UCI", () => {
    seed(42000); sample(1000); sample(1600); sample(2200);
    response.endpoints[0].port = 43000;
    sample(2800);
    t.eq(length(fake.__commits()), 0);
});
t.test("replacement waits ten healthy minutes and writes once per boot", () => {
    seed(41000); sample(1000); sample(1599);
    t.eq(port(), "41000"); t.eq(length(fake.__commits()), 0);
    sample(1600); t.eq(port(), "42000"); t.eq(length(fake.__commits()), 1);
    response.endpoints[0].port = 43000;
    sample(1700); sample(2300);
    t.eq(port(), "42000"); t.eq(length(fake.__commits()), 1);
});
t.test("a failed request resets continuous health without losing boot allowance", () => {
    seed(41000); sample(1000);
    hints.io.request = () => { die("temporary API outage"); };
    clock = 1500; hints.capture();
    hints.io.request = () => response;
    clock = 1600;
    sample(1600); sample(2199); t.eq(length(fake.__commits()), 0);
    sample(2200); t.eq(port(), "42000");
    let checkpoint = common.read_json_file(hints.paths.state);
    t.ok(length(keys(checkpoint.saved)) > 0, "allowance survives service process restart in RAM file");
});
t.test("handshake without IP data and stale handshake cannot persist a hint", () => {
    seed(41000); response.endpoints[0].data_at = 0;
    sample(1000); sample(1600); t.eq(length(fake.__commits()), 0);
    response.endpoints[0].data_at = 1600;
    sample(1700); clock = 2300; hints.capture();
    t.eq(length(fake.__commits()), 0);
});
t.test("a restarted core resets stability; regenerated profile cannot inherit old hint", () => {
    seed(41000); sample(1000); response.endpoints[0].instance = "core2";
    sample(1500); sample(1600); t.eq(length(fake.__commits()), 0);
    let c = fake.cursor(); c.set("kabanmax", "first", "warp_profile_id", "regenerated"); c.commit("kabanmax");
    sample(2200); t.eq(port(), "41000"); t.eq(length(fake.__commits()), 1);
});
t.test("two profiles retain independent ports and batch eligible changes in one commit", () => {
    seed(41000);
    let c = fake.cursor();
    c.set("kabanmax", "second", "tunnel");
    for (let key, value in { section:"vpn", kind:"warp", name:"second", warp_profile_id:"profile2", warp_profile_auth_token:"token2", warp_profile_private_key:"key2" })
        c.set("kabanmax", "second", key, value);
    c.commit("kabanmax");
    push(runtime.endpoints, { type:"warp", tag:"vpn/second", profile:{id:"profile2",auth_token:"token2",private_key:"key2"} });
    push(response.endpoints, { tag:"vpn/second",profile_id:"profile2",port:44000,handshake_at:1000,data_at:1000,instance:"second" });
    for (let at = 1000; at <= 1600; at += 60) {
        clock = at;
        for (let row in response.endpoints) row.handshake_at = at;
        hints.capture();
    }
    t.eq(length(fake.__commits()), 2, "one seed commit and one batched hint commit");
    t.eq(port(), "42000");
    t.eq(fake.cursor().get("kabanmax", "second", "warp_local_port_hint"), "44000");
});
t.test("a corrupt boot checkpoint fails closed instead of granting a second write", () => {
    seed(41000); fs.writefile(hints.paths.state, "broken");
    sample(1000); sample(1600);
    t.eq(length(fake.__commits()), 0); t.eq(fs.readfile(hints.paths.state), "broken");
});
t.test("status from an old running profile cannot write the newly generated profile", () => {
    seed(41000); response.endpoints[0].profile_id = "old-profile";
    sample(1000); sample(1600); t.eq(length(fake.__commits()), 0);
});
t.test("hint commits use an isolated delta directory instead of staged LuCI settings", () => {
    seed(41000);
    let original = fake.cursor; let calls = [];
    fake.cursor = (config, delta) => { push(calls, [config,delta]); return original(config,delta); };
    sample(1000); sample(1600);
    fake.cursor = original;
    t.ok(length(calls)>0);
    for (let args in calls) t.eq(args,["/etc/config",hints.paths.delta]);
});
t.done();
