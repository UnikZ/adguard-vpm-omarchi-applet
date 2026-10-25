// Pure parsing helpers for AdGuard VPN CLI output. No QML dependencies so
// every regex can be checked by eye against real CLI output:
//
// status (connected):
//   Connected to VILNIUS in SOCKS mode, listening on 127.0.0.1:1080
// status (disconnected):
//   VPN is disconnected
// config show:
//   Mode: tun|socks
//   SOCKS host: 127.0.0.1
//   SOCKS port: 1080

function stripAnsi(text) {
  // [0-9;?]* also covers private-mode CSI (e.g. "\x1b[?25l" cursor hide)
  return String(text || "").replace(/\x1b\[[0-9;?]*[A-Za-z]/g, "")
}

function elide(text) {
  var value = stripAnsi(text).replace(/\s+/g, " ").trim()
  return value.length > 140 ? value.substring(0, 139) + "…" : value
}

function parseStatus(raw) {
  var lines = stripAnsi(raw).split(/\r?\n/)
  var headline = ""
  var warnings = []
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (line === "") continue
    if (headline === "") headline = line
    else if (/warning/i.test(line)) warnings.push(line)
  }
  if (/^Connected to\b/i.test(headline)) {
    var match = headline.match(/^Connected to\s+(.+?)(?:\s+in\s+(SOCKS|TUN)\s+mode)?(?:\s*,?\s*listening on\s+(\S+))?$/i)
    var location = match ? String(match[1] || "").trim() : headline.replace(/^Connected to\s+/i, "").split(/\s+in\s+/)[0]
    return {
      ok: true,
      connected: true,
      location: location,
      mode: match ? String(match[2] || "").toLowerCase() : "",
      listen: match ? String(match[3] || "").trim() : "",
      warnings: warnings
    }
  }
  if (/disconnected/i.test(headline)) {
    return { ok: true, connected: false, location: "", mode: "", listen: "", warnings: warnings }
  }
  return { ok: false, connected: false, location: "", mode: "", listen: "", warnings: warnings, message: elide(headline) || "Unknown status" }
}

function parseConfig(raw) {
  var text = stripAnsi(raw)
  var mode = (text.match(/^\s*Mode:\s*(\S+)/m) || [])[1] || ""
  var host = (text.match(/^\s*SOCKS host:\s*(\S+)/m) || [])[1] || "127.0.0.1"
  var port = (text.match(/^\s*SOCKS port:\s*(\d+)/m) || [])[1] || "1080"
  return { mode: mode.toLowerCase(), proxyAddress: host + ":" + port }
}

function modeLabel(mode) {
  var value = String(mode || "").toLowerCase()
  if (value === "socks") return "SOCKS"
  if (value === "tun") return "TUN"
  return "—"
}

// AdGuard's login-required phrasings across CLI versions, collected from
// dms-adguard-vpn-plugin and docker-adguardvpn-cli.
function needsLogin(text) {
  return /not\s+logged\s+in|login\s+required|not\s+authorized|authentication\s+required|unauthorized|session\s+expired/i.test(String(text || ""))
}

// Command that exits 0 when the SOCKS listener accepts connections, or null
// when the address is not a safe host:port. bash /dev/tcp does the probing;
// `timeout` is the probe's own watchdog.
function listenProbe(hostPort) {
  var parts = String(hostPort || "").split(":")
  if (parts.length !== 2) return null
  var host = parts[0]
  var port = parseInt(parts[1], 10)
  if (!/^[0-9A-Za-z.]+$/.test(host) || !isFinite(port) || port <= 0 || port > 65535) return null
  return ["timeout", "2", "bash", "-c", "exec 3<>/dev/tcp/" + host + "/" + port]
}

// The same-city rule for both the idempotent-connect guard and the panel's
// active-row highlight: CLI status reports uppercase, the table title-case.
function sameCity(a, b) {
  return String(a || "").trim().toLowerCase() === String(b || "").trim().toLowerCase()
}

function containsCity(cities, city) {
  for (var i = 0; i < (cities || []).length; i++) {
    if (sameCity(cities[i], city)) return true
  }
  return false
}

// Favorites render as the intersection of stored city strings with the
// current list, in list order — which is already ping-sorted. Cities the
// list no longer carries simply don't render; storage keeps them forever.
function favoriteLocations(stored, locations) {
  var wanted = {}
  for (var i = 0; i < (stored || []).length; i++) wanted[String(stored[i] || "").trim().toLowerCase()] = true
  var out = []
  for (var j = 0; j < (locations || []).length; j++) {
    if (wanted[String(locations[j].city || "").trim().toLowerCase()]) out.push(locations[j])
  }
  return out
}

// The catalog shows everything not pinned as a favorite, so a city appears
// exactly once: either in the favorites block or in the list below it.
function nonFavoriteLocations(stored, locations) {
  var wanted = {}
  for (var i = 0; i < (stored || []).length; i++) wanted[String(stored[i] || "").trim().toLowerCase()] = true
  var out = []
  for (var j = 0; j < (locations || []).length; j++) {
    if (!wanted[String(locations[j].city || "").trim().toLowerCase()]) out.push(locations[j])
  }
  return out
}

// list-locations prints a fixed-width, ANSI-decorated table sorted by ping:
//   ISO   COUNTRY              CITY                           PING ESTIMATE
//   EE    Estonia              Tallinn                        3
// Column offsets: ISO 0-5, COUNTRY 6-26, CITY 27-57, PING 58+.
function parseLocations(raw) {
  var lines = stripAnsi(raw).split(/\r?\n/)
  var out = []
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (/^\s*ISO\b/.test(line)) continue
    if (line.replace(/\s/g, "").length === 0 || line.length < 28) continue
    // Only real table rows count: the CLI trails the table with a
    // "connect by running ..." hint that is long enough to look like a row.
    var iso = line.substring(0, 6).trim()
    if (!/^[A-Z]{2}$/.test(iso)) continue
    var country = line.substring(6, 27).trim()
    var city = line.substring(27, 58).trim()
    if (city === "" || country === "") continue
    var ping = parseInt(line.substring(58).trim(), 10)
    out.push({
      iso: iso,
      country: country,
      city: city,
      ping: isFinite(ping) ? ping : -1
    })
  }
  return out
}

// Node-only export for tests; `module` is undefined under Quickshell.
if (typeof module !== "undefined") {
  module.exports = { stripAnsi: stripAnsi, elide: elide, parseStatus: parseStatus, parseConfig: parseConfig, modeLabel: modeLabel, parseLocations: parseLocations, sameCity: sameCity, containsCity: containsCity, favoriteLocations: favoriteLocations, nonFavoriteLocations: nonFavoriteLocations, listenProbe: listenProbe, needsLogin: needsLogin }
}
