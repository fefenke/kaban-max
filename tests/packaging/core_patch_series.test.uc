let t = require("t");
let fs = require("fs");
let repo = require("repo");
let constants = require("core.constants");

t.test("the r39 package includes section-wide applied IP routes while the default minimum remains r10", () => {
    let upstream = fs.readfile(repo.path("core/UPSTREAM"));
    let version = match(upstream, /package_version=([^\r\n]+)/)[1];
    t.eq(version, "1.14.4-r40");
    t.eq(constants.SB_REQUIRED_VERSION, "1.14.4-r10");
});

t.done();
