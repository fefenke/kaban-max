// Bounded journal independent of logd's circular buffer. Timestamps describe when
// a record was collected; restoring an archive never renews its retention period.
// Two bounded rolling fingerprints identify overlap, not authenticate records.
// Persisting fingerprints prevents deleted plaintext living in dedup metadata.
function fingerprint(line) {
    let a = 5381;
    let b = 2166136261;
    for (let i = 0; i < length(line); i++) {
        let byte = ord(line, i);
        a = (a * 33 + byte) % 4294967291;
        b = (b * 65599 + byte) % 4294967279;
    }
    return sprintf("%d:%d:%d", length(line), a, b);
}

function create(options, saved) {
    options = options ?? {};
    let hash = options.fingerprint ?? fingerprint;
    // Transient snapshot only; never persisted in archive/dedup metadata.
    let last_dump = null;
    let recent_hashes = {};
    let max_age = options.max_age ?? 86400;
    let max_bytes = options.max_bytes ?? 262144;
    let max_storage_bytes = options.max_storage_bytes ?? 524288;
    let max_entries = options.max_entries ?? 2048;
    let max_line_bytes = options.max_line_bytes ?? 2048;
    function bounded_line(line) {
        if (length(line) <= max_line_bytes) return line;
        let end = max_line_bytes - length(" [truncated]");
        while (end > 0 && (ord(line, end) & 192) == 128) end--;
        return substr(line, 0, end) + " [truncated]";
    }
    // Bound object count independently of payload bytes, including legacy restores.
    let source = type(saved?.entries) == "array" ? saved.entries : [];
    let restore_changed = length(source) > max_entries;
    let entries = [];
    let sizes = [];
    let bytes = 0;
    let stored = 0;
    for (let i = max(0, length(source) - max_entries); i < length(source); i++) {
        let entry = source[i];
        if (type(entry.line) != "string" || type(entry.at) != "int") { restore_changed = true; continue; }
        let retained = { at: entry.at, line: bounded_line(entry.line) };
        if (retained.line != entry.line) restore_changed = true;
        let size = length(sprintf("%J", retained)) + 2;
        push(entries, retained);
        push(sizes, size);
        bytes += length(retained.line) + 1;
        stored += size;
    }
    source = null;
    let previous = type(saved?.previous) == "array" ? saved.previous : [];
    if (saved?.version != 2)
        previous = map(previous, fingerprint);
    previous = slice(previous, length(previous) > 128 ? length(previous) - 128 : 0);
    let previous_count = int(saved?.previous_count ?? length(previous));
    let previous_digest = saved?.previous_digest ?? "";
    let revision = int(saved?.revision ?? 0) + (restore_changed ? 1 : 0);

    function prune(now) {
        let overhead = length(sprintf("%J", previous)) + 256;
        let first = 0;
        while (first < length(entries) && (entries[first].at <= now - max_age ||
               bytes > max_bytes || stored + overhead > max_storage_bytes || length(entries) - first > max_entries)) {
            bytes -= length(entries[first].line) + 1;
            stored -= sizes[first];
            first++;
        }
        if (first > 0) {
            entries = slice(entries, first);
            sizes = slice(sizes, first);
            revision++;
        }
        return first > 0;
    }

    function ingest(lines, now) {
        lines = map(lines, bounded_line);
        let dump = join("\n", lines);
        if (last_dump != null && dump == last_dump) {
            prune(now);
            return [];
        }
        // Compare the prior dump and then its bounded suffix window. Fingerprints
        // survive clear/expiry so an unchanged system dump is never reimported.
        let next_hashes = {};
        let hashes = [];
        for(let i=0;i<length(lines);i++) {
            let line=lines[i];let value=recent_hashes[line] ?? hash(line);
            push(hashes,value);
            // RAM only, bounded by the collected tail; never serialize plaintext
            // into persisted dedup metadata after clear/expiry.
            if(i>=length(lines)-1024)next_hashes[line]=value;
        }
        recent_hashes=next_hashes;
        let digest = hash(join("\n", hashes));
        let overlap = length(previous) < length(lines) ? length(previous) : length(lines);
        let end = 0;
        if (previous_count > 0 && length(hashes) >= previous_count &&
            hash(join("\n", slice(hashes, 0, previous_count))) == previous_digest)
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
        last_dump = dump;
        for (let line in fresh) {
            let entry = { at: now, line };
            let size = length(sprintf("%J", entry)) + 2;
            push(entries, entry);
            push(sizes, size);
            bytes += length(line) + 1;
            stored += size;
            // Evict during admission, not after building an oversized batch heap.
            if (length(entries) > max_entries + 128 || bytes > max_bytes + 65536)
                prune(now);
        }
        if (length(fresh) > 0)
            revision++;
        prune(now);
        return fresh;
    }

    prune(0);
    return {
        ingest,
        prune,
        clear: function(now) { entries = []; sizes = []; bytes = 0; stored = 0; revision++; },
        revision: function() { return revision; },
        text: function(now) {
            prune(now);
            return length(entries) ? join("\n", map(entries, (entry) => entry.line)) + "\n" : "";
        },
        snapshot: function() { return { version: 2, entries, previous, previous_count, previous_digest, revision }; }
    };
}

return { create };
