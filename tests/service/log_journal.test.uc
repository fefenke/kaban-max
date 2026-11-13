let t = require("t");
let journal = require("service.log_journal");

t.test("records survive system ring rotation and expire after 24 hours", () => {
    let log = journal.create({ max_age: 86400, max_bytes: 1024 });
    log.ingest([ "first", "second" ], 100);
    log.ingest([ "third" ], 101);
    t.eq(log.text(86499), "first\nsecond\nthird\n");
    t.eq(log.text(86500), "third\n");
    t.eq(log.text(86501), "");
});

t.test("size evicts oldest complete records even when younger than a day", () => {
    let log = journal.create({ max_age: 86400, max_bytes: 8 });
    log.ingest([ "aaa", "bbb", "ccc" ], 100);
    t.eq(log.text(101), "bbb\nccc\n");
    log.ingest([ "ccc", "oversized record" ], 102);
    t.eq(log.text(102), "");
});

t.test("clearing never imports existing system lines again, including after restore", () => {
    let log = journal.create();
    log.ingest([ "first", "same" ], 100);
    log.clear(101);
    let restored = journal.create(null, log.snapshot());
    restored.ingest([ "first", "same" ], 102);
    t.eq(restored.text(102), "");
    restored.ingest([ "first", "same", "same" ], 103);
    t.eq(restored.text(103), "same\n", "a repeated new line is retained");
});

t.test("expiry changes revision even with no new system lines", () => {
    let log = journal.create({ max_age: 10 });
    log.ingest([ "line" ], 100);
    let before = log.revision();
    log.prune(110);
    t.ok(log.revision() > before);
    t.eq(log.text(110), "");
});

t.test("restore keeps timestamps instead of granting an additional day", () => {
    let log = journal.create({ max_age: 10 });
    log.ingest([ "line" ], 100);
    let restored = journal.create({ max_age: 10 }, log.snapshot());
    t.eq(restored.text(109), "line\n");
    t.eq(restored.text(110), "");
});

t.test("cleared and expired text is absent from persisted deduplication metadata", () => {
    let log = journal.create({ max_age: 10 });
    log.ingest([ "private-record-to-remove" ], 100);
    log.clear(101);
    t.excludes(sprintf("%J", log.snapshot()), "private-record-to-remove");
    log.ingest([ "private-record-to-remove", "another-private-record" ], 102);
    log.prune(112);
    t.excludes(sprintf("%J", log.snapshot()), "another-private-record");
});

t.test("a bounded fingerprint window does not reimport a large unchanged or repeated system dump", () => {
    let lines = [];
    for (let i = 0; i < 300; i++)
        push(lines, "same");
    let log = journal.create();
    log.ingest(lines, 100);
    log.clear(101);
    let restored = journal.create(null, log.snapshot());
    restored.ingest(lines, 102);
    t.eq(restored.text(102), "");
    restored.ingest([ ...lines, "same" ], 103);
    t.eq(restored.text(103), "same\n");
    t.ok(length(restored.snapshot().previous) <= 128);
});

t.test("the serialized archive limit includes JSON overhead and deduplication metadata", () => {
    let log = journal.create({ max_storage_bytes: 8192 });
    let lines = [];
    for (let i = 0; i < 80; i++)
        push(lines, sprintf("record %d: quoted \"value\" with slash \\ and unicode текст, long enough to fill storage", i));
    log.ingest(lines, 100);
    t.ok(length(sprintf("%J", log.snapshot())) <= 8192);
    t.excludes(log.text(101), "record 0:");
    t.contains(log.text(101), "record 79:");
});

t.done();
