let t = require("t");
let fixture = require("fixture");
let q = require("sbconfig");
let generator = require("singbox.generator");

t.test("TLS record fragmentation belongs only to the selected manual server", () => {
    fixture.seed({
        settings: { dns_server: "1.1.1.1", service_listen_address: "127.0.0.1" },
        section: [ { ".name": "main", action: "connection", enabled: "1" } ],
        connection_link: [
            { ".name": "split", section: "main", name: "Split", uri: "vless://u@split.example:443?security=reality#Split", tls_record_fragment: "1" },
            { ".name": "plain", section: "main", name: "Plain", uri: "vless://u@plain.example:443?security=reality#Plain" },
            { ".name": "classic", section: "main", name: "Classic", uri: "vless://u@classic.example:443?security=reality#Classic", tls_classical: "1" },
            { ".name": "both", section: "main", name: "Both", uri: "vless://u@both.example:443?security=reality#Both", tls_classical: "1", tls_record_fragment: "1" },
            { ".name": "disabled", section: "main", name: "Disabled", uri: "vless://u@disabled.example:443?security=tls#Disabled", tls_record_fragment: "0" }
        ]
    });
    let config = generator.build({ service_address: "127.0.0.1" });
    t.eq(q.outbound(config, "main/Split").tls_record_fragment, true);
    t.eq(q.outbound(config, "main/Plain").tls_record_fragment, null);
    t.eq(q.outbound(config, "main/Disabled").tls_record_fragment, null);
    t.eq(q.outbound(config, "main/Split").tls_classical, null);
    t.eq(q.outbound(config, "main/Classic").tls_classical, true);
    t.eq(q.outbound(config, "main/Classic").tls_record_fragment, null);
    t.eq(q.outbound(config, "main/Plain").tls_classical, null);
    t.eq(q.outbound(config, "main/Both").tls_classical, true);
    t.eq(q.outbound(config, "main/Both").tls_record_fragment, true);
    t.eq(q.outbound(config, "main/Split").link, "vless://u@split.example:443?security=reality#Split");
});
t.test("fingerprint override belongs to its persistent item and preserves the URI", () => {
    let uri = "vless://u@same.example:443?security=tls&fp=firefox#Same";
    fixture.seed({ settings: { dns_server: "1.1.1.1" },
        section: [ { ".name": "main", action: "connection", enabled: "1" } ],
        connection_link: [
            { ".name": "first", section: "main", name: "Renamed", uri, tls_fingerprint: " Chrome_155 " },
            { ".name": "second", section: "main", name: "Same", uri }
        ] });
    let config = generator.build({ service_address: "127.0.0.1" });
    t.eq(q.outbound(config, "main/Renamed").tls_fingerprint, "chrome_155");
    t.eq(q.outbound(config, "main/Same").tls_fingerprint, null);
    t.eq(q.outbound(config, "main/Renamed").link, uri);
    t.eq(q.outbound(config, "main/Same").link, uri);
});

t.done();
