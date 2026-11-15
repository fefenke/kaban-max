// Synthetic fixtures shared with the offline tests of UPSTREAM+patches.
let fs = require("fs");
let fixture = require("fixture");
let generator = require("singbox.generator");
let output = getenv("KABANMAX_DNS_FIXTURES");
if (!output)
    die("KABANMAX_DNS_FIXTURES is required");

for (let mode in [ "policy", "provider", "srs-only", "ports", "priority", "detour-off", "resolve-all", "resolve-selected" ]) {
    let bypass = { ".name": "bypass", enabled: "1", action: "bypass",
        source_ip_cidr: [ "192.0.2.7/32" ], destinations: "192.0.2.0/24\n2001:db8::/32",
        rule_set_with_subnets: [ "/synthetic/mixed.srs" ] };
    if (mode == "srs-only")
        delete bypass.destinations;
    if (mode == "ports")
        bypass.ports = [ "443" ];
    let proxy = { ".name": "proxy", enabled: "1", action: "connection", destinations: "example.org",
        source_ip_cidr: [ "192.0.2.0/24" ] };
    fixture.seed({
        settings: { dns_server: "https://dns.example/dns-query", dns_detour_enabled: mode == "detour-off" ? "0" : "1", dns_detour_section: "proxy",
            pre_routing_resolve_mode: mode == "resolve-all" ? "all" : (mode == "resolve-selected" ? "selected" : "disabled"),
            pre_routing_resolve_domains: "example.org" },
        section: mode == "priority" ? [ proxy, bypass ] : [ bypass, proxy ],
        connection_link: mode == "provider" ? [] : fixture.links("proxy", [ "socks://vpn.example:1080#VPN" ]),
        subscription_url: mode == "provider" ? [ { ".name": "sub", section: "proxy", tag: "sub", url: "/synthetic/provider.txt" } ] : []
    });
    let config = generator.build({ service_address: "127.0.0.1" });
    if (!fs.writefile(output + "/" + mode + ".json", sprintf("%J", config)))
        die("cannot export " + mode);
}
