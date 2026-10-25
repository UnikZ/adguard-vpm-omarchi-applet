// Parser tests against real AdGuard VPN CLI output shapes (see Model.js
// header). Run: node --test tests/
const test = require("node:test")
const assert = require("node:assert")
const Model = require("../Model.js")

test("stripAnsi removes escape sequences", () => {
  assert.strictEqual(Model.stripAnsi("\x1b[?25lConnected\x1b[0m"), "Connected")
  assert.strictEqual(Model.stripAnsi(""), "")
})

test("elide collapses whitespace and truncates", () => {
  assert.strictEqual(Model.elide("a   b\n\tc"), "a b c")
  assert.ok(Model.elide("x".repeat(200)).length <= 140)
  assert.ok(Model.elide("x".repeat(200)).endsWith("…"))
})

test("parseStatus connected with mode and listener", () => {
  const r = Model.parseStatus("Connected to VILNIUS in SOCKS mode, listening on 127.0.0.1:1080")
  assert.deepStrictEqual([r.ok, r.connected], [true, true])
  assert.strictEqual(r.location, "VILNIUS")
  assert.strictEqual(r.mode, "socks")
  assert.strictEqual(r.listen, "127.0.0.1:1080")
})

test("parseStatus connected bare (no mode/listen)", () => {
  const r = Model.parseStatus("Connected to VILNIUS")
  assert.deepStrictEqual([r.ok, r.connected, r.location], [true, true, "VILNIUS"])
  assert.strictEqual(r.mode, "")
})

test("parseStatus disconnected", () => {
  const r = Model.parseStatus("VPN is disconnected")
  assert.deepStrictEqual([r.ok, r.connected], [true, false])
})

test("parseStatus collects warnings and rejects garbage", () => {
  const r = Model.parseStatus("VPN is disconnected\nWarning: something\nnoise")
  assert.deepStrictEqual(r.warnings, ["Warning: something"])
  const bad = Model.parseStatus("Total gibberish")
  assert.strictEqual(bad.ok, false)
  assert.ok(bad.message.length > 0)
})

test("parseConfig reads mode and SOCKS address, defaults when absent", () => {
  const r = Model.parseConfig("Mode: socks\nSOCKS host: 192.168.1.2\nSOCKS port: 9050")
  assert.deepStrictEqual(r, { mode: "socks", proxyAddress: "192.168.1.2:9050" })
  const d = Model.parseConfig("")
  assert.deepStrictEqual(d, { mode: "", proxyAddress: "127.0.0.1:1080" })
})

test("modeLabel maps known modes", () => {
  assert.strictEqual(Model.modeLabel("SOCKS"), "SOCKS")
  assert.strictEqual(Model.modeLabel("tun"), "TUN")
  assert.strictEqual(Model.modeLabel(""), "—")
})

test("sameCity matches across case and nulls", () => {
  assert.strictEqual(Model.sameCity("VILNIUS", " Vilnius "), true)
  assert.strictEqual(Model.sameCity("Vilnius", "Tallinn"), false)
  assert.strictEqual(Model.sameCity(null, ""), true)
})

test("listenProbe builds the /dev/tcp probe and rejects unsafe addresses", () => {
  assert.deepStrictEqual(Model.listenProbe("127.0.0.1:1080"), [
    "timeout", "2", "bash", "-c", "exec 3<>/dev/tcp/127.0.0.1/1080"
  ])
  assert.strictEqual(Model.listenProbe("127.0.0.1"), null)
  assert.strictEqual(Model.listenProbe("evil`host:1080"), null)
  assert.strictEqual(Model.listenProbe("127.0.0.1:0"), null)
  assert.strictEqual(Model.listenProbe("127.0.0.1:70000"), null)
  assert.strictEqual(Model.listenProbe(""), null)
})

test("favoriteLocations intersects by city, keeping list (ping) order", () => {
  const locs = [
    { iso: "EE", country: "Estonia", city: "Tallinn", ping: 3 },
    { iso: "LT", country: "Lithuania", city: "Vilnius", ping: 8 },
    { iso: "JP", country: "Japan", city: "Tokyo", ping: 120 }
  ]
  assert.deepStrictEqual(Model.favoriteLocations(["vilnius ", "Atlantis"], locs), [locs[1]])
  assert.deepStrictEqual(Model.favoriteLocations([], locs), [])
  assert.deepStrictEqual(Model.favoriteLocations(["TOKYO"], locs), [locs[2]])
})

test("nonFavoriteLocations is the exact complement", () => {
  const locs = [
    { iso: "EE", country: "Estonia", city: "Tallinn", ping: 3 },
    { iso: "LT", country: "Lithuania", city: "Vilnius", ping: 8 },
    { iso: "JP", country: "Japan", city: "Tokyo", ping: 120 }
  ]
  const stored = ["vilnius ", "Atlantis"]
  assert.deepStrictEqual(Model.nonFavoriteLocations(stored, locs), [locs[0], locs[2]])
  const favs = Model.favoriteLocations(stored, locs).concat(Model.nonFavoriteLocations(stored, locs))
  assert.deepStrictEqual(favs.sort((a, b) => a.ping - b.ping), locs)
})

test("containsCity matches like sameCity and tolerates null", () => {
  assert.strictEqual(Model.containsCity(["VILNIUS"], " Vilnius "), true)
  assert.strictEqual(Model.containsCity(["Vilnius"], "Tokyo"), false)
  assert.strictEqual(Model.containsCity(null, "Tokyo"), false)
})

test("parseLocations slices the fixed-width table", () => {
  const raw = [
    "ISO   COUNTRY              CITY                           PING ESTIMATE",
    "EE    Estonia              Tallinn                        3",
    "US    United States        New York                       42",
    "",
    "short",
    "You can connect to a location by running `/opt/adguardvpn_cli/adguardvpn-cli connect -l 'city'`"
  ].join("\n")
  const locs = Model.parseLocations(raw)
  assert.strictEqual(locs.length, 2)
  assert.deepStrictEqual(locs[0], { iso: "EE", country: "Estonia", city: "Tallinn", ping: 3 })
  assert.strictEqual(locs[1].ping, 42)
})

test("parseLocations marks missing ping as -1", () => {
  // Build the line with the documented column widths: ISO 0-5, COUNTRY 6-26, CITY 27-57
  const line = "DE".padEnd(6) + "Germany".padEnd(21) + "Frankfurt"
  const locs = Model.parseLocations(line)
  assert.deepStrictEqual(locs[0], { iso: "DE", country: "Germany", city: "Frankfurt", ping: -1 })
})
