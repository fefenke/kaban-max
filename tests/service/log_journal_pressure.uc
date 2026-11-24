// Local synthetic replay only; never generates network traffic or router logs.
let fs = require("fs");
let journal = require("service.log_journal").create();
function seconds() { let now = clock(); return now[0] + now[1] / 1000000000; }
let started = seconds();
for (let round = 0; round < 80; round++) {
    let lines = [];
    for (let i = 0; i < 200; i++)
        push(lines, sprintf("Mon Nov 23 12:00:00 2026 daemon.err sing-box[123]: DEBUG[%d] synthetic connection diagnostic event", round * 200 + i));
    journal.ingest(lines, 100 + round);
    // Match the state service's archive write and the Logs tab's text read.
    let archive = sprintf("%J", journal.snapshot());
    let text = journal.text(100 + round);
}
print(sprintf("elapsed_seconds=%.3f records=%d text_bytes=%d archive_bytes=%d\n", seconds() - started,
    length(journal.snapshot().entries), length(journal.text(180)), length(sprintf("%J", journal.snapshot()))));
print(match(fs.readfile("/proc/self/status"), /VmHWM:[^\n]*/)?.[0], "\n");
