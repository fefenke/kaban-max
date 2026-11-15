// Offline forecast of the generated configuration, NOT an active core route API.
// Unknown matchers stop evaluation. Never use this forecast to authorize probes.
let ip = require("core.ip");
let domain = require("config.domain");
let common = require("core.common");

function values(value) {
    return value == null ? [] : type(value) == "array" ? value : [value];
}

function address_match(prefix, address) {
    if (address == "") return null;
    if (!ip.valid_ip(address)) return null;
    if (ip.valid_ip(prefix))
        return join(".", iptoarr(prefix)) == join(".", iptoarr(address));
    return ip.valid_ip_cidr(prefix) ? ip.prefix_contains(prefix, address) : null;
}

function any_match(items, fn) {
    items = values(items);
    if (length(items) == 0 || length(items) > 256) return null;
    let unknown = false;
    for (let item in items) {
        let result = fn(item);
        if (result === true) return true;
        if (result == null) unknown = true;
    }
    return unknown ? null : false;
}

function combine(items, mode) {
    let unknown = false;
    for (let item in items) {
        if (mode == "and" && item === false) return false;
        if (mode == "or" && item === true) return true;
        if (item == null) unknown = true;
    }
    return unknown ? null : mode == "and";
}

function rule_match(rule, q, depth, budget) {
    if (type(rule) != "object" || depth > 8 || budget.left-- <= 0) return null;
    let parts = [];
    let domain_parts = [];
    let has_ip = rule.ip_cidr != null;
    let has_domain = false;
    // Destination matchers may be ORed by core. A nonmatching known domain/IP
    // cannot disprove an opaque SRS/regex branch in the same rule.
    let opaque = false;
    for (let key in keys(rule))
        if (index(["action", "outbound", "server", "type", "mode", "rules", "invert", "override_port", "override_address", "source_ip_cidr", "ip_cidr", "port", "port_range", "network", "inbound", "domain", "domain_suffix", "domain_keyword"], key) < 0)
            opaque = true;
    for (let key, value in rule) {
        if (index(["action", "outbound", "server", "type", "mode", "rules", "invert"], key) >= 0) continue;
        let result = null;
        if (key == "source_ip_cidr")
            result = any_match(value, (prefix) => q.source == "@system" ? null : address_match(prefix, q.source));
        else if (key == "ip_cidr")
            result = opaque ? null : any_match(value, (prefix) => address_match(prefix, q.address));
        else if (key == "port")
            result = any_match(value, (port) => type(port) == "int" ? port == q.port : null);
        else if (key == "port_range")
            result = any_match(value, (range) => {
                let m = type(range) == "string" ? match(range, /^([0-9]+):([0-9]+)$/) : null;
                return m ? q.port >= int(m[1]) && q.port <= int(m[2]) : null;
            });
        else if (key == "network")
            result = any_match(value, (network) => network == "tcp");
        else if (key == "inbound") {
            let matches = map(q.inbounds, (inbound) => index(values(value), inbound) >= 0);
            result = index(matches, true) < 0 ? false : index(matches, false) < 0 ? true : null;
        }
        else if (index(["domain", "domain_suffix", "domain_keyword"], key) >= 0) {
            has_domain = true;
            result = any_match(value, (pattern) => {
                if (q.domain == "") return null; // An IP may acquire a domain through sniff/reverse mapping.
                if (type(pattern) != "string") return null;
                pattern = lc(pattern);
                if (key == "domain") return q.domain == pattern;
                if (key == "domain_keyword") return index(q.domain, pattern) >= 0;
                if (substr(pattern, 0, 1) == ".") pattern = substr(pattern, 1);
                return q.domain == pattern || (length(q.domain) > length(pattern) &&
                    substr(q.domain, length(q.domain) - length(pattern) - 1) == "." + pattern);
            });
            push(domain_parts, result);
            continue;
        }
        // Regex, rule sets, GeoIP, protocol, private-IP, interface and future fields
        // need core state/semantics. Do not execute user regex in this read RPC.
        push(parts, result);
    }
    if (has_domain) push(parts, opaque ? null : combine(domain_parts, "or"));
    if (has_domain && has_ip) return null;
    if (rule.type != null && rule.type != "logical") push(parts, null);
    if (rule.type == "logical") {
        if (index(["and", "or"], rule.mode) < 0 || type(rule.rules) != "array" || length(rule.rules) == 0 || length(rule.rules) > 256)
            push(parts, null);
        else push(parts, combine(map(rule.rules, (child) => rule_match(child, q, depth + 1, budget)), rule.mode));
    }
    let result = combine(parts, "and");
    return rule.invert === true && result != null ? !result : result;
}

function parse_query(query) {
    if (type(query) != "object") return null;
    let destination = common.as_string(query.destination);
    let source = common.as_string(query.source);
    let port = common.as_string(query.port ?? "443");
    if (length(destination) > 253 || !match(port, /^[1-9][0-9]{0,4}$/) || int(port) > 65535 ||
        (source != "" && source != "@system" && !ip.valid_ip(source))) return null;
    let address = ip.valid_ip(destination) ? destination : "";
    if (address == "" && substr(destination, -1) == ".") destination = substr(destination, 0, length(destination) - 1);
    let name = address == "" ? domain.suffix_to_ascii(destination) : "";
    if (address == "" && (name == null || name == "" || substr(name, 0, 1) == "." || match(name, /(^|\.)[0-9]+$/))) return null;
    let inbounds = source == "@system" ? ["system-in", "system6-in"] :
        source == "" ? ["tproxy-in", "tproxy6-in", "system-in", "system6-in"] : ["tproxy-in", "tproxy6-in"];
    return { destination, address, domain: name ?? "", source, port: int(port), inbounds };
}

function predict(config, query) {
    let result = {
        predicted: { status: "unknown", reason: "runtime_config_unavailable" },
        observed: { status: "unavailable", reason: "config_file_is_not_live_egress_evidence" },
        verified: { status: "not_run", requests: 0 },
        dns: { status: "not_queried", reason: "read_only_no_resolution" },
        automation: { status: "unsupported", reason: "r10_probe_evidence_unavailable" },
        assumptions: ["non-DNS TCP", "generated config forecast only; nft/PBR and live core state are not verified"]
    };
    let q = parse_query(query);
    if (q == null) {
        result.predicted = { status: "invalid_input", reason: "expected_domain_or_ip_source_and_port" };
        return result;
    }
    if (q.address != "" && (ip.prefix_contains("198.18.0.0/15", q.address) || ip.prefix_contains("fc00::/18", q.address))) {
        result.predicted = { status: "unknown", reason: "fakeip_requires_core_mapping" };
        return result;
    }
    if (type(config?.route?.rules) != "array") return result;
    let rules = config.route.rules;
    if (length(rules) > 1024) {
        result.predicted.reason = "rule_budget_exceeded";
        return result;
    }
    let budget = { left: 4096 };
    for (let i = 0; i < length(rules); i++) {
        let rule = rules[i];
        // Initial sniff supplies metadata only; the caller explicitly gives the
        // destination to forecast. DNS traffic is outside this tool's contract.
        if (rule.action == "sniff" || (rule.action == "hijack-dns" && q.port != 53)) continue;
        let matched = rule_match(rule, q, 0, budget);
        if (matched === false) continue;
        let unknown = (reason) => { result.predicted = { status: "unknown", reason, rule_index: i }; return result; };
        if (matched == null) return unknown("matcher_requires_core_state");
        if (rule.action == "resolve" && q.address != "") continue;
        if (rule.action == "route" && type(rule.outbound) == "string" && rule.outbound != "") {
            result.predicted = { status: "predicted", action: "route", outbound: rule.outbound, rule_index: i };
            return result;
        }
        if (rule.action == "reject") {
            result.predicted = { status: "predicted", action: "reject", rule_index: i };
            return result;
        }
        return unknown("action_requires_core_state");
    }
    if (type(config.route.final) == "string" && config.route.final != "")
        result.predicted = { status: "predicted", action: "route", outbound: config.route.final, reason: "final" };
    return result;
}

function inspect(destination, source, port) {
    let uci = require("core.uci");
    let settings = uci.get_all("kabanmax", "settings") ?? {};
    let config = common.read_json_file(require("singbox.constants").config_path(settings));
    return predict(config, { destination, source, port: port || "443" });
}

return { predict, inspect };
