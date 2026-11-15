let t = require("t");
let fixture = require("fixture");
let generator = require("singbox.generator");
let policy = require("diagnostics.route_policy");
let fs = require("fs");
let stub = require("stub");
let cli = require("service.cli");
let uci = require("uci");

t.test("generated ordered domain Block and Zapret rules agree with forecast", () => {
    for (let action in ["block", "zapret2", "bypass"]) {
        fixture.seed({ settings: {}, section: [
            { ".name": "first", enabled: "1", action, destinations: "example.test", ports: ["443"], source_ip_cidr: ["192.168.1.8"] },
            { ".name": "later", enabled: "1", action: "block", destinations: "example.test" }
        ] });
        let config = generator.build({ service_address: "192.168.1.1" });
        let result = policy.predict(config, { destination: "example.test", source: "192.168.1.8", port: "443" });
        t.eq(result.predicted.status, "predicted", sprintf("%J", result));
        t.eq(result.predicted.action, action == "block" ? "reject" : "route");
        if (action != "block") t.eq(result.predicted.outbound, action == "bypass" ? "direct-out" : "first");
    }
});

t.test("CLI uses configured path, performs no commands and never commits UCI", () => {
    let path = stub.tmpdir() + "/config.json";
    fixture.seed({ settings: { config_path: path } });
    fs.writefile(path, sprintf("%J", { route: { rules: [{ action: "reject" }], final: "direct-out" } }));
    let before = sprintf("%J", uci.__sections("kabanmax"));
    stub.commands([[() => true, { status: 99 }]]);
    let response = stub.capture(() => cli.main(["check_route", "example.test", "192.168.1.8", "443"], "/lib"));
    t.eq(stub.command_lines(), []);
    stub.restore();
    t.eq(json(response.stdout).predicted.action, "reject");
    t.eq(json(response.stdout).verified.requests, 0);
    t.eq(uci.__commits(), []);
    t.eq(sprintf("%J", uci.__sections("kabanmax")), before);
});

t.test("pre-resolve modes cannot turn unresolved domains into Direct permissions", () => {
    for (let mode in ["disabled", "all", "selected"]) {
        fixture.seed({ settings: { pre_routing_resolve_mode: mode, pre_routing_resolve_domains: "example.test" }, section: [
            { ".name": "first", enabled: "1", action: "bypass", destinations: "203.0.113.0/24" },
            { ".name": "zap", enabled: "1", action: "zapret2", destinations: "example.test" }
        ] });
        let config = generator.build({ service_address: "192.168.1.1" });
        let result = policy.predict(config, { destination: "example.test", source: "192.168.1.8", port: "443" });
        t.eq(result.predicted.status, "unknown", mode);
        t.eq(result.verified.requests, 0);
    }
});
t.done();
