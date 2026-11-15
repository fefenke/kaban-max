let t = require("t");
let fixture = require("fixture");
let generator = require("singbox.generator");
let nft = require("nft.apply");

t.test("dnsmasq explicit local and conditional zones stay local before Bypass evaluation", () => {
    for (let local in [ "/home.arpa/", [ "/home.arpa/", "/corp.test/lab.test/" ] ]) {
        fixture.seed({ dhcp_dnsmasq: { domain: "lan", local,
            server: [ "/internal.test/192.0.2.53", "/ignored.test/#", "192.0.2.53" ] },
            section: [ { ".name": "b", action: "bypass", destinations: "203.0.113.0/24\ninternal.test" } ] });
        let rules = generator.build({ service_address: "127.0.0.1" }).dns.rules;
        for (let domain in [ ".lan", ".home.arpa", ".internal.test" ])
            t.ok(length(filter(rules, (r) => r.server == "dnsmasq-server" &&
                (r.domain_suffix == domain || (type(r.domain_suffix) == "array" && index(r.domain_suffix, domain) >= 0)))) > 0, domain);
        t.ok(length(filter(rules, (r) => r.server == "dnsmasq-server" && r.query_type != null && index(r.query_type, "PTR") >= 0)) > 0);
        let local_at = -1, bypass_at = -1;
        for (let i = 0; i < length(rules); i++) {
            if (rules[i].domain_suffix == ".internal.test" && local_at < 0) local_at = i;
            if (rules[i].server == "dns-server" && rules[i].domain_suffix != null && index(rules[i].domain_suffix, "internal.test") >= 0) bypass_at = i;
        }
        t.ok(local_at >= 0 && bypass_at > local_at, "explicit local zone precedes a section domain rule");
    }
});

t.test("foreign mwan marks do not skip system routing or DNS and are preserved when capturing", () => {
    fixture.seed({ section: [ { ".name": "p", action: "connection", fully_routed_ips: [ "@system" ] } ] });
    let script = nft.build().script;
    t.eq(index(script, "meta mark != 0 return"), -1);
    t.ok(index(script, "system_dns_redirect meta mark & 0x08000000 == 0x08000000 return") >= 0);
    t.ok(index(script, "meta mark set meta mark | 0x10000000") >= 0);
    t.ok(index(script, "mangle_output meta mark & 0x08000000 == 0x08000000 counter return") < index(script, "mangle_output jump priority_output_rules"));
    for (let foreign in [ 0, 0x100, 0x3f00, 0x80000000 ]) {
        t.eq((foreign & 0x08000000) == 0x08000000, false);
        t.eq(((foreign | 0x08000000) & 0x08000000) == 0x08000000, true);
        t.eq((foreign | 0x10000000) & foreign, foreign);
        t.eq((foreign | 0x04000000) & foreign, foreign);
    }
});

t.test("device scopes and paused sections never widen invalid selected sources to LAN", () => {
    for (let action in [ "bypass", "connection", "zapret2" ])
        for (let sources in [ [ "invalid" ], [ "" ], [ "192.0.2.7/32", "2001:db8::7/128" ], [] ]) {
            let section = { ".name": "scoped", action, source_ip_cidr: sources,
                destinations: "example.org\n203.0.113.0/24" };
            fixture.seed({ section: [ section, { ".name": "rest", action: "bypass", destinations: "rest.example" } ],
                connection_link: fixture.links("scoped", [ "socks://vpn.example:1080#VPN" ]) });
            let config = generator.build({ service_address: "127.0.0.1" });
            let scoped = filter(config.route.rules, (r) => (r.domain_suffix != null && index(r.domain_suffix, "example.org") >= 0));
            if (length(sources) > 0 && sources[0] != "192.0.2.7/32")
                t.eq(scoped, [], "invalid selected sources produce no unrestricted route");
            section.enabled = "0";
            fixture.seed({ section: [ section, { ".name": "rest", action: "bypass", destinations: "rest.example" } ] });
            config = generator.build({ service_address: "127.0.0.1" });
            t.eq(filter(config.dns.rules, (r) => r.domain_suffix != null && index(r.domain_suffix, "example.org") >= 0), []);
        }
});

t.test("an unsynchronized provider captures its source scope before an IP can escape core", () => {
    for (let action in [ "connection", "bypass" ]) {
        fixture.seed({ section: [ { ".name": "pending", action,
            source_ip_cidr: [ "192.0.2.7/32" ], rule_set: [ "https://rules.example/protected.srs" ] } ] });
        let script = nft.build().script;
        t.ok(index(script, "kabanmax_rule_pending_pending4 { 0.0.0.0/0 }") >= 0);
        t.ok(index(script, "kabanmax_rule_pending_pending6 { ::/0 }") >= 0);
        t.ok(index(script, "ip saddr @kabanmax_rule_pending_sources ip daddr != @localv4 ip daddr @kabanmax_rule_pending_pending4 meta mark set meta mark | 0x04000000") >= 0);
    }
});

t.done();
