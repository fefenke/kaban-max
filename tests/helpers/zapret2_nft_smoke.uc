// Run from repo root with tests/fakes, tests/lib and kabanmax/files/usr/lib in -L.
// The resulting script can be checked by nft -c in an isolated network namespace.
require("fixture").seed({ settings: require("fixture").settings(), section: [
    { ".name": "https", action: "zapret2", destinations: "youtube.com", fully_routed_ips: [ "192.168.1.10" ] },
    { ".name": "subnet", action: "zapret2", destinations: "203.0.113.0/24", ports: "443" }
] });
print(require("nft.apply").build().script);
