// A separate table survives removal of the main table during package upgrades.
let exec = require("core.exec");
let constants = require("core.constants");
const TABLE = "KabanMaxDnsTransition";
const SOURCE = constants.NFT_TABLE_NAME;

function snapshot_set(name, optional) {
    let reply = exec.capture([ "nft", "-j", "list", "set", "inet", SOURCE, name ], 262144);
    if (reply.status != 0) {
        if (optional) return null;
        die("Cannot snapshot the DNS capture interfaces before update");
    }
    let document = json(reply.stdout);
    for (let entry in document.nftables ?? [])
        if (entry.set?.name == name && entry.set?.table == SOURCE && entry.set?.family == "inet")
            return entry.set;
    die("Invalid DNS capture snapshot before update");
}

function build(snapshot) {
    if (type(snapshot.interfaces) != "object" || type(snapshot.interfaces.elem ?? []) != "array")
        die("Missing DNS capture interface snapshot");
    let commands = [ { add: { table: { family: "inet", name: TABLE } } } ];
    for (let pair in [ [ "interfaces", snapshot.interfaces ], [ "excluded4", snapshot.excluded4 ], [ "excluded6", snapshot.excluded6 ] ]) {
        if (pair[1] == null) continue;
        let source = pair[1];
        let set = { family: "inet", table: TABLE, name: pair[0], type: source.type, elem: source.elem ?? [] };
        if (source.flags != null) set.flags = source.flags;
        if (source["auto-merge"] != null) set["auto-merge"] = source["auto-merge"];
        push(commands, { add: { set } });
    }
    push(commands, { add: { chain: { family: "inet", table: TABLE, name: "dns", type: "filter", hook: "prerouting", prio: -152, policy: "accept" } } });
    for (let pair in [ [ "ip", "excluded4" ], [ "ip6", "excluded6" ] ])
        if (snapshot[pair[1]] != null)
            push(commands, { add: { rule: { family: "inet", table: TABLE, chain: "dns", expr: [
                { match: { op: "==", left: { payload: { protocol: pair[0], field: "saddr" } }, right: "@" + pair[1] } },
                { return: null }
            ] } } });
    for (let protocol in [ "tcp", "udp" ])
        push(commands, { add: { rule: { family: "inet", table: TABLE, chain: "dns", expr: [
            { match: { op: "==", left: { ct: { key: "direction" } }, right: "original" } },
            { match: { op: "==", left: { meta: { key: "iifname" } }, right: "@interfaces" } },
            { match: { op: "==", left: { payload: { protocol, field: "dport" } }, right: 53 } },
            { drop: null }
        ] } } });
    return { nftables: commands };
}

function begin() {
    if (!exec.ok([ "nft", "list", "table", "inet", SOURCE ])) return true;
    if (exec.ok([ "nft", "list", "table", "inet", TABLE ]))
        die("A DNS transition guard is already active");
    let document = build({
        interfaces: snapshot_set(constants.NFT_INTERFACE_SET_NAME, false),
        excluded4: snapshot_set("kabanmax_excluded", true),
        excluded6: snapshot_set("kabanmax_excluded6", true)
    });
    let result = exec.feed([ "nft", "-j", "-f", "-" ], sprintf("%J", document));
    if (result.status != 0)
        die("Cannot protect client DNS before stopping KabanMax: " + result.stderr);
    return true;
}

return { build, begin };
