let t = require("t");
let fixture = require("fixture");
let generator = require("singbox.generator");
let q = require("sbconfig");

function build(extra, sections) {
    fixture.seed({
        settings: { dns_detour_enabled: "1", dns_detour_section: "proxy", dns_server: "https://dns.example/dns-query", ...(extra ?? {}) },
        section: sections ?? [ { ".name": "proxy", enabled: "1", action: "connection" } ],
        connection_link: fixture.links("proxy", [ "vless://11111111-1111-4111-8111-111111111111@vpn.example:443#VPN" ]),
        subscription_url: [ { ".name": "sub", section: "proxy", tag: "sub", url: "https://sub.example/nodes" } ]
    });
    return generator.build({ service_address: "127.0.0.1" });
}

t.test("destination DNS uses main while VPN, DNS and subscription infrastructure bootstraps independently", () => {
    for (let server in [ "https://dns.example/dns-query", "1.1.1.1", "tls://[2001:db8::53]" ]) {
        let config = build({ dns_server: server });
        t.eq(config.route.default_domain_resolver, "dns-server");
        t.eq(q.outbound(config, "proxy/VPN").domain_resolver, "bootstrap-dns-server");
        t.eq(q.dns_server_tag(config, "dns-server").detour, "proxy");
        t.eq(q.dns_server_tag(config, "bootstrap-dns-server").detour, null);
        t.eq(q.provider(config, "proxy/sub").override.patch.domain_resolver, "bootstrap-dns-server");
        let download = q.outbound(config, q.provider(config, "proxy/sub").download_detour);
        t.eq(download.type, "direct");
        t.eq(download.domain_resolver, "bootstrap-dns-server");
        t.eq(q.outbound(config, "direct-out").domain_resolver, null, "user Direct inherits main");
    }
    t.eq(build({ dns_detour_enabled: "0" }).route.default_domain_resolver, "dns-server");
});

t.test("IP-only and mixed Bypass evaluate real answers before later FakeIP, preserving device and family", () => {
    let config = build({}, [
        { ".name": "bypass", enabled: "1", action: "bypass", source_ip_cidr: [ "192.0.2.7/32" ],
          destinations: "192.0.2.0/24\n2001:db8::/32", rule_set_with_subnets: [ "https://lists.example/mixed.srs" ] },
        { ".name": "proxy", enabled: "1", action: "connection", destinations: "example.org", source_ip_cidr: [ "192.0.2.7/32" ] }
    ]);
    let evaluate = filter(config.dns.rules, (r) => r.action == "evaluate");
    let respond = filter(config.dns.rules, (r) => r.action == "respond");
    t.eq(length(evaluate), 1);
    t.eq(evaluate[0].server, "dns-server");
    t.eq(evaluate[0].source_ip_cidr, "192.0.2.7/32");
    t.eq(evaluate[0].query_type, [ "A", "AAAA" ]);
    t.eq(length(respond), 2, "inline CIDRs and SRS are alternative matches");
    t.eq(respond[0].ip_cidr, [ "192.0.2.0/24", "2001:db8::/32" ]);
    for (let rule in respond) {
        t.eq(rule.match_response, evaluate[0].tag);
        t.eq(rule.source_ip_cidr, "192.0.2.7/32");
    }
    let at = (action) => q.dns_rule_index(config, (r) => r.action == action);
    t.ok(at("evaluate") < at("respond"), "evaluate precedes respond");
    t.ok(at("respond") < q.dns_rule_index(config, (r) => r.server == "fakeip-server" && r.source_ip_cidr != null), "Bypass response check precedes the later section's FakeIP");
    for (let rule in config.dns.rules)
        if (rule.rule_set != null && rule.match_response == null)
            t.eq(rule.rule_set_domain_only, true);
});
t.test("raw endpoint resolvers and explicit subscription patches keep the user's resolver", () => {
    fixture.seed({ settings: { dns_detour_enabled: "1", dns_detour_section: "proxy" },
        section: [ { ".name": "proxy", action: "connection", enabled: "1", outbound_jsons: [
            '{"type":"socks","tag":"custom","server":"vpn.example","server_port":1080,"domain_resolver":{"server":"bootstrap-dns-server","strategy":"ipv6_only"}}'
        ] } ],
        subscription_url: [ { ".name": "sub", section: "proxy", tag: "sub", url: "/tmp/nodes", override_patch: '{"domain_resolver":{"server":"bootstrap-dns-server","strategy":"ipv6_only"}}' } ]
    });
    let config = generator.build({ service_address: "127.0.0.1" });
    t.eq(q.outbound(config, "proxy/custom").domain_resolver, { server: "bootstrap-dns-server", strategy: "ipv6_only" });
    t.eq(q.provider(config, "proxy/sub").override.patch.domain_resolver, { server: "bootstrap-dns-server", strategy: "ipv6_only" });
});

t.test("Bypass response evaluation keeps IPv6 and System source variants distinct and skips port-limited sections", () => {
    let config = build({}, [
        { ".name": "bypass", action: "bypass", source_ip_cidr: [ "2001:db8::7/128", "@system" ], destinations: "2001:db9::/32" },
        { ".name": "ports", action: "bypass", destinations: "192.0.2.0/24", ports: [ "443" ] },
        { ".name": "proxy", action: "connection", destinations: "example.org" }
    ]);
    let evaluate = filter(config.dns.rules, (r) => r.action == "evaluate");
    t.eq(length(evaluate), 2);
    t.eq(evaluate[0].source_ip_cidr, "2001:db8::7/128");
    t.eq(evaluate[0].inbound, [ "source-dns-in" ]);
    t.eq(evaluate[1].inbound, [ "system-dns-in" ]);
    t.eq(evaluate[1].source_ip_cidr, null);
    t.ok(evaluate[0].tag != evaluate[1].tag);
});

t.done();
