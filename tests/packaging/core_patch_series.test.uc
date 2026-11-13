let t = require("t");
let fs = require("fs");
let repo = require("repo");
let constants = require("core.constants");

t.test("the application minimum matches the pinned core package with Chrome 155 support", () => {
    let upstream = fs.readfile(repo.path("core/UPSTREAM"));
    let version = match(upstream, /package_version=([^\r\n]+)/)[1];
    t.eq(version, constants.SB_REQUIRED_VERSION);
    t.eq(constants.SB_REQUIRED_VERSION, "1.14.4-r9");
});

t.done();
