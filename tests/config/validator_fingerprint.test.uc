let t = require("t");
let v = require("validation");
let fingerprints = require("singbox.fingerprints");

function config(uri, fingerprint) {
    return { section: [ { ".name": "main", action: "connection", enabled: "1" } ],
        connection_link: [ { ".name": "server1", section: "main", name: "Same", uri, tls_fingerprint: fingerprint } ] };
}

t.test("every catalog fingerprint is accepted over TCP TLS and guarded for REALITY", () => {
    for (let profile in fingerprints) {
        v.accepts(config("vless://u@a.example:443?security=tls", profile.id));
        if (profile.reality == "unsupported")
            v.refuses(config("vless://u@a.example:443?security=reality", profile.id), "TLS fingerprint requires");
        else
            v.accepts(config("vless://u@a.example:443?security=reality", profile.id));
    }
});

t.test("REALITY inferred by a public key has the same fingerprint limits", () => {
    v.refuses(config("vless://u@a.example:443?security=tls&pbk=key", "android"), "TLS fingerprint requires");
    v.refuses(config("vless://u@a.example:443?security=tls&pbk=key", "360"), "TLS fingerprint requires");
    v.accepts(config("vless://u@a.example:443?security=tls&pbk=key", "randomized"));
});
t.test("fingerprint override validates TLS capabilities and known names", () => {
    v.accepts(config("vless://u@a.example:443?security=tls", " Chrome_155 "));
    v.accepts(config("trojan://p@a.example:443", "firefox"));
    v.accepts(config("vless://u@a.example:443?security=tls", "android"));
    v.refuses(config("vless://u@a.example:443?security=reality", "android"), "TLS fingerprint requires a supported TCP connection with TLS enabled");
    v.accepts(config("socks://a.example:1080", ""));
    v.refuses(config("vless://u@a.example:443?security=tls", "unknown"), "Unsupported TLS fingerprint");
    v.refuses(config("vless://u@a.example:443?security=tls", "chrome_155"), "with a TLS fingerprint override", { core_tags: [ "with_clash_api" ] });
    for (let uri in [ "socks://a.example:1080", "vless://u@a.example:443", "http://a.example:80?security=tls", "trojan://p@a.example:443?security=none", "vless://u@a.example:443?pbk=key", "tuic://u:p@a.example:443", "vless://u@a.example:443?security=tls&type=xhttp&alpn=h3" ])
        v.refuses(config(uri, "chrome_155"), "TLS fingerprint requires a supported TCP connection with TLS enabled");
});
t.done();
