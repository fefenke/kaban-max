let t = require("t");
let fs = require("fs");
let repo = require("repo");
let constants = require("core.constants");

t.test("the r43 package includes probe budgets and explicit protocol risk while the default minimum remains r10", () => {
    let upstream = fs.readfile(repo.path("core/UPSTREAM"));
    let version = match(upstream, /package_version=([^\r\n]+)/)[1];
    t.eq(version, "1.14.4-r46");
    t.ok(fs.stat(repo.path("core/patches/0041-late-dns-applied-routing.patch")) != null);
    t.ok(fs.stat(repo.path("core/patches/0042-runtime-failure-visibility.patch")) != null);
    t.ok(fs.stat(repo.path("core/patches/0043-auto-probe-budget-and-protocol-opt-in.patch")) != null);
    t.ok(fs.stat(repo.path("core/patches/0044-dial-only-fallback-health.patch")) != null);
    t.ok(fs.stat(repo.path("core/patches/0045-fallback-independent-health-success.patch")) != null);
    t.ok(fs.stat(repo.path("core/patches/0046-actionable-connection-context.patch")) != null);
    t.eq(constants.SB_REQUIRED_VERSION, "1.14.4-r10");
});

t.done();
