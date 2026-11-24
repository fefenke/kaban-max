let t = require("t");
let fixture = require("fixture");
let generator = require("singbox.generator");
let q = require("sbconfig");

function build(proxy, credentials, extra) {
    fixture.seed({
        settings: fixture.settings({ warp_profiles_via_proxy: proxy ? "1" : "0", warp_profiles_via_proxy_section: "api", ...(extra ?? {}) }),
        section: [
            { ".name": "api", enabled: "1", action: "connection", outbound_jsons: [ '{"type":"direct"}' ] },
            { ".name": "vpn", enabled: "1", action: "connection" }
        ],
        tunnel: map([ "first", "second" ], (name) => ({
            ".name": name, section: "vpn", kind: "warp", name,
            ...(credentials ? { warp_profile_id: name, warp_profile_auth_token: "test-token", warp_profile_private_key: "test-key-" + name } : {}),
            amnezia_jc: "4", amnezia_jmin: "10", amnezia_jmax: "20", amnezia_i1: "<r 2>"
        }))
    });
    return generator.build({ service_address: "127.0.0.1" });
}

for (let proxy in [ false, true ]) {
    for (let credentials in [ false, true ]) {
        let through = proxy;
        let supplied = credentials;
        t.test("WARP API uses a core dialer, proxy=" + through + " credentials=" + supplied, () => {
            let config = build(through, supplied);
            for (let name in [ "first", "second" ]) {
                let endpoint = q.endpoint(config, "vpn/" + name);
                t.eq(endpoint.profile?.detour, through ? "api" : "direct-out");
                t.eq(endpoint.profile?.id, supplied ? name : null);
                t.eq(endpoint.detour, null, "API routing does not change the tunnel transport");
                t.eq(endpoint.amnezia, { jc: 4, jmin: 10, jmax: 20, i1: "<r 2>" });
            }
            t.eq(config.route.default_mark, require("singbox.constants").OUTBOUND_MARK);
        });
    }
}

t.test("WARP API bootstrap does not depend on DNS through this same WARP", () => {
    for (let via_proxy in [ false, true ]) {
        let config = build(via_proxy, false, { dns_detour_enabled: "1", dns_detour_section: "vpn" });
        for (let name in [ "first", "second" ]) {
            let endpoint = q.endpoint(config, "vpn/" + name);
            t.eq(endpoint.domain_resolver, "bootstrap-dns-server");
            t.eq(endpoint.profile.detour, via_proxy ? "api" : "infrastructure-direct-out");
            t.eq(endpoint.detour, null);
        }
        t.eq(q.outbound(config, "infrastructure-direct-out").domain_resolver, "bootstrap-dns-server");
        t.eq(config.route.default_domain_resolver, "dns-server");
    }
});

t.test("durable local port belongs to the generated WARP profile and is a soft hint", () => {
    fixture.seed({ settings: fixture.settings(), section: [{".name":"vpn", enabled:"1", action:"connection"}], tunnel: [
        {".name":"first", section:"vpn", kind:"warp", name:"first", warp_port:"2408", warp_profile_id:"p1", warp_profile_auth_token:"t", warp_profile_private_key:"k", warp_local_port_hint:"42000", warp_local_port_profile:"p1"},
        {".name":"second", section:"vpn", kind:"warp", name:"second", warp_profile_id:"p2", warp_profile_auth_token:"t", warp_profile_private_key:"k2", warp_local_port_hint:"43000", warp_local_port_profile:"old-profile"}
    ] });
    let config = generator.build({service_address:"127.0.0.1"});
    let first = q.endpoint(config,"vpn/first");
    t.eq(first.listen_port_hint,42000); t.eq(first.listen_port,null); t.eq(first.port,2408);
    t.eq(q.endpoint(config,"vpn/second").listen_port_hint,null);
});
t.done();
