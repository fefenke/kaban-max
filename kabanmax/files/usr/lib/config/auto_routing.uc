let common = require("core.common");
let connections = require("config.connections");
let domains = require("config.domain");
let ip = require("core.ip");
let url = require("core.url");
let uci = require("core.uci");
let paths = { suppression: "/etc/kabanmax/auto-routing-suppression.json" };
function valid_scope(text) {
    if (type(text) != "string" || length(text) > 1024) return false;
    let key = common.parse_json(text);
    return type(key) == "array" && length(key) == 6 && type(key[0]) == "string" && key[0] != "" &&
        ip.valid_ip(key[1]) && type(key[2]) == "string" && (key[2] == "" || domains.suffix_to_ascii(key[2]) != null) &&
        ip.valid_ip(key[3]) && index(["tproxy-in", "tproxy6-in", "system-in", "system6-in"], key[4]) >= 0 &&
        type(key[5]) == "int" && key[5] >= 1 && key[5] <= 65535;
}
function suppression() {
    let staged=require("config.auto_registry").pending("excluded");
    let raw = staged!=null ? sprintf("%J",{version:1,entries:staged}) : require("fs").readfile(paths.suppression);
    if (raw == null) return { version: 1, entries: [] };
    let value = common.parse_json(raw);
    if (type(value) != "object" || value.version != 1 || type(value.entries) != "array") die("Automatic routing suppression store is corrupt");
    for (let entry in value.entries)
        if (entry?.owner != "auto-routing" || !valid_scope(entry.scope)) die("Automatic routing suppression ownership or scope is corrupt");
    return {version:1,entries:require("config.auto_storage").entries("excluded",value.entries)};
}

function contract(section) {
    let raw = common.option(section, "auto_routing_contract", "");
    let value = raw == "" ? { mode: "web", path: "/", port: 443, status: 200 } : common.parse_json(raw);
    if (type(value) != "object") die("Automatic routing requires an explicit HTTPS application contract");
    let mode = value.mode ?? "strict";
    if (mode != "strict" && mode != "web") die("Invalid automatic routing verification mode");
    let domain = mode == "web" && (value.domain == null || value.domain == "") ? "" : domains.suffix_to_ascii(value.domain);
    let port = common.as_string(value.port);
    if (domain == null || substr(domain, 0, 1) == "." || ip.valid_ip(domain) || match(domain, /(^|\.)[0-9]+$/) ||
        type(value.path) != "string" || !match(value.path, /^\/[^\r\n#]*$/) || substr(value.path, 0, 2) == "//" || length(value.path) > 1024 ||
        !match(port, /^[1-9][0-9]{0,4}$/) || int(port) > 65535 || type(value.status) != "int" || value.status < 200 || value.status > 299 ||
        (mode == "strict" && (type(value.prefix) != "string" || length(value.prefix) == 0)) ||
        (value.prefix != null && (type(value.prefix) != "string" || length(value.prefix) > 128)))
        die("Invalid automatic routing application contract (domain/path/port/status/prefix)");
    if (mode == "web" && (value.failure_status != null || value.failure_prefix != null)) die("Ordinary HTTPS cannot define a nonce failure contract");
    if (value.failure_status != null && (type(value.failure_status) != "int" || value.failure_status < 400 || value.failure_status > 599 ||
        type(value.failure_prefix) != "string" || value.failure_prefix == "" || value.failure_prefix == value.prefix || length(value.failure_prefix) > 128))
        die("Invalid explicit failure contract");
    return { mode, domain, path: value.path, port: int(port), status: value.status, prefix: value.prefix ?? "",
        failure_status: value.failure_status ?? 0, failure_prefix: value.failure_prefix ?? "" };
}

// Collect only identified infrastructure. Dynamic subscriptions and opaque URI
// formats require a future core inventory; they must not silently weaken guard.
function protected_hosts(config) {
    if (length(keys(config.providers ?? {})) > 0)
        die("Automatic routing cannot verify infrastructure endpoints of dynamic subscriptions");
    let result = [];
    function add(host) {
        if (type(host) != "string" || host == "") return;
        if (!ip.valid_ip(host) && domains.suffix_to_ascii(host) == null)
            die("Automatic routing infrastructure endpoint is opaque");
        if (index(result, host) < 0) push(result, host);
        if (length(result) > 32) die("Automatic routing infrastructure inventory exceeds 32 endpoints");
    }
    function walk(value, depth) {
        if (depth > 12) die("Automatic routing infrastructure inventory exceeds depth limit");
        if (type(value) == "array") { for (let item in value) walk(item, depth + 1); return; }
        if (type(value) != "object") return;
        for (let key, item in value) {
            if (key == "server" || key == "server_address") add(item);
            else if (key == "link") {
                let host = url.host(item);
                if (host == "" || (url.scheme(item) == "vmess")) die("Automatic routing cannot inventory this URI format");
                add(host);
            }
            else if (type(item) == "object" || type(item) == "array") walk(item, depth + 1);
        }
    }
    walk(config.outbounds ?? [], 0); walk(config.endpoints ?? [], 0);
    for (let endpoint in config.endpoints ?? [])
        if (endpoint.type == "warp") { add("engage.cloudflareclient.com"); add("api.cloudflareclient.com"); }
    return result;
}

function warp_output(config, tag, trail) {
    trail=trail ?? [];
    if(tag=="" || length(trail)>8 || index(trail,tag)>=0)return false;
    let node=filter([...(config.outbounds ?? []),...(config.endpoints ?? [])],(n)=>n.tag==tag)[0];
    if(node==null)return false;
    if(node.type=="warp") {
        // Registration API routing is independent of the WARP data transport.
        if(node.detour==null || node.detour=="")return true;
        let transport=filter(config.outbounds ?? [],(n)=>n.tag==node.detour)[0];
        return transport?.type=="direct" && (transport.detour==null || transport.detour=="");
    }
    if(index(["selector","fallback","urltest"],node.type)<0 || length(node.providers ?? [])>0 || node.use_all_providers==true)return false;
    let members=[...(node.outbounds ?? [])];
    for(let group in node.groups ?? [])members=[...members,...(group.outbounds ?? [])];
    if(length(members)==0)return false;
    for(let member in members)if(!warp_output(config,member,[...trail,tag]))return false;
    return true;
}
function warp_sections(config, sections, tag_for_section) {
    return map(filter(sections,(s)=>common.bool_option(s,"enabled",true) && warp_output(config,tag_for_section(s[".name"]))),(s)=>({id:s[".name"],name:connections.section_display_name(s[".name"]),outbound:tag_for_section(s[".name"])}));
}
function sources(config, sections, tag_for_section) {
    let storage=require("config.auto_storage").settings();
    let pending=common.read_json_file(require("diagnostics.auto_routing").paths.pending) ?? [];
    // Upgrade from cores whose private checkpoint did not yet include results.
    // The installer preparation may preserve the old core's bounded snapshot.
    let pending_path=require("diagnostics.auto_routing").paths.pending;
    let legacy_checks=type(pending_path)=="string" ? common.read_json_file(pending_path+".checks") : null;
    if(type(legacy_checks)=="array")pending=map(pending,(row)=>{
        if(row.check_result!=null)return row;
        let matches=filter(legacy_checks,(d)=>d.owner=="auto-routing" && d.source_id==row.source_id && d.source==row.source && d.failure?.id==row.id && d.ip==row.ip && d.source_ip==row.source_ip && d.inbound==row.inbound && d.port==row.port && d.domain==row.domain);
        sort(matches,(a,b)=>common.as_string(a.created)>common.as_string(b.created) ? -1 : 1);
        if(length(matches)==0)return row;
        let checked=matches[0];
        if(checked.status=="expired" && checked.reason=="check_expired" && checked.target!=null && length(filter(checked.attempts ?? [],(a)=>a.outbound==checked.target && a.status=="verified"))>=2)
            checked={...checked,status:"proposed",reason:"retained_verified_alternative"};
        return {...row,check_result:checked};
    });
    let saved=require("config.auto_registry").load().entries;
    let enabled = filter(sections, (s) => common.option(s, "action", "") == "zapret2" && (common.bool_option(s, "auto_routing_enabled", false) || length(filter(saved,(e)=>common.parse_json(e.scope)[0]==s[".name"]))>0 || length(filter(pending,(e)=>e.source_id==s[".name"]))>0));
    if (length(enabled) == 0) return [];
    if (common.as_string(config.experimental?.clash_api?.secret) == "") {
        if(length(filter(enabled,(s)=>common.bool_option(s,"auto_routing_enabled",false)))==0)return [];
        die("Automatic routing requires an authenticated Clash API (Dashboard secret key)");
    }
    function safe_dns_egress(tag, depth) {
        if (depth > 8) return false;
        let candidates = [...(config.outbounds ?? []), ...(config.endpoints ?? [])];
        let node = filter(candidates, (item) => item.tag == tag)[0];
        if (node == null) return false;
        if (node.type == "direct") return node.detour == null || node.detour == "";
        if (node.type == "warp") {
            for (let detour in [node.detour, node.profile?.detour])
                if (detour != null && detour != "" && !safe_dns_egress(detour, depth + 1)) return false;
            return true;
        }
        if (node.type == "selector" && length(node.outbounds ?? []) > 0) {
            for (let member in node.outbounds) if (!safe_dns_egress(member, depth + 1)) return false;
            return true;
        }
        return false;
    }
    for (let server in config.dns?.servers ?? [])
        if (server.tag == "dns-server" && server.detour != null && server.detour != "" && !safe_dns_egress(server.detour, 0))
            die("Automatic routing refuses main DNS through VPS or an opaque/Fallback/URLTest egress; DNS settings are unchanged");
    let protected = protected_hosts(config);
    let excluded = connections.excluded_devices(uci.get_all("kabanmax", "settings") ?? {});
    let suppressed = [];
    for (let entry in suppression().entries) {
        if (entry?.owner == "auto-routing" && type(entry.scope) == "string") push(suppressed, entry.scope);
    }
    let result = [];
    for (let section in enabled) {
        if (common.option(section, "action", "") != "zapret2") die("Automatic routing can only start from a Zapret2 section");
        let warp = "";
        let warp_section = "";
        if(common.bool_option(section,"auto_routing_use_warp",true)) {
            warp_section=common.option(section,"auto_routing_warp_section","");
            if(warp_section!="") {
                let selected=filter(sections,(s)=>s[".name"]==warp_section && common.bool_option(s,"enabled",true))[0];
                if(selected==null)die("Automatic routing target section is unavailable");
                warp=tag_for_section(warp_section);
                if(!warp_output(config,warp))die("Automatic routing target section must use WARP without VPN detour");
            }
        }
        if (length(tag_for_section(section[".name"])) > 128) die("Automatic routing section names must not exceed 128 bytes");
        if (warp == "" && common.bool_option(section,"auto_routing_use_warp",true) && common.option(section,"auto_routing_warp","")!="") {
            warp=common.option(section,"auto_routing_warp","");
            let endpoint = filter(config.endpoints ?? [], (e) => e.tag == warp && e.type == "warp")[0];
            if (endpoint == null || (endpoint.detour != null && endpoint.detour != "direct-out"))
                die("Automatic routing WARP must be a concrete profile without VPN detour");
            for (let parent in sections) {
                let tunnels = connections.tunnel_items(parent);
                for (let i = 0; i < length(tunnels); i++)
                    if (require("singbox.constants").child_tag(tag_for_section(parent[".name"]), connections.tunnel_display_name(tunnels[i], i + 1)) == warp)
                        warp_section = parent[".name"];
            }
            if(warp_section!="" && warp_output(config,tag_for_section(warp_section)))warp=tag_for_section(warp_section);
        }
        push(result, { ...contract(section), id: section[".name"], outbound: tag_for_section(section[".name"]),
            memory_bytes:storage.memory_bytes,cleanup_seconds:storage.cleanup_seconds,
            collect_disabled: !common.bool_option(section,"auto_routing_enabled",false),
            pending: filter(pending,(e)=>e.source_id==section[".name"]),
            saved: map(filter(saved,(e)=>common.parse_json(e.scope)[0]==section[".name"] && index(suppressed,e.scope)<0 && index(suppressed,require("config.auto_registry").key({...e.record,domain:""}))<0),(e)=>e.record),
            registry_scopes: map(filter(saved,(e)=>common.parse_json(e.scope)[0]==section[".name"]),(e)=>e.scope),
            direct_section: common.option(section, "auto_routing_direct_section", ""),
            warp_section,
            excluded_sources: excluded.addresses, excluded_system: excluded.router,
            mark: require("zapret2.model").mark(section[".name"]),
            probe_zapret: common.bool_option(section, "auto_routing_probe_zapret", true),
            direct: common.bool_option(section, "auto_routing_direct", false), warp,
            auto_apply: common.bool_option(section, "auto_routing_apply", false),
            allow_ip_only: common.bool_option(section,"auto_routing_apply",false) && common.bool_option(section,"auto_routing_ip_only",false), protected, suppressed });
    }
    return result;
}
return { contract, sources, warp_sections, warp_output, protected_hosts, suppression, valid_scope, paths };
