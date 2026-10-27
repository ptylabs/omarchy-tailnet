// Pure helpers, kept free of QML so they can be exercised with node.

var KNOWN_PORTS = {
  21: { name: "ftp" },
  22: { name: "ssh", ssh: true },
  53: { name: "dns" },
  80: { name: "http", scheme: "http" },
  443: { name: "https", scheme: "https" },
  445: { name: "smb" },
  1883: { name: "mqtt" },
  2049: { name: "nfs" },
  3000: { name: "web:3000", scheme: "http" },
  3306: { name: "mysql" },
  3389: { name: "rdp" },
  5000: { name: "web:5000", scheme: "http" },
  5432: { name: "postgres" },
  5900: { name: "vnc" },
  6379: { name: "redis" },
  8000: { name: "web:8000", scheme: "http" },
  8080: { name: "web:8080", scheme: "http" },
  8123: { name: "home-assistant", scheme: "http" },
  8443: { name: "web:8443", scheme: "https" },
  9000: { name: "web:9000", scheme: "http" },
  9090: { name: "web:9090", scheme: "http" },
  11434: { name: "ollama", scheme: "http" },
  27017: { name: "mongodb" },
  32400: { name: "plex", scheme: "http" }
}

function filterIPv4(ips) {
  var result = []
  if (!ips || typeof ips.length !== "number") return result
  for (var i = 0; i < ips.length; i++) {
    var ip = String(ips[i] || "")
    if (/^100\./.test(ip)) result.push(ip)
  }
  return result
}

function cleanDnsName(name) {
  var value = String(name || "")
  return value.charAt(value.length - 1) === "." ? value.slice(0, -1) : value
}

function shortDnsName(name) {
  var clean = cleanDnsName(name)
  if (clean === "") return ""
  return clean.split(".")[0] || clean
}

function displayHostName(hostName, dnsName) {
  var host = String(hostName || "")
  if (host !== "" && host.toLowerCase() !== "localhost") return host
  return shortDnsName(dnsName) || host || "Unknown"
}

function isMullvadPeer(peer) {
  var dnsName = cleanDnsName((peer && peer.DNSName) || "").toLowerCase()
  return /\.mullvad\.ts\.net$/.test(dnsName)
}

function osIcon(os) {
  var value = String(os || "").toLowerCase()
  if (value === "linux") return "󰌽"
  if (value === "macos" || value === "ios") return "󰀵"
  if (value === "windows") return "󰍲"
  if (value === "android") return "󰀲"
  return "󰟀"
}

function hasSshCapability(self) {
  var capability = "https://tailscale.com/cap/ssh"
  if (self && self.CapMap && self.CapMap[capability] !== undefined) return true
  var caps = (self && self.Capabilities) || []
  for (var i = 0; i < caps.length; i++) if (String(caps[i]) === capability) return true
  return false
}

function deviceFromStatus(id, peer, isSelf) {
  var ips = filterIPv4(peer.TailscaleIPs || [])
  return {
    id: id,
    self: isSelf === true,
    name: displayHostName(peer.HostName, peer.DNSName),
    dnsName: cleanDnsName(peer.DNSName),
    ip: ips.length > 0 ? ips[0] : "",
    os: String(peer.OS || ""),
    online: isSelf === true || peer.Online === true,
    lastSeen: String(peer.LastSeen || ""),
    // Tailscale only publishes host keys for peers running Tailscale SSH.
    tailscaleSsh: !!(peer.sshHostKeys && peer.sshHostKeys.length > 0),
    exitNode: peer.ExitNode === true,
    tags: peer.Tags || []
  }
}

function parseStatus(raw) {
  var text = String(raw || "").trim()
  if (text === "") return { ok: true, unavailable: true, message: "Desconectado" }

  try {
    var data = JSON.parse(text)
    var backendState = String(data.BackendState || "Unknown")
    var self = data.Self || {}
    var tailnet = data.CurrentTailnet || {}
    var devices = []
    var rawPeers = data.Peer || {}

    for (var id in rawPeers) {
      var peer = rawPeers[id] || {}
      if (isMullvadPeer(peer)) continue
      devices.push(deviceFromStatus(id, peer, false))
    }

    devices.sort(function(a, b) {
      if (a.online !== b.online) return a.online ? -1 : 1
      return String(a.name).localeCompare(String(b.name))
    })

    var capName = self.CapMap && self.CapMap["tailnet-display-name"]
    var tailnetName = String(tailnet.Name || (capName && capName[0]) || "")

    return {
      ok: true,
      unavailable: false,
      backendState: backendState,
      running: backendState === "Running",
      needsLogin: backendState === "NeedsLogin",
      authUrl: String(data.AuthURL || ""),
      tailnetName: tailnetName,
      magicDnsSuffix: String(tailnet.MagicDNSSuffix || data.MagicDNSSuffix || ""),
      magicDnsEnabled: tailnet.MagicDNSEnabled !== false,
      self: deviceFromStatus("self", self, true),
      selfCanServeSsh: hasSshCapability(self),
      devices: devices
    }
  } catch (e) {
    return { ok: false, unavailable: true, message: "Error de estado", error: "No se pudo leer tailscale status" }
  }
}

// Scanner output is one "<ip>\t<port>" line per open port.
function parseScan(raw) {
  var result = {}
  var lines = String(raw || "").split(/\r?\n/)
  for (var i = 0; i < lines.length; i++) {
    var parts = lines[i].trim().split(/\s+/)
    if (parts.length < 2) continue
    var port = parseInt(parts[1], 10)
    if (!isFinite(port)) continue
    if (!result[parts[0]]) result[parts[0]] = []
    if (result[parts[0]].indexOf(port) === -1) result[parts[0]].push(port)
  }
  for (var ip in result) result[ip].sort(function(a, b) { return a - b })
  return result
}

function parsePorts(value) {
  var result = []
  var parts = String(value || "").split(/[\s,]+/)
  for (var i = 0; i < parts.length; i++) {
    var port = parseInt(parts[i], 10)
    if (isFinite(port) && port > 0 && port < 65536 && result.indexOf(port) === -1) result.push(port)
  }
  return result
}

function serviceFor(port, host) {
  var known = KNOWN_PORTS[port] || {}
  var scheme = known.scheme || ""
  var url = ""
  if (scheme !== "" && host !== "") {
    var defaultPort = (scheme === "http" && port === 80) || (scheme === "https" && port === 443)
    url = scheme + "://" + host + (defaultPort ? "" : ":" + port)
  }
  return {
    kind: "port",
    port: port,
    label: known.name || String(port),
    detail: host + ":" + port,
    url: url,
    ssh: known.ssh === true
  }
}

function servicesFor(ports, host) {
  var result = []
  var values = ports || []
  for (var i = 0; i < values.length; i++) result.push(serviceFor(values[i], host))
  return result
}

// `tailscale serve status --json` — Web maps "host:port" to path handlers,
// AllowFunnel marks the same keys that are public.
function parseServe(raw) {
  var result = []
  var text = String(raw || "").trim()
  if (text === "") return result
  try {
    var data = JSON.parse(text)
    var web = data.Web || {}
    var funnel = data.AllowFunnel || {}
    for (var hostPort in web) {
      var handlers = (web[hostPort] && web[hostPort].Handlers) || {}
      var port = hostPort.split(":").pop()
      var host = hostPort.slice(0, hostPort.length - port.length - 1)
      var base = "https://" + host + (port === "443" ? "" : ":" + port)
      for (var path in handlers) {
        var handler = handlers[path] || {}
        var target = handler.Proxy || handler.Path || (handler.Text ? "texto" : "")
        result.push({
          kind: funnel[hostPort] === true ? "funnel" : "serve",
          label: (funnel[hostPort] === true ? "funnel " : "serve ") + (port === "443" ? "" : ":" + port) + path,
          detail: base + path + (target ? " → " + target : ""),
          url: base + path,
          ssh: false
        })
      }
    }
    var tcp = data.TCP || {}
    for (var tcpPort in tcp) {
      var entry = tcp[tcpPort] || {}
      if (!entry.TCPForward) continue
      result.push({
        kind: "serve",
        label: "tcp :" + tcpPort,
        detail: ":" + tcpPort + " → " + entry.TCPForward,
        url: "",
        ssh: false
      })
    }
  } catch (e) {}
  return result
}

function sshDestination(device, user, target) {
  if (!device) return ""
  var host = target === "IP" ? device.ip : (device.dnsName || device.ip)
  if (host === "") return ""
  return user ? user + "@" + host : host
}

function sshCommand(device, user, target) {
  var destination = sshDestination(device, user, target)
  if (destination === "") return []
  return device.tailscaleSsh ? ["tailscale", "ssh", destination] : ["ssh", destination]
}

function relativeTime(iso, nowMs) {
  var ms = Date.parse(String(iso || ""))
  // Tailscale reports the zero time for peers it has never seen.
  if (!isFinite(ms) || ms <= 0) return ""
  var seconds = Math.max(0, Math.round(((nowMs || Date.now()) - ms) / 1000))
  if (seconds < 60) return "hace un momento"
  if (seconds < 3600) return "hace " + Math.round(seconds / 60) + " min"
  if (seconds < 86400) return "hace " + Math.round(seconds / 3600) + " h"
  return "hace " + Math.round(seconds / 86400) + " d"
}

if (typeof module !== "undefined") {
  module.exports = {
    filterIPv4: filterIPv4,
    cleanDnsName: cleanDnsName,
    displayHostName: displayHostName,
    osIcon: osIcon,
    parseStatus: parseStatus,
    parseScan: parseScan,
    parsePorts: parsePorts,
    serviceFor: serviceFor,
    servicesFor: servicesFor,
    parseServe: parseServe,
    sshDestination: sshDestination,
    sshCommand: sshCommand,
    relativeTime: relativeTime
  }
}
