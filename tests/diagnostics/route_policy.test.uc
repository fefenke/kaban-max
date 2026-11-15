let t = require("t");
let policy = require("diagnostics.route_policy");

function config(rules) { return { route: { rules, final: "direct-out" } }; }
function query(extra) { return { destination: "203.0.113.7", source: "192.168.1.8", port: "443", ...(extra ?? {}) }; }
let zap = { action: "route", outbound: "zap", ip_cidr: [ "203.0.113.0/24" ] };
let block = { action: "reject", ip_cidr: [ "203.0.113.7/32" ] };

t.test("first matching Block forbids selection; lower Block does not override Zapret", () => {
    t.eq(policy.predict(config([block, zap]), query()).predicted.action, "reject");
    let result = policy.predict(config([zap, block]), query());
    t.eq(result.predicted.outbound, "zap");
    t.eq(result.predicted.rule_index, 0);
    t.eq(result.observed.status, "unavailable");
    t.eq(result.verified.status, "not_run");
    t.eq(result.automation.status, "unsupported");
});

t.test("Bypass and device port scope follow actual order", () => {
    let first = { ...block, source_ip_cidr: [ "192.168.1.9" ], port: [443] };
    t.eq(policy.predict(config([first, zap]), query()).predicted.outbound, "zap");
    t.eq(policy.predict(config([{ ...block, port: [80] }, zap]), query()).predicted.outbound, "zap");
    t.eq(policy.predict(config([{ ...zap, outbound: "direct-out" }, zap]), query()).predicted.outbound, "direct-out");
    t.eq(policy.predict(config([first, zap]), query({ source: "" })).predicted.status, "unknown");
    t.eq(policy.predict(config([{ ...block, inbound: ["system-in", "system6-in"] }, zap]), query({ source: "" })).predicted.status, "unknown");
    t.eq(policy.predict(config([{ ...block, inbound: ["system-in", "system6-in"] }, zap]), query()).predicted.outbound, "zap");
});

t.test("unresolved providers and protocol guards never fall through to Direct", () => {
    for (let first in [ { action: "route", outbound: "vpn", rule_set: "remote" },
        { action: "route", outbound: "vpn", protocol: "bittorrent" },
        { type: "logical", mode: "and", rules: [ { rule_set: "missing" }, { port: [443] } ], action: "reject" } ])
        t.eq(policy.predict(config([first]), query()).predicted.status, "unknown");
    t.eq(policy.predict(config([{ action: "route", rule_set: "missing", port: [80] }, zap]), query()).predicted.outbound, "zap");
    t.eq(policy.predict(config([{ action: "route", outbound: "vpn", domain: ["different.test"], rule_set: "missing" }]), query({ destination: "example.test" })).predicted.status, "unknown");
    t.eq(policy.predict(config([{ ...block, source_ip_cidr: ["192.168.1.1"] }, zap]), query({ source: "@system" })).predicted.status, "unknown");
});

t.test("literal IPv6 uses CIDR matching and invalid inputs stay invalid", () => {
    let result = policy.predict(config([{ action: "reject", ip_cidr: [ "2001:db8::/32" ] }]), query({ destination: "2001:db8::7" }));
    t.eq(result.predicted.action, "reject");
    for (let q in [ { destination: "bad host" }, { port: "0" }, { port: "443x" }, { source: "not-ip" }, { destination: "https://example.com" }, { destination: "999.0.0.1" } ])
        t.eq(policy.predict(config([]), query(q)).predicted.status, "invalid_input");
});

t.test("DNS and FakeIP are never silently treated as real addresses", () => {
    let resolve = { action: "resolve", server: "dns-server" };
    t.eq(policy.predict(config([resolve, zap]), query({ destination: "example.test" })).predicted.status, "unknown");
    t.eq(policy.predict(config([zap]), query({ destination: "198.18.0.7" })).predicted.status, "unknown");
    t.eq(policy.predict(config([zap]), query({ destination: "fc00::7" })).predicted.status, "unknown");
    t.eq(policy.predict(config([zap]), query({ destination: "example.test" })).predicted.status, "unknown");
    t.eq(policy.predict(null, query()).predicted.status, "unknown");
});

t.test("exact domain suffix and logical rules; unknown rules and depth are bounded", () => {
    let rules = [ { action: "reject", domain_suffix: [ "example.test" ] } ];
    t.eq(policy.predict(config(rules), query({ destination: "A.Example.Test." })).predicted.action, "reject");
    t.eq(policy.predict(config(rules), query({ destination: "notexample.test" })).predicted.outbound, "direct-out");
    let logical = { action: "reject", type: "logical", mode: "or", rules: [ { port: [80] }, { ip_cidr: ["203.0.113.7"] } ] };
    t.eq(policy.predict(config([logical]), query()).predicted.action, "reject");
    t.eq(policy.predict(config([{ action: "reject", new_matcher: true }]), query()).predicted.status, "unknown");
    t.eq(policy.predict(config([{ ...zap, domain: ["example.test"] }]), query({ destination: "example.test" })).predicted.status, "unknown");
    let nested = { port: [443] };
    for (let i = 0; i < 12; i++) nested = { type: "logical", mode: "and", rules: [nested] };
    t.eq(policy.predict(config([{ ...nested, action: "reject" }]), query()).predicted.status, "unknown");
});

t.test("inspection never mutates its input or claims active verification", () => {
    let c = config([block, zap]);
    let before = sprintf("%J", c);
    policy.predict(c, query());
    t.eq(sprintf("%J", c), before);
    t.eq(policy.predict(c, query()).automation.reason, "r10_probe_evidence_unavailable");
});

t.test("rule budgets and repeated forecasts cannot create fallback or active probes", () => {
    let many = [];
    for (let i = 0; i < 1025; i++) push(many, { action: "reject", port: [80] });
    t.eq(policy.predict(config(many), query()).predicted.reason, "rule_budget_exceeded");
    let c = config([{ action: "reject", source_ip_cidr: ["192.168.1.8/32"], port_range: ["400:500"] }, zap]);
    for (let i = 0; i < 25; i++) {
        let result = policy.predict(c, query());
        t.eq(result.predicted.action, "reject");
        t.eq(result.verified.requests, 0);
    }
});
t.done();
