let t = require("t");
let fs = require("fs");
let stub = require("stub");
let kernel = require("zapret2.kernel");
let repo = require("repo");

t.test("NFQUEUE is a persistent package dependency, even when old modules are still loaded", () => {
    for (let file in [ "kabanmax/Makefile", "build.sh" ])
        for (let dependency in [ "kmod-nfnetlink-queue", "kmod-nft-queue" ])
            t.ok(index(fs.readfile(repo.path(file)), dependency) >= 0, file + ": " + dependency);
});
t.test("missing queue modules are loaded before starting userspace workers", () => {
    let dir = stub.tmpdir();
    kernel.paths.modules = dir;
    stub.commands([
        [ "modprobe nfnetlink_queue", () => { fs.mkdir(dir + "/nfnetlink_queue"); return {}; } ],
        [ "modprobe nft_queue", () => { fs.mkdir(dir + "/nft_queue"); return {}; } ]
    ]);
    kernel.load();
    t.eq(stub.command_lines(), [ "modprobe nfnetlink_queue", "modprobe nft_queue" ]);
    stub.restore();
    stub.commands([]);
    kernel.load();
    t.eq(stub.command_lines(), [], "loaded modules do not need reloading");
    stub.restore();
});
t.test("an absent module gives a package instruction instead of a worker respawn loop", () => {
    kernel.paths.modules = stub.tmpdir();
    stub.commands([ [ "modprobe nfnetlink_queue", { status: 1 } ] ]);
    t.contains(t.throws(() => kernel.load()).message, "kmod-nfnetlink-queue");
    stub.restore();
});
t.done();
