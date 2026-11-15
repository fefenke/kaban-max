// IP-first observations. Logs and generic Clash snapshots never prove the
// original winning Zapret rule; attribution comes separately from core events.
let ip = require("core.ip");
let common = require("core.common");

function log_candidate(line, now) {
    if (type(line) != "string" || length(line) > 4096 || !match(line, /timeout|timed out|failed|refused|reset|unreachable|no route|EOF/)) return null;
    let m = match(line, /(dial|connect|connection to) (tcp|udp)?[ \t]*\[([0-9a-fA-F:]+)\]:([0-9]+)/);
    if (m == null) m = match(line, /(dial|connect|connection to) (tcp|udp)?[ \t]*([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+):([0-9]+)/);
    if (m == null || !ip.valid_ip(m[3]) || int(m[4]) < 1 || int(m[4]) > 65535) return null;
    return { ip: m[3], port: int(m[4]), domain: "", network: m[2] ?? "unknown", source_ip: "", source: "", status: "unattributed",
        reason: "log_has_no_trusted_first_match", timestamp: now, count: 1 };
}

function stalled(previous, connections, now) {
    let tracked = {}, events = [];
    for (let conn in connections) {
        if (length(tracked) >= 128) break;
        let meta = conn.metadata ?? {};
        if (!ip.valid_ip(meta.destinationIP) || conn.id == null) continue;
        let signature = sprintf("%J", [meta.destinationIP, meta.destinationPort, meta.sourceIP, meta.host, meta.network]);
        let old = previous[conn.id];
        let item = { signature, progress: now, download: int(conn.download ?? 0), emitted: false };
        if (old?.signature == signature && old.download == item.download) { item.progress = old.progress; item.emitted = old.emitted; }
        if (!item.emitted && meta.network == "tcp" && int(conn.upload ?? 0) > 0 && now - item.progress >= 15) {
            push(events, { ip: meta.destinationIP, port: int(meta.destinationPort), domain: common.as_string(meta.host), network: meta.network,
                source_ip: common.as_string(meta.sourceIP), source: "", status: "unattributed", reason: "no_progress_without_trusted_first_match", timestamp: now, count: 1 });
            item.emitted = true;
        }
        tracked[conn.id] = item;
    }
    return { tracked, events };
}
return { log_candidate, stalled };
