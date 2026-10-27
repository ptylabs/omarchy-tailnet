import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})

  property bool installed: false
  property bool running: false
  property bool needsLogin: false

  // Optimistic toggle, same contract as omarchy.tailscale: -1 follows the
  // real state, 0/1 while a toggle is still catching up.
  property int _desired: -1
  readonly property bool active: _desired === -1 ? running : (_desired === 1)
  property string backendState: "Unknown"
  property string statusText: "Comprobando…"
  property string authUrl: ""
  property string tailnetName: ""
  property string magicDnsSuffix: ""
  property var selfDevice: null
  property var devices: []
  property var portsByIp: ({})
  property var serveEntries: []
  property bool scanning: false
  property double scannedAtMs: 0
  property string actionStatus: ""
  property string lastError: ""

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 30, 5, 3600)
  readonly property int scanIntervalSec: intSetting("scanIntervalSec", 120, 30, 3600)
  readonly property var ports: Model.parsePorts(setting("ports", "22,80,443,3000,8080"))
  readonly property string sshUser: String(setting("sshUser", "")).trim()
  readonly property string sshTarget: String(setting("sshTarget", "MagicDNS"))
  readonly property string downloadDir: String(setting("downloadDir", "")).trim()
  readonly property bool showOffline:setting("showOffline", true) !== false
  readonly property var visibleDevices: {
    if (showOffline) return devices
    var result = []
    for (var i = 0; i < devices.length; i++) if (devices[i].online) result.push(devices[i])
    return result
  }
  readonly property int onlineCount: {
    var n = 0
    for (var i = 0; i < devices.length; i++) if (devices[i].online) n++
    return n
  }
  readonly property bool busy: whichProcess.running || statusProcess.running || actionProcess.running || loginProcess.running

  property string _statusOutput: ""
  property string _statusError: ""
  property string _scanOutput: ""
  property string _serveOutput: ""
  property string _actionOutput: ""
  property string _actionError: ""
  property string _loginOutput: ""

  // Probes every host:port pair in parallel through bash's /dev/tcp, so no
  // nmap/nc dependency; each probe is capped by `timeout`.
  readonly property string scanScript: ""
    + "t=\"$0\"; ports=\"$1\"; shift 2; "
    + "for h in \"$@\"; do for p in ${ports//,/ }; do "
    + "  ( timeout \"$t\" bash -c 'exec 3<>/dev/tcp/$0/$1' \"$h\" \"$p\" 2>/dev/null && printf '%s\\t%s\\n' \"$h\" \"$p\" ) & "
    + "done; done; wait"

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    return Math.max(min, Math.min(max, n))
  }

  function osIcon(os) {
    return Model.osIcon(os)
  }

  function relativeTime(iso) {
    return Model.relativeTime(iso, Date.now())
  }

  function servicesFor(device) {
    if (!device || device.ip === "") return []
    var host = sshTarget === "IP" ? device.ip : (device.dnsName || device.ip)
    var result = Model.servicesFor(portsByIp[device.ip] || [], host)
    if (device.self) result = serveEntries.concat(result)
    return result
  }

  function hasScanned(device) {
    return device && portsByIp[device.ip] !== undefined
  }

  function canSsh(device) {
    if (!device || !device.online || device.self) return false
    return Model.sshCommand(device, sshUser, sshTarget).length > 0
  }

  function sshLabel(device) {
    if (!device) return ""
    var dest = Model.sshDestination(device, sshUser, sshTarget)
    return (device.tailscaleSsh ? "tailscale ssh " : "ssh ") + dest
  }

  function openSsh(device) {
    if (!canSsh(device)) return
    var command = Model.sshCommand(device, sshUser, sshTarget)
    // Keep the window open when the session fails, otherwise an auth error
    // just flashes a terminal on screen and disappears.
    var script = "\"$@\"; code=$?; "
      + "if [ $code -ne 0 ]; then printf '\\n[%s terminó con código %s] Pulsa Enter para cerrar… ' \"$*\" \"$code\"; read -r _; fi"
    Quickshell.execDetached(["setsid", "uwsm-app", "--", "xdg-terminal-exec", "--app-id=org.omarchy.ssh",
      "--title=SSH " + device.name, "-e", "bash", "-c", script, "ssh"].concat(command))
    flashStatus("Abriendo " + sshLabel(device))
  }

  // mode is "upload" or "download"; transfer.sh does the picking and copying
  // inside a terminal so ssh can still ask for a password.
  function transfer(device, mode) {
    if (!canSsh(device)) return
    var destination = Model.sshDestination(device, sshUser, sshTarget)
    var script = decodeURIComponent(String(Qt.resolvedUrl("transfer.sh")).replace(/^[a-z]+:\/\//, ""))
    Quickshell.execDetached(["setsid", "uwsm-app", "--", "xdg-terminal-exec", "--app-id=org.omarchy.tailnet-transfer",
      "--title=" + (mode === "upload" ? "Subir a " : "Descargar de ") + device.name,
      "-e", "bash", script, mode, destination, downloadDir])
  }

  function openService(device, service) {
    if (!service) return
    if (service.ssh) openSsh(device)
    else if (service.url !== "") Quickshell.execDetached(["omarchy-launch-browser", service.url])
    else copyToClipboard(service.detail, service.detail)
  }

  function openFirstWebService(device) {
    var services = servicesFor(device)
    for (var i = 0; i < services.length; i++) {
      if (services[i].url !== "") {
        Quickshell.execDetached(["omarchy-launch-browser", services[i].url])
        return
      }
    }
  }

  function copyToClipboard(value, label) {
    var text = String(value || "")
    if (text === "") return
    Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(text) + " | wl-copy"])
    flashStatus("Copiado " + (label || text))
  }

  function flashStatus(text) {
    actionStatus = text
    actionStatusTimer.restart()
  }

  function refresh() {
    if (installed) {
      refreshStatus()
      return
    }
    if (!whichProcess.running) {
      whichProcess.command = ["which", "tailscale"]
      whichProcess.running = true
    }
  }

  function refreshStatus() {
    if (!installed || statusProcess.running) return
    _statusOutput = ""
    _statusError = ""
    statusProcess.command = ["tailscale", "status", "--json"]
    statusProcess.running = true
    if (!serveProcess.running) {
      _serveOutput = ""
      serveProcess.command = ["tailscale", "serve", "status", "--json"]
      serveProcess.running = true
    }
    if (!pollWatchdog.running) pollWatchdog.start()
  }

  function scan() {
    if (!running || scanProcess.running || ports.length === 0) return
    var hosts = []
    if (selfDevice && selfDevice.ip !== "") hosts.push(selfDevice.ip)
    for (var i = 0; i < devices.length; i++) if (devices[i].online && devices[i].ip !== "") hosts.push(devices[i].ip)
    if (hosts.length === 0) return
    _scanOutput = ""
    scanning = true
    scanProcess.command = ["bash", "-c", scanScript, "1", ports.join(",")].concat(hosts)
    scanProcess.running = true
  }

  function scanIfStale() {
    if (Date.now() - scannedAtMs > scanIntervalSec * 1000) scan()
  }

  function resetUnavailable(message) {
    running = false
    needsLogin = false
    _desired = -1
    backendState = "Unavailable"
    statusText = message
    authUrl = ""
    selfDevice = null
    devices = []
    serveEntries = []
  }

  function parseStatus(raw) {
    var parsed = Model.parseStatus(raw)
    if (!parsed.ok) {
      resetUnavailable(parsed.message)
      lastError = parsed.error
      return
    }
    if (parsed.unavailable) {
      resetUnavailable(parsed.message)
      return
    }
    var wasRunning = running
    backendState = parsed.backendState
    running = parsed.running
    if (_desired !== -1 && running === (_desired === 1)) _desired = -1
    needsLogin = parsed.needsLogin
    authUrl = parsed.authUrl
    tailnetName = parsed.tailnetName
    magicDnsSuffix = parsed.magicDnsSuffix
    selfDevice = parsed.self
    devices = parsed.running ? parsed.devices : []
    statusText = needsLogin ? "Requiere login" : (running ? "Conectado" : (backendState === "Stopped" ? "Desconectado" : backendState))
    lastError = ""
    if (running && (!wasRunning || scannedAtMs === 0)) scan()
  }

  function toggleTailscale() {
    if (!installed) return
    if (active) {
      _desired = 0
      runAction(["tailscale", "down"])
    } else {
      loginOrUp()
    }
  }

  function loginOrUp() {
    if (!installed || loginProcess.running) return
    if (needsLogin && /^https?:\/\//.test(authUrl)) {
      Quickshell.execDetached(["omarchy-launch-browser", authUrl])
      return
    }
    _desired = needsLogin ? -1 : 1
    _loginOutput = ""
    loginProcess.command = ["tailscale", "up"]
    loginProcess.running = true
  }

  function runAction(command) {
    if (actionProcess.running) return
    _actionOutput = ""
    _actionError = ""
    actionProcess.command = command
    actionProcess.running = true
  }

  function elide(text) {
    var value = String(text || "").replace(/\s+/g, " ").trim()
    return value.length > 140 ? value.substring(0, 137) + "…" : value
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    interval: root.scanIntervalSec * 1000
    repeat: true
    running: root.running
    onTriggered: root.scan()
  }

  Timer {
    id: delayedRefresh
    interval: 600
    onTriggered: root.refresh()
  }

  Timer {
    id: pollWatchdog
    interval: 15000
    onTriggered: {
      if (statusProcess.running) statusProcess.running = false
      if (serveProcess.running) serveProcess.running = false
      if (scanProcess.running) scanProcess.running = false
    }
  }

  Timer {
    id: actionStatusTimer
    interval: 2200
    onTriggered: root.actionStatus = ""
  }

  Process {
    id: whichProcess
    command: []
    onExited: function(exitCode) {
      root.installed = exitCode === 0
      if (root.installed) root.refreshStatus()
      else root.resetUnavailable("Tailscale no está instalado")
    }
  }

  Process {
    id: statusProcess
    command: []
    stdout: StdioCollector { id: statusStdout; waitForEnd: true; onStreamFinished: root._statusOutput = text }
    stderr: StdioCollector { id: statusStderr; waitForEnd: true; onStreamFinished: root._statusError = text }
    onExited: function(exitCode) {
      var stdout = String(statusStdout.text || root._statusOutput || "")
      var stderr = String(statusStderr.text || root._statusError || "")
      if (exitCode === 0) root.parseStatus(stdout)
      else {
        root.resetUnavailable("Desconectado")
        root.lastError = root.elide(stderr)
      }
    }
  }

  Process {
    id: serveProcess
    command: []
    stdout: StdioCollector { id: serveStdout; waitForEnd: true; onStreamFinished: root._serveOutput = text }
    onExited: function(exitCode) {
      root.serveEntries = exitCode === 0 ? Model.parseServe(String(serveStdout.text || root._serveOutput || "")) : []
    }
  }

  Process {
    id: scanProcess
    command: []
    stdout: StdioCollector { id: scanStdout; waitForEnd: true; onStreamFinished: root._scanOutput = text }
    onExited: function(exitCode) {
      var found = Model.parseScan(String(scanStdout.text || root._scanOutput || ""))
      var hosts = scanProcess.command.slice(5)
      // Hosts with nothing open still get an entry so the UI can tell
      // "no services" apart from "not scanned yet".
      for (var i = 0; i < hosts.length; i++) if (!found[hosts[i]]) found[hosts[i]] = []
      root.portsByIp = found
      root.scannedAtMs = Date.now()
      root.scanning = false
    }
  }

  Process {
    id: actionProcess
    command: []
    stdout: StdioCollector { id: actionStdout; waitForEnd: true; onStreamFinished: root._actionOutput = text }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true; onStreamFinished: root._actionError = text }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root._desired = -1
        root.lastError = root.elide(String(actionStderr.text || root._actionError || actionStdout.text || "Falló el comando de Tailscale"))
      } else {
        root.lastError = ""
      }
      delayedRefresh.restart()
    }
  }

  Process {
    id: loginProcess
    command: []
    stdout: SplitParser { onRead: function(data) { root._loginOutput += data + "\n" } }
    stderr: SplitParser { onRead: function(data) { root._loginOutput += data + "\n" } }
    onExited: function(exitCode) {
      var match = root._loginOutput.match(/https?:\/\/\S+/)
      if (match) {
        root._desired = -1
        Quickshell.execDetached(["omarchy-launch-browser", match[0]])
      } else if (exitCode !== 0) {
        root._desired = -1
        root.lastError = root.elide(root._loginOutput || "tailscale up falló")
      }
      delayedRefresh.restart()
    }
  }
}
