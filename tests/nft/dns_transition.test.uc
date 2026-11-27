let t = require("t");
let stub = require("stub");
let guard = require("nft.dns_transition");

let interfaces = { type: "ifname", flags: [ "interval" ], elem: [ "br-test" ] };

t.test("guard is independent of the service table and preserves exclusions", function() {
    let commands = guard.build({ interfaces, excluded4: { type: "ipv4_addr", flags: [ "interval" ], elem: [ "192.0.2.7" ] }, excluded6: null }).nftables;
    t.eq(commands[0].add.table.name, "KabanMaxDnsTransition");
    t.eq(commands[1].add.set.elem, [ "br-test" ]);
    let chain = filter(commands, (c) => c.add?.chain)[0].add.chain;
    t.eq([ chain.hook, chain.prio, chain.policy ], [ "prerouting", -152, "accept" ]);
    let rules = map(filter(commands, (c) => c.add?.rule), (c) => c.add.rule.expr);
    t.eq(rules[0][-1], { return: null });
    t.eq(length(rules), 3);
    for (let rule in slice(rules, 1)) {
        t.eq(rule[0].match.right, "original");
        t.eq(rule[1].match.right, "@interfaces");
        t.eq(rule[2].match.right, 53);
        t.eq(rule[-1], { drop: null });
    }
});

t.test("absent service table does not create a guard", function() {
    stub.commands([ [ "nft list table", { status: 1 } ] ]);
    t.ok(guard.begin());
    t.eq(length(filter(stub.calls(), (c) => index(c.argv, "-f") >= 0)), 0);
    stub.restore();
});

t.test("failed snapshot cannot create a partial guard", function() {
    stub.commands([ [ "nft list table inet KabanMaxTable", {} ], [ "nft list table", { status: 1 } ], [ "nft -j list set", { status: 1 } ] ]);
    t.throws(() => guard.begin());
    t.eq(length(filter(stub.calls(), (c) => index(c.argv, "-f") >= 0)), 0);
    stub.restore();
});

t.test("active capture snapshot is installed as one independent transaction", function() {
    let set = { family: "inet", table: "KabanMaxTable", name: "kabanmax_interfaces", type: "ifname", elem: [ "br-test" ] };
    stub.commands([
        [ "nft list table inet KabanMaxTable", {} ],
        [ "nft list table", { status: 1 } ],
        [ "nft -j list set inet KabanMaxTable kabanmax_interfaces", { stdout: sprintf("%J", { nftables: [ { set } ] }) } ],
        [ "nft -j list set", { status: 1 } ],
        [ "nft -j -f", {} ]
    ]);
    t.ok(guard.begin());
    let calls = filter(stub.calls(), (c) => index(c.argv, "-f") >= 0);
    t.eq(length(calls), 1);
    t.eq(json(calls[0].stdin).nftables[0].add.table.name, "KabanMaxDnsTransition");
    stub.restore();
});

t.done();
