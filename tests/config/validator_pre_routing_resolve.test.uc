let t = require("t");
let v = require("validation");
function data(settings) {
    return { settings, section: [ { ".name": "direct", enabled: "1", action: "bypass", destinations: "example.org" } ] };
}
t.test("invalid mode is refused", () => {
    v.refuses(data({ pre_routing_resolve_mode: "typo" }), "Unsupported pre-routing resolve mode");
});
t.test("selected never becomes resolve all on an empty list", () => {
    v.refuses(data({ pre_routing_resolve_mode: "selected", pre_routing_resolve_domains: "# comment" }), "at least one domain");
});
t.test("only exact and suffix domains are accepted", () => {
    for (let value in [ "192.0.2.1", "keyword:example", "regex:.*", "https://example.org", "example..org" ])
        v.refuses(data({ pre_routing_resolve_mode: "selected", pre_routing_resolve_domains: value }), "Invalid pre-routing resolve domain");
    v.accepts(data({ pre_routing_resolve_mode: "selected", pre_routing_resolve_domains: "example.org\nfull:only.example" }));
});
t.done();
