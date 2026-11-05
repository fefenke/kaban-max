// Install the original upstream embedded build, without running its firewall installer.
// Both engine and Lua come from the same verified release. No remittor dependency.
let fs = require("fs");
let common = require("core.common");
let exec = require("core.exec");
let lock = require("service.lock");
const ROOT = "/opt/forkop-zapret2";
const STATE = "/var/run/forkop-zapret2-update.json";
const LOCK = "/var/run/forkop-zapret2-update.lock";

function select_release(release) {
    let version = release.tag_name ?? "";
    if (match(version, /^v[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?$/) == null || release.prerelease || release.draft)
        die("No supported stable Zapret2 release was found");
    let name = "zapret2-" + version + "-openwrt-embedded.tar.gz";
    for (let asset in release.assets ?? []) {
        if (asset.name != name) continue;
        let url = "https://github.com/bol-van/zapret2/releases/download/" + version + "/" + name;
        if (asset.browser_download_url != url || match(asset.digest ?? "", /^sha256:[a-f0-9]{64}$/) == null)
            die("Zapret2 release has no verified download URL or SHA-256 digest");
        if (match(asset.url ?? "", /^https:\/\/api\.github\.com\/repos\/bol-van\/zapret2\/releases\/assets\/[0-9]+$/) == null)
            die("Zapret2 release has no trusted GitHub asset API URL");
        return { version, url: asset.url, digest: substr(asset.digest, 7) };
    }
    die("The Zapret2 release has no OpenWrt embedded archive");
}

function architecture(arch, machine) {
    if (match(arch, /^aarch64/) || machine == "aarch64") return "arm64";
    if (match(arch, /^arm/) || match(machine, /^arm/)) return "arm";
    if (match(arch, /^mips64/) && !match(arch, /^mips64el/)) return "mips64";
    if (match(arch, /^mipsel/)) return "mipsel";
    if (match(arch, /^mips_/) || machine == "mips") return "mips";
    if (arch == "x86_64" || machine == "x86_64") return "x86_64";
    if (match(arch, /^i[3-6]86/) || match(machine, /^i[3-6]86/)) return "x86";
    if (match(arch, /^riscv64/) || machine == "riscv64") return "riscv64";
    if (match(arch, /^powerpc/) || machine == "ppc") return "ppc";
    die("No official Zapret2 binary is supported for architecture " + arch + " (" + machine + ")");
}

function device_arch() {
    let found = match(fs.readfile("/etc/openwrt_release") ?? "", /DISTRIB_ARCH=['"]([^'"]+)['"]/);
    return architecture(found == null ? "" : found[1], trim(exec.output([ "uname", "-m" ]) ?? ""));
}

function fetch(url, path) {
    let headers = index(url, "/releases/assets/") >= 0 ? [ "--header=Accept: application/octet-stream" ] : [];
    let result = exec.combined([ "uclient-fetch", "-T", "45", ...headers, "-O", path, url ]);
    if (result.status != 0) die("Download failed: " + url + ": " + result.output);
}

function latest() {
    let path = "/tmp/forkop-zapret2-release." + common.own_pid() + ".json";
    try {
        fetch("https://api.github.com/repos/bol-van/zapret2/releases/latest", path);
        let release = select_release(json(fs.readfile(path)));
        fs.unlink(path);
        return release;
    }
    catch (e) { fs.unlink(path); die(e.message); }
}

function status() {
    let state = {};
    try { state = json(fs.readfile(STATE) ?? "{}"); } catch (e) {}
    return { ...state, installed: trim(fs.readfile(ROOT + "/current/version") ?? ""),
        running: lock.held(LOCK), architecture: device_arch() };
}

function write_state(state) {
    let tmp = STATE + ".tmp";
    if (fs.writefile(tmp, sprintf("%J", state)) == null || !fs.rename(tmp, STATE)) die("Could not write Zapret2 update state");
}

function start(action) {
    if (index([ "check", "install" ], action) < 0) die("Unknown Zapret2 update action");
    let owner = common.own_pid();
    if (!lock.acquire(LOCK, owner)) die("A Zapret2 update is already running");
    write_state({ running: true, success: null, message: "Checking the official Zapret2 release" });
    // The worker takes over this lock. It outlives LuCI's request and browser tab.
    if (!exec.background([ "/usr/bin/forkop", "zapret2_update_run", action ])) {
        lock.release(LOCK, owner);
        die("Could not launch the Zapret2 update worker");
    }
    for (let attempt = 0; attempt < 50; attempt++) {
        if (trim(fs.readfile(LOCK + "/pid") ?? "") != owner) return { running: lock.held(LOCK) };
        sleep(100);
    }
    lock.release(LOCK, owner);
    die("The Zapret2 update worker did not start");
}

function switch_to(target) {
    if (target == null) { fs.unlink(ROOT + "/current"); return; }
    fs.unlink(ROOT + "/next");
    if (!fs.symlink(target, ROOT + "/next") || !fs.rename(ROOT + "/next", ROOT + "/current"))
        die("Could not switch the Zapret2 release");
}

function activate(target, previous, running, ops) {
    ops = ops ?? {
        select: switch_to,
        stop: () => {
            if (!exec.ok([ "env", "FORKOP_ZAPRET2_UPDATING=1", "/etc/init.d/forkop", "stop" ])) die("Could not stop Forkop");
        },
        start: () => {
            if (!exec.ok([ "env", "FORKOP_ZAPRET2_UPDATING=1", "/etc/init.d/forkop", "start" ]) ||
                !require("service.health").sing_box_service_running()) die("Forkop failed to start with Zapret2");
        }
    };
    let stopped = false, changed = false;
    try {
        if (running) { stopped = true; ops.stop(); }
        ops.select(target); changed = true;
        if (running) ops.start();
    }
    catch (e) {
        try {
            if (changed) { ops.stop(); ops.select(previous); }
            if (stopped) ops.start();
        }
        catch (rollback) { die(e.message + "; rollback failed: " + rollback.message); }
        die(e.message);
    }
}

function runtime_permissions(path) {
    let info = fs.lstat(path);
    if (info == null) die("Missing staged Zapret2 path: " + path);
    if (info.type == "directory") {
        if (!fs.chmod(path, 0755)) die("Could not set Zapret2 directory permissions: " + path);
        for (let name in fs.lsdir(path) ?? []) runtime_permissions(path + "/" + name);
    }
    else if (info.type == "file") {
        if (!fs.chmod(path, 0644)) die("Could not set Zapret2 file permissions: " + path);
    }
    else die("Unexpected staged Zapret2 file type: " + path);
}

function install(release) {
    // Never overwrite another project's /opt/zapret2 or configuration.
    let opt_existed = fs.stat("/opt") != null;
    common.ensure_dir(ROOT + "/releases");
    if (!opt_existed && !fs.chmod("/opt", 0755)) die("Could not make the new /opt directory traversable");
    if ((fs.stat("/opt").mode & 0001) == 0) die("nfqws2 cannot traverse /opt after dropping privileges; grant execute permission on /opt before retrying");
    let stage = ROOT + "/releases/" + release.version + "." + common.own_pid();
    let archive = "/tmp/forkop-zapret2." + common.own_pid() + ".tar.gz";
    let old = fs.readlink(ROOT + "/current");
    let running = require("service.health").sing_box_service_running();
    try {
        fetch(release.url, archive);
        let hash = split(trim(exec.output([ "sha256sum", archive ]) ?? ""), /\s+/)[0];
        if (hash != release.digest) die("Zapret2 archive SHA-256 mismatch");
        let prefix = "zapret2-" + release.version + "/";
        let bin = prefix + "binaries/linux-" + device_arch() + "/nfqws2";
        let listing = split(exec.output([ "tar", "-tzf", archive ]) ?? "", "\n");
        if (index(listing, bin) < 0) die("Release has no binary for this router");
        let members = [bin];
        for (let member in listing)
            if (substr(member, 0, length(prefix)) == prefix &&
                match(substr(member, length(prefix)), /^(lua|files)\/[a-zA-Z0-9_.\/-]+$/) &&
                index(member, "..") < 0 && substr(member, -1) != "/") push(members, member);
        common.ensure_dir(stage + "/unpack");
        if (!exec.ok([ "tar", "-xzf", archive, "-C", stage + "/unpack", ...members ])) die("Could not unpack Zapret2");
        let source = stage + "/unpack/" + prefix;
        common.ensure_dir(stage + "/nfq2");
        if (!exec.ok([ "cp", source + "binaries/linux-" + device_arch() + "/nfqws2", stage + "/nfq2/nfqws2" ])) die("Could not stage nfqws2");
        fs.chmod(stage + "/nfq2/nfqws2", 0755);
        for (let dir in ["lua", "files"])
            if (fs.stat(source + dir) != null && !exec.ok([ "cp", "-R", source + dir, stage + "/" + dir ])) die("Could not stage " + dir);
        for (let file in fs.glob(stage + "/lua/*.gz") ?? [])
            if (!exec.ok([ "gzip", "-d", file ])) die("Could not decompress Zapret2 Lua");
        // rpcd may use umask 077. nfqws2 loads Lua after dropping root, so every
        // managed parent must be traversable and the staged assets readable.
        for (let dir in [ ROOT, ROOT + "/releases", stage, stage + "/nfq2" ])
            if (!fs.chmod(dir, 0755)) die("Could not set Zapret2 directory permissions: " + dir);
        for (let dir in [ "lua", "files" ])
            if (fs.stat(stage + "/" + dir) != null) runtime_permissions(stage + "/" + dir);
        let version = exec.combined([ stage + "/nfq2/nfqws2", "--version" ]);
        if (version.status != 0 || index(version.output, substr(release.version, 1)) < 0) die("The new nfqws2 binary does not run or has an unexpected version");
        for (let file in ["zapret-lib.lua", "zapret-antidpi.lua", "zapret-auto.lua"])
            if (!fs.access(stage + "/lua/" + file, "r")) die("Release is missing " + file);
        for (let instance in require("zapret2.model").instances(true)) {
            let argv = map(instance.argv, (arg) => replace(arg, ROOT + "/current", stage));
            let checked = exec.combined([ ...argv, "--dry-run" ]);
            if (checked.status != 0) die("New Zapret2 rejects section '" + instance.name + "': " + checked.output);
        }
        fs.writefile(stage + "/version", release.version + "\n");
        common.remove_tree(stage + "/unpack");
        // NFQUEUE kernel packages are persistent dependencies of the Forkop package.
        activate(stage, old, running);
        // Keep the active release and exactly one predecessor on flash.
        for (let path in fs.glob(ROOT + "/releases/*") ?? [])
            if (path != stage && path != old && match(path, /^\/opt\/forkop-zapret2\/releases\/v[0-9.]+\.[0-9]+$/))
                common.remove_tree(path);
    }
    catch (e) {
        // If rollback itself failed, keep the release that current still references.
        if (fs.readlink(ROOT + "/current") != stage) common.remove_tree(stage);
        fs.unlink(archive);
        die(e.message);
    }
    fs.unlink(archive);
}

function run(action) {
    let owner = common.own_pid();
    if (index([ "check", "install" ], action) < 0 || !lock.held(LOCK)) die("No valid Zapret2 update was requested");
    fs.writefile(LOCK + "/pid", owner + "\n");
    try {
        let release = latest();
        if (action == "install") {
            write_state({ running: true, latest: release.version, message: "Downloading and validating " + release.version });
            install(release);
        }
        write_state({ success: true, latest: release.version, message: action == "install" ? "Zapret2 installed: " + release.version : "Latest Zapret2: " + release.version });
        lock.release(LOCK, owner);
        return 0;
    }
    catch (e) { write_state({ success: false, message: e.message }); lock.release(LOCK, owner); return 1; }
}

return { select_release, architecture, status, start, run, activate };
