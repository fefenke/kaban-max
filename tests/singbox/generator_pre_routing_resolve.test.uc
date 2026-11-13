let t = require("t");
let fixture = require("fixture");
let generator = require("singbox.generator");
let q = require("sbconfig");

function build(settings) {
    fixture.seed({ settings, section: [
        { ".name": "ip", enabled: "1", action: "bypass", destinations: "192.0.2.0/24" },
        { ".name": "domain", enabled: "1", action: "zapret2", destinations: "example.org" }
    ] });
    return generator.build({ service_address: "192.168.1.1" });
}

t.test("disabled by default", () => {
    t.eq(q.route_rule(build({}), (r) => r.action == "resolve" && r.server == "dns-server"), null);
});

t.test("all resolves with real main DNS before ordered user routes", () => {
    let config = build({ pre_routing_resolve_mode: "all", static_hosts_text: "192.0.2.7 pinned.example" });
    let at = q.route_rule_index(config, (r) => r.action == "resolve" && r.server == "dns-server");
    t.ok(at >= 0, "main DNS resolve exists");
    t.ok(at > q.route_rule_index(config, (r) => r.server == "hosts-server"), "static overrides first");
    t.ok(at > q.route_rule_index(config, (r) => r.domain == "ip.podkop.fyi" && r.action == "route"), "service rules first");
    let ip_at = q.route_rule_index(config, (r) => r.ip_cidr != null);
    let domain_at = q.route_rule_index(config, (r) => r.domain_suffix != null && r.domain_suffix[0] == "example.org");
    t.ok(at < ip_at && ip_at < domain_at, "resolution does not move an IP rule below domain routing");
    t.eq(config.route.rules[domain_at].outbound, "domain", "the lower domain rule still uses its Zapret2 outbound");
    t.eq(config.route.rules[at].rules[0], { domain: [ "pinned.example", "ip.podkop.fyi", "fakeip.podkop.fyi" ], invert: true });
});

t.test("selected preserves suffix and exact syntax", () => {
    let config = build({ pre_routing_resolve_mode: "selected", pre_routing_resolve_domains: "example.org\nfull:ONLY.example\n# comment" });
    let rule = q.route_rule(config, (r) => r.action == "resolve" && r.server == "dns-server");
    t.ok(rule != null);
    t.eq(rule.rules[1], { type: "logical", mode: "or", rules: [ { domain_suffix: [ "example.org" ] }, { domain: [ "only.example" ] } ] });
});
t.done();
