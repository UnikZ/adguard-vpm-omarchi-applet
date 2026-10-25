import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})

  // The official installer drops the binary here without adding it to PATH.
  property string cliPath: Quickshell.env("ADGUARDVPN_CLI") || "/opt/adguardvpn_cli/adguardvpn-cli"

  property bool installed: false
  property bool running: false

  // Optimistic state so the switch reacts instantly: -1 follows the real
  // state, 0/1 hold until the action's refresh catches up.
  property int _desired: -1
  readonly property bool active: _desired === -1 ? running : (_desired === 1)
  property string statusText: "Checking…"
  property string location: ""
  property string mode: "" // socks | tun | "" unknown
  property string proxyAddress: "" // host:port of the SOCKS listener
  property var warnings: []
  property string actionStatus: ""
  property string lastError: ""
  property var locations: [] // [{iso, country, city, ping}] sorted by ping
  property bool locationsRefreshing: false

  // The CLI segfaults intermittently on list-locations; retrying immediately
  // just stacks coredumps. Back off exponentially after failures.
  property int _locationsFailures: 0
  property double _locationsLastFailureMs: 0

  // Favorited cities, plugin-owned state. Follows the first-party convention
  // (clipboard, agents): ~/.local/state/omarchy/, XDG_STATE_HOME-aware.
  readonly property string favoritesPath: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/adguardvpn-favorites.json"
  property var favorites: [] // stored city strings, in add order
  readonly property var favoriteLocations: Model.favoriteLocations(favorites, locations)
  readonly property var catalogLocations: Model.nonFavoriteLocations(favorites, locations)

  // SOCKS-mode truth: `status` can report Disconnected in steady state while
  // the proxy still accepts connections, so probe the listener and let a live
  // socket outrank a stale status line.
  property bool _listenerUp: false

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 10, 5, 3600)
  readonly property bool busy: checkProcess.running || statusProcess.running || configProcess.running || actionProcess.running || locationsProcess.running

  property string _statusOutput: ""
  property string _statusError: ""
  property int _pollCount: 0
  property string _configOutput: ""
  property string _configError: ""
  property string _actionOutput: ""
  property string _actionError: ""
  property string _locationsOutput: ""
  property string _locationsError: ""

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    if (n < min) n = min
    if (n > max) n = max
    return n
  }

  function proxyUri() {
    return proxyAddress !== "" ? "socks5://" + proxyAddress : ""
  }

  // bash /dev/tcp probe of the SOCKS listener; see Model.listenProbe.
  function listenerProbeCommand() {
    return Model.listenProbe(proxyAddress)
  }

  // A live SOCKS listener outranks a "disconnected" status line — unless a
  // disconnect is pending, where user intent wins over the lingering socket.
  function socksListenerUp() {
    return mode === "socks" && _listenerUp && _desired !== 0
  }

  function copyToClipboard(value) {
    var text = String(value || "")
    if (text === "") return
    Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(text) + " | wl-copy"])
  }

  function isFavorite(city) {
    return Model.containsCity(favorites, city)
  }

  function toggleFavorite(city) {
    var target = String(city || "")
    if (target === "") return
    var next = favorites.slice()
    for (var i = 0; i < next.length; i++) {
      if (Model.sameCity(next[i], target)) {
        next.splice(i, 1)
        break
      }
    }
    if (next.length === favorites.length) next.push(target)
    favorites = next
    favoritesFile.setText(JSON.stringify(next))
    favoritesFile.writeAdapter()
  }

  function refresh() {
    if (installed) {
      refreshStatusAndConfig()
      return
    }
    if (!checkProcess.running) {
      checkProcess.command = ["bash", "-c", "test -x " + Util.shellQuote(cliPath)]
      checkProcess.running = true
    }
  }

  function refreshStatusAndConfig() {
    if (!installed) return
    _pollCount += 1
    var launched = false
    if (!statusProcess.running) {
      _statusOutput = ""
      _statusError = ""
      statusProcess.command = [cliPath, "status"]
      statusProcess.running = true
      launched = true
    }
    if (!configProcess.running && _pollCount % 6 === 1) {
      // Config is near-static (hand-edited CLI settings); status carries the
      // freshness. First poll and then roughly once a minute.
      _configOutput = ""
      _configError = ""
      configProcess.command = [cliPath, "config", "show"]
      configProcess.running = true
      launched = true
    }
    if (mode === "socks") {
      var probe = listenerProbeCommand()
      if (probe !== null && !listenerProcess.running) {
        listenerProcess.command = probe
        listenerProcess.running = true
      }
    }
    // Reap polls that never exit (flaky network) so refreshes keep flowing.
    if (launched && !pollWatchdog.running) pollWatchdog.start()
  }

  function resetUnavailable(message) {
    running = false
    _desired = -1
    statusText = message
    location = ""
    warnings = []
  }

  function parseStatus(raw) {
    var parsed = Model.parseStatus(raw)
    if (!parsed.ok) {
      resetUnavailable(parsed.message || "Status error")
      lastError = parsed.message || "Failed to parse status"
      return
    }
    running = parsed.connected || socksListenerUp()
    // Reality caught up to the pending toggle — stop overriding.
    if (_desired !== -1 && running === (_desired === 1)) _desired = -1
    // Keep the last known location while the listener override holds the
    // connection up — the lying status line carries no location.
    if (parsed.location !== "" || !socksListenerUp()) location = parsed.location
    warnings = parsed.warnings
    if (parsed.connected || socksListenerUp()) {
      statusText = "Connected"
      if (parsed.mode !== "") mode = parsed.mode
    } else {
      statusText = "Disconnected"
    }
    lastError = ""
  }

  function applyConfig(raw) {
    var parsed = Model.parseConfig(raw)
    mode = parsed.mode
    proxyAddress = parsed.proxyAddress
  }

  function toggle() {
    if (!installed || actionProcess.running) return
    if (active) disconnect()
    else connect()
  }

  function connect() {
    if (!installed || actionProcess.running) return
    _desired = 1
    runAction([cliPath, "connect", "-y", "--no-progress"], "Connecting…")
  }

  function connectTo(city) {
    var target = String(city || "")
    if (!installed || actionProcess.running || target === "") return
    // Reconnecting to the city we're on bounces the tunnel and kills every
    // in-flight proxied connection — make that click a no-op instead.
    if (running && Model.sameCity(location, target)) {
      actionStatus = "Already on " + target
      actionStatusTimer.restart()
      return
    }
    _desired = 1
    runAction([cliPath, "connect", "-y", "--no-progress", "-l", target], "Connecting to " + target + "…")
  }

  function connectFastest() {
    if (!installed || actionProcess.running) return
    _desired = 1
    runAction([cliPath, "connect", "-y", "--no-progress", "-f"], "Connecting to the fastest location…")
  }

  // Ping estimates come from live measurement, so fetch on panel open and
  // explicit refresh only — never on the periodic status poll.
  function refreshLocations() {
    if (!installed || locationsProcess.running || locationsCooldownActive()) return
    _locationsOutput = ""
    _locationsError = ""
    locationsRefreshing = true
    locationsProcess.command = [cliPath, "list-locations"]
    locationsProcess.running = true
  }

  function locationsCooldownActive() {
    // Cooldown protects a working list from crash-loop churn; an empty list
    // has nothing to protect, and throttling it stretches a seconds-long
    // network blip into minutes of missing locations.
    if (_locationsFailures === 0 || locations.length === 0) return false
    var cooldown = Math.min(300000, 60000 * Math.pow(2, _locationsFailures - 1))
    return Date.now() - _locationsLastFailureMs < cooldown
  }

  function noteLocationsResult(ok) {
    if (ok) _locationsFailures = 0
    else {
      _locationsFailures += 1
      _locationsLastFailureMs = Date.now()
    }
  }

  function disconnect() {
    if (!installed || actionProcess.running) return
    _desired = 0
    // A probe launched before this click can still report the port up;
    // user intent wins until the next probe re-establishes the truth.
    _listenerUp = false
    runAction([cliPath, "disconnect"], "Disconnecting…")
  }

  function runAction(command, label) {
    if (actionProcess.running) return
    _actionOutput = ""
    _actionError = ""
    actionStatus = label || ""
    actionProcess.command = command
    actionProcess.running = true
    actionWatchdog.restart()
  }

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: delayedRefresh
    interval: 600
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    id: pollWatchdog
    interval: 15000
    repeat: false
    onTriggered: {
      if (statusProcess.running) statusProcess.running = false
      if (configProcess.running) configProcess.running = false
      if (locationsProcess.running) locationsProcess.running = false
    }
  }

  // Real connects take tens of seconds on flaky networks, so this reaps
  // later than the poll watchdog; onExited treats the kill as a failure.
  Timer {
    id: actionWatchdog
    interval: 45000
    repeat: false
    onTriggered: if (actionProcess.running) actionProcess.running = false
  }

  Timer {
    id: actionStatusTimer
    interval: 2200
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  FileView {
    id: favoritesFile
    path: root.favoritesPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: {
      try {
        root.favorites = JSON.parse(text()).filter(function (v) { return typeof v === "string" })
      } catch (e) {
        root.favorites = []
      }
    }
    onLoadFailed: root.favorites = []
    onSaveFailed: root.lastError = "Could not save favorites"
    onFileChanged: reload()
  }

  Process {
    id: checkProcess
    running: false
    command: []
    onExited: function(exitCode) {
      root.installed = exitCode === 0
      if (root.installed) root.refreshStatusAndConfig()
      else root.resetUnavailable("Not installed")
    }
  }

  Process {
    id: statusProcess
    running: false
    command: []
    stdout: StdioCollector { id: statusStdout; waitForEnd: true; onStreamFinished: root._statusOutput = text }
    stderr: StdioCollector { id: statusStderr; waitForEnd: true; onStreamFinished: root._statusError = text }
    onExited: function(exitCode) {
      var stdout = String(statusStdout.text || root._statusOutput || "")
      var stderr = String(statusStderr.text || root._statusError || "")
      if (exitCode === 0) root.parseStatus(stdout)
      else {
        root.resetUnavailable("Unavailable")
        root.lastError = Model.elide(stderr || stdout || "Status command failed")
      }
    }
  }

  Process {
    id: configProcess
    running: false
    command: []
    stdout: StdioCollector { id: configStdout; waitForEnd: true; onStreamFinished: root._configOutput = text }
    stderr: StdioCollector { id: configStderr; waitForEnd: true; onStreamFinished: root._configError = text }
    onExited: function(exitCode) {
      var stdout = String(configStdout.text || root._configOutput || "")
      var stderr = String(configStderr.text || root._configError || "")
      if (exitCode === 0) root.applyConfig(stdout)
      else if (root.proxyAddress === "") root.lastError = Model.elide(stderr || stdout || "Config command failed")
    }
  }

  Process {
    id: locationsProcess
    running: false
    command: []
    stdout: StdioCollector { id: locationsStdout; waitForEnd: true; onStreamFinished: root._locationsOutput = text }
    stderr: StdioCollector { id: locationsStderr; waitForEnd: true; onStreamFinished: root._locationsError = text }
    onExited: function(exitCode) {
      root.locationsRefreshing = false
      var stdout = String(locationsStdout.text || root._locationsOutput || "")
      var stderr = String(locationsStderr.text || root._locationsError || "")
      if (exitCode === 0) {
        root.locations = Model.parseLocations(stdout)
        root.noteLocationsResult(root.locations.length > 0)
        if (root.locations.length === 0) root.lastError = "No locations parsed"
      } else {
        root.noteLocationsResult(false)
        root.lastError = Model.elide(stderr || stdout || "list-locations failed")
      }
    }
  }

  Process {
    id: listenerProcess
    running: false
    command: []
    onExited: function(exitCode) {
      root._listenerUp = exitCode === 0
      // Probe can land after the status line: apply the override here too.
      if (!root.running && root.socksListenerUp()) {
        root.running = true
        root.statusText = "Connected"
        root.lastError = ""
      }
    }
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stdout: StdioCollector { id: actionStdout; waitForEnd: true; onStreamFinished: root._actionOutput = text }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true; onStreamFinished: root._actionError = text }
    onExited: function(exitCode) {
      var stdout = String(actionStdout.text || root._actionOutput || "")
      var stderr = String(actionStderr.text || root._actionError || "")
      if (exitCode !== 0) {
        root._desired = -1
        root.lastError = Model.elide(stderr || stdout || "Command failed")
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else {
        root.lastError = ""
        root.actionStatus = ""
      }
      delayedRefresh.restart()
    }
  }
}
