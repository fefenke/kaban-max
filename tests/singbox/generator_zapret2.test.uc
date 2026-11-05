let t = require("t");
let fixture = require("fixture");
let generator = require("singbox.generator");
let nft = require("nft.apply");

t.test("zapret2 routes through distinct marked direct outbounds and queues", () => {
    fixture.seed({ settings: fixture.settings(), section: [
        { ".name": "off", action: "zapret2", enabled: "0" },
        { ".name": "yt", action: "zapret2", destinations: "youtube.com" },
        { ".name": "dc", action: "zapret2", destinations: "discord.com" }
    ] });
    let config = generator.build({ service_address: "127.0.0.1" });
    let outbounds = filter(config.outbounds, (o) => o.routing_mark != null);
    t.eq(map(outbounds, (o) => [o.tag, o.type, o.routing_mark]), [
        ["yt", "direct", 0x02000001], ["dc", "direct", 0x02000002]
    ]);
    let script = nft.build().script;
    t.ok(index(script, "meta mark 0x02000001 meta l4proto { tcp, udp } counter queue num 4300 bypass") >= 0);
    t.ok(index(script, "meta mark 0x02000002 meta l4proto { tcp, udp } counter queue num 4301 bypass") >= 0);
    t.ok(index(script, "0x40000000") >= 0, "desync packets must not be recaptured");
    t.ok(index(script, "ct direction reply ct mark & 0x020001ff == 0x02000001") >= 0,
        "nfqws2 sees replies as well as requests, for its connection tracking and adaptive strategies");
});
t.done();
