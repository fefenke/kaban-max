let fs = require("fs");
let exec = require("core.exec");
let paths = { modules: "/sys/module" };

// Checking only an already loaded module loses the dependency after an old
// package is removed: its code survives in memory until the next reboot.
// Packages declare both modules persistently; load them before privilege drop.
function load() {
    for (let module in [ "nfnetlink_queue", "nft_queue" ]) {
        if (fs.stat(paths.modules + "/" + module) != null) continue;
        if (!exec.ok([ "modprobe", module ]) || fs.stat(paths.modules + "/" + module) == null)
            die("Zapret2 needs kernel module " + module + ". Install kmod-nfnetlink-queue and kmod-nft-queue for this firmware, then retry");
    }
}

return { load, paths };
