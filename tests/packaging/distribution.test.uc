let t = require("t");
let fs = require("fs");
let installer = fs.readfile("../install.sh");
t.test("the public installer keeps backend and patched core in our release", () => {
    t.ok(index(installer, "FORKOP_REPO=fefenke/kaban-max") >= 0, "backend uses our repository");
    t.ok(index(installer, "CORE_REPO=fefenke/kaban-max") >= 0, "core uses our repository");
    t.ok(index(installer, "core-release.json") >= 0, "core has its own manifest");
    t.ok(index(installer, "KABANMAX_RELEASE") >= 0, "prerelease pin is supported");
});
t.done();
