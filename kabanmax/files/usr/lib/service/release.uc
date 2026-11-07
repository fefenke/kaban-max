let fs = require("fs");
let common = require("core.common");
let exec = require("core.exec");
let constants = require("core.constants");
let packages = require("core.packages");
let versions = require("core.version");

function valid_tag(value) {
    return type(value) == "string" && match(value, /^[0-9]+\.[0-9]+\.[0-9]+$/) != null;
}

function valid_manifest(value, name, tag) {
    return type(value) == "object" && value.schema === 1 && value.name == name &&
        valid_tag(value.tag) && value.tag == tag && type(value.version) == "string" &&
        (name == "kabanmax" ? valid_tag(value.version) : packages.kabanmax_core_version(value.version) != "");
}

// A private, unique file; uclient-fetch bounds connect/request time, ulimit bounds bytes on disk.
// OpenWrt does not necessarily ship the standalone timeout applet.
// Neither remote error bodies nor download URLs are returned to the page or the log.
function fetch_json(url, asset, expected_type) {
    let now = clock();
    let path = sprintf("/tmp/kabanmax-release.%d.%d.%d", common.own_pid(), now[0], now[1]);
    let argv = [ "uclient-fetch", "-q", "-T", "15", ...(asset ? [ "--header=Accept: application/octet-stream" ] : []), "-O", path, url ];
    let status = exec.status([ "sh", "-c", "umask 077; ulimit -f 1024; exec \"$@\"", "sh", ...argv ]);
    let data = status == 0 ? fs.readfile(path, 1048576) : null;
    fs.unlink(path);
    if (data == null)
        die("Cannot download release information; check the router internet connection or GitHub rate limit and retry");
    let value = common.parse_json(data);
    if (type(value) != (expected_type || "object"))
        die("Invalid release information");
    return value;
}

function asset_url(listing, file) {
    for (let asset in (type(listing?.assets) == "array" ? listing.assets : []))
        if (asset?.name == file && type(asset.url) == "string" &&
            index(asset.url, "https://api.github.com/repos/" + constants.KABANMAX_RELEASE_REPO + "/releases/assets/") == 0)
            return asset.url;
    die("Selected release is missing " + file);
}

function evaluate(app, core, tag, installed, core_installed) {
    if (!valid_manifest(app, "kabanmax", tag) || !valid_manifest(core, "sing-box-kabanmax", tag) || app.install_command)
        die("Selected release metadata is invalid or requires a console installation");
    if (versions.version_compare(app.version, installed) < 0 ||
        (core_installed != "" && versions.version_compare(core.version, core_installed) < 0))
        die("Latest release would downgrade an installed component; use the console to select a release");
    let update_available = versions.version_compare(app.version, installed) > 0 ||
        core_installed == "" || versions.version_compare(core.version, core_installed) > 0;
    return { installed, latest: app.version, release: tag, core_installed, core_latest: core.version,
        update_available, message: update_available ? "An update is available" : "KabanMax and its core are up to date" };
}

// GitHub's /latest excludes prereleases. This project publishes numeric tags on
// that channel too, so select the highest supported tag from the bounded listing.
function select_release(listing) {
    if (type(listing) != "array")
        die("Invalid release listing");
    let selected = null;
    for (let item in listing) {
        if (type(item) != "object" || item.draft === true || !valid_tag(item.tag_name))
            continue;
        if (selected == null || versions.version_compare(item.tag_name, selected.tag_name) > 0)
            selected = item;
    }
    if (selected == null)
        die("No supported published KabanMax release was found");
    return selected;
}

function check() {
    let url = "https://api.github.com/repos/" + constants.KABANMAX_RELEASE_REPO + "/releases?per_page=30";
    let mirror = getenv("KABANMAX_DOWNLOAD_URL");
    let listing = select_release(fetch_json(url, false, "array"));
    let tag = listing.tag_name;
    let manifest = (file) => mirror
        ? fetch_json(mirror + "/" + constants.KABANMAX_RELEASE_REPO + "/releases/download/" + tag + "/" + file, false)
        : fetch_json(asset_url(listing, file), true);
    // Both transports must refer to the same complete, selected release.
    for (let file in [ "install.sh", "release.json", "core-release.json" ])
        asset_url(listing, file);
    return { ...evaluate(manifest("release.json"), manifest("core-release.json"), tag,
        constants.KABANMAX_VERSION, packages.sing_box_version()), prerelease: listing.prerelease === true };
}

return { valid_tag, valid_manifest, select_release, evaluate, check };
