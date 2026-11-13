// Bounded journal independent of logd's circular buffer. Timestamps describe when
// a record was collected; restoring an archive never renews its retention period.
// Two bounded rolling fingerprints identify overlap, not authenticate records.
// Persisting fingerprints prevents deleted plaintext living in dedup metadata.
function fingerprint(line) {
    let a = 5381;
    let b = 2166136261;
    for (let i = 0; i < length(line); i++) {
        let byte = ord(substr(line, i, 1));
        a = (a * 33 + byte) % 4294967291;
        b = (b * 65599 + byte) % 4294967279;
    }
    return sprintf("%d:%d:%d", length(line), a, b);
}

function create(options, saved) {
    options = options ?? {};
    let max_age = options.max_age ?? 86400;
    let max_bytes = options.max_bytes ?? 2097152;
    let max_storage_bytes = options.max_storage_bytes ?? 2097152;
    let entries = type(saved?.entries) == "array" ? saved.entries : [];
    let previous = type(saved?.previous) == "array" ? saved.previous : [];
    if (saved?.version != 2)
        previous = map(previous, fingerprint);
    previous = slice(previous, length(previous) > 128 ? length(previous) - 128 : 0);
    let previous_count = int(saved?.previous_count ?? length(previous));
    let previous_digest = saved?.previous_digest ?? "";
    let revision = int(saved?.revision ?? 0);

    function prune(now) {
        let retained = [];
        let bytes = 0;
        let stored = length(sprintf("%J", previous)) + 256;
        for (let entry in entries) {
            if (type(entry.line) != "string" || type(entry.at) != "int" || entry.at <= now - max_age)
                continue;
            push(retained, entry);
            bytes += length(entry.line) + 1;
            stored += length(sprintf("%J", entry)) + 2;
        }
        let first = 0;
        while ((bytes > max_bytes || stored > max_storage_bytes) && first < length(retained)) {
            bytes -= length(retained[first].line) + 1;
            stored -= length(sprintf("%J", retained[first])) + 2;
            first++;
        }
        retained = slice(retained, first);
        let changed = length(retained) != length(entries);
        if (changed)
            revision++;
        entries = retained;
        return changed;
    }

    function ingest(lines, now) {
        // Compare the prior dump and then its bounded suffix window. Fingerprints
        // survive clear/expiry so an unchanged system dump is never reimported.
        let hashes = map(lines, fingerprint);
        let digest = fingerprint(join("\n", hashes));
        let overlap = length(previous) < length(lines) ? length(previous) : length(lines);
        let end = 0;
        if (previous_count > 0 && length(hashes) >= previous_count &&
            fingerprint(join("\n", slice(hashes, 0, previous_count))) == previous_digest)
            end = previous_count;
        for (; end == 0 && overlap > 0; overlap--) {
            // The bounded prior window can start inside a larger system dump.
            for (let start = 0; start <= length(lines) - overlap; start++) {
                let same = true;
                for (let i = 0; i < overlap; i++)
                    if (previous[length(previous) - overlap + i] != hashes[start + i]) {
                        same = false;
                        break;
                    }
                if (same) {
                    end = start + overlap;
                    break;
                }
            }
            if (end > 0)
                break;
        }
        let fresh = slice(lines, end);
        previous = slice(hashes, length(hashes) > 128 ? length(hashes) - 128 : 0);
        previous_count = length(hashes);
        previous_digest = digest;
        for (let line in fresh)
            push(entries, { at: now, line });
        if (length(fresh) > 0)
            revision++;
        prune(now);
        return fresh;
    }

    return {
        ingest,
        prune,
        clear: function(now) { entries = []; revision++; },
        revision: function() { return revision; },
        text: function(now) {
            prune(now);
            return length(entries) ? join("\n", map(entries, (entry) => entry.line)) + "\n" : "";
        },
        snapshot: function() { return { version: 2, entries, previous, previous_count, previous_digest, revision }; }
    };
}

return { create };
