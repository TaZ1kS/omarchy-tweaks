import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import qs.Commons as Commons

Panel {
  id: root
  moduleName: "local.system-monitor"
  manageIpc: false

  implicitWidth: button.implicitWidth
  implicitHeight: bar ? bar.barSize : Style.bar.sizeHorizontal

  Commons.Translations {
    id: strings
    directory: Qt.resolvedUrl("i18n")
  }

  readonly property string metric: String(setting("metric", "cpu"))
  readonly property var barMetrics: {
    var v = setting("barMetrics", null)
    if (Array.isArray(v) && v.length > 0) {
      var out = []
      for (var i = 0; i < v.length; i++) out.push(String(v[i]))
      return out
    }
    return [String(setting("metric", "cpu"))]
  }
  readonly property int intervalMs: Math.max(250, Number(setting("interval", 250)) || 250)

  readonly property bool showMemory: setting("showMemory", true) !== false
  readonly property bool showSwap: setting("showSwap", true) !== false
  readonly property bool showGpu: setting("showGpu", true) !== false
  readonly property bool showDisk: setting("showDisk", true) !== false
  readonly property bool showTopProcesses: setting("showTopProcesses", true) !== false
  readonly property bool showTemperature: setting("showTemperature", true) !== false
  readonly property bool showNetwork: setting("showNetwork", true) !== false
  readonly property bool showUptime: setting("showUptime", true) !== false
  readonly property bool showLoad: setting("showLoad", true) !== false

  property var stats: ({})
  property var history: []
  property bool paused: false
  property bool sortMemory: false
  readonly property int graphSeconds: Math.max(10, Math.min(300, Number(setting("graphSeconds", 60))))
  readonly property int graphHeight: Math.max(30, Math.min(150, Number(setting("graphHeight", 70))))
  readonly property int processLimit: Math.max(3, Math.min(15, Number(setting("processLimit", 8))))
  readonly property int panelWidth: Math.max(320, Math.min(700, Number(setting("panelWidth", 440))))
  readonly property var visibleProcesses: topProcesses.slice().sort(function(a,b) { return root.sortMemory ? b.rss-a.rss : b.cpu-a.cpu }).slice(0, processLimit)

  property bool restartQueued: false
  property bool settingsOpen: false
  property int settingsCursor: 0
  property var settingsFocusables: []
  property var setQueue: []

  readonly property real cpuValue: Math.max(0, Math.min(100, Number(stats.cpu) || 0))
  readonly property real memValue: Math.max(0, Math.min(100, Number(stats.mem) || 0))
  readonly property real swapValue: Math.max(0, Math.min(100, Number(stats.swap) || 0))
  readonly property real diskValue: Math.max(0, Math.min(100, Number(stats.diskPct) || 0))
  readonly property var gpu: stats.gpu && typeof stats.gpu === "object" ? stats.gpu : null
  readonly property var topProcesses: Array.isArray(stats.top) ? stats.top : []

  // ---------------------------------------------------------------- formatting

  function percent(value) {
    return Commons.I18n.formatNumber(Math.round(Number(value) || 0)) + "%"
  }

  function gib(mib) {
    return Commons.I18n.formatNumber((Number(mib) || 0) / 1024, 1)
  }

  function rate(bytes) {
    var value = Math.max(0, Number(bytes) || 0)
    if (value >= 1048576) return Commons.I18n.formatNumber(value / 1048576, 1) + " MB/s"
    if (value >= 1024) return Commons.I18n.formatNumber(value / 1024, 0) + " KB/s"
    return Commons.I18n.formatNumber(value, 0) + " B/s"
  }

  function compactRate(bytes) {
    var value = Math.max(0, Number(bytes) || 0)
    if (value >= 1048576) return Commons.I18n.formatNumber(value / 1048576, 1) + "M"
    if (value >= 1024) return Commons.I18n.formatNumber(value / 1024, 0) + "K"
    return Commons.I18n.formatNumber(value, 0) + "B"
  }

  function uptimeText(seconds) {
    var total = Math.max(0, Math.floor(Number(seconds) || 0))
    var days = Math.floor(total / 86400)
    var hours = Math.floor((total % 86400) / 3600)
    var minutes = Math.floor((total % 3600) / 60)
    if (days > 0) return days + "d " + hours + "h"
    if (hours > 0) return hours + "h " + minutes + "m"
    return Math.max(1, minutes) + "m"
  }

  readonly property string temperatureText: Number(stats.temp) > 0
    ? Commons.I18n.formatNumber(Number(stats.temp)) + " °C"
    : "—"

  readonly property string uptimeLabel: strings.t("uptime").arg(uptimeText(stats.uptime))
  readonly property string loadText: Commons.I18n.formatNumber(Number(stats.load) || 0, 2)

  // ------------------------------------------------------------ bar presentation

  function metricGlyph(key) {
    switch (key) {
      case "memory": return "󰍜"
      case "temperature": return "󰔏"
      case "disk": return "󰋊"
      case "network": return "󰌗"
      case "gpu": return root.gpu ? "󰣈" : "󰻠"
      default: return "󰻠"
    }
  }

  function metricLabel(key) {
    switch (key) {
      case "memory": return root.percent(root.memValue)
      case "temperature": return Number(root.stats.temp) > 0 ? Commons.I18n.formatNumber(Number(root.stats.temp)) + "°" : "—"
      case "disk": return root.percent(root.diskValue)
      case "network": return root.compactRate((Number(root.stats.rx) || 0) + (Number(root.stats.tx) || 0))
      case "gpu": return root.gpu ? root.percent(root.gpu.util) : root.percent(root.cpuValue)
      default: return root.percent(root.cpuValue)
    }
  }

  readonly property string barLabel: {
    var parts = []
    for (var i = 0; i < root.barMetrics.length; i++) {
      var k = root.barMetrics[i]
      parts.push(root.metricGlyph(k) + " " + root.metricLabel(k))
    }
    return parts.join("  ")
  }

  readonly property string tooltipText: strings.t("tooltip")
    .arg(root.percent(root.cpuValue)).arg(root.percent(root.memValue)).arg(root.temperatureText)

  function handleSample(line) {
    if (root.paused) return
    var sample
    try {
      sample = JSON.parse(String(line))
    } catch (e) {
      return
    }
    if (!sample || typeof sample !== "object" || Array.isArray(sample)) return

    var clean = {
      cpu: Math.max(0, Math.min(100, Number(sample.cpu) || 0)),
      mem: Math.max(0, Math.min(100, Number(sample.mem) || 0)),
      memUsedMb: Math.max(0, Number(sample.memUsedMb) || 0),
      memTotalMb: Math.max(0, Number(sample.memTotalMb) || 0),
      swap: Math.max(0, Math.min(100, Number(sample.swap) || 0)),
      swapUsedMb: Math.max(0, Number(sample.swapUsedMb) || 0),
      swapTotalMb: Math.max(0, Number(sample.swapTotalMb) || 0),
      temp: Number(sample.temp) || -1,
      load: Number(sample.load) || 0,
      uptime: Math.max(0, Number(sample.uptime) || 0),
      rx: Math.max(0, Number(sample.rx) || 0),
      tx: Math.max(0, Number(sample.tx) || 0),
      diskPct: Math.max(0, Math.min(100, Number(sample.diskPct) || 0)),
      diskUsedGb: Math.max(0, Number(sample.diskUsedGb) || 0),
      diskTotalGb: Math.max(0, Number(sample.diskTotalGb) || 0),
      gpu: null,
      top: []
    }

    if (sample.gpu && typeof sample.gpu === "object" && !Array.isArray(sample.gpu)) {
      clean.gpu = {
        name: String(sample.gpu.name || "").substring(0, 24),
        util: Math.max(0, Math.min(100, Number(sample.gpu.util) || 0)),
        memUsedMb: Math.max(0, Number(sample.gpu.memUsedMb) || 0),
        memTotalMb: Math.max(0, Number(sample.gpu.memTotalMb) || 0),
        temp: Number(sample.gpu.temp) || -1
      }
    }

    if (Array.isArray(sample.top)) {
      for (var i = 0; i < sample.top.length && clean.top.length < 8192; i++) {
        var row = sample.top[i]
        if (!row || typeof row !== "object") continue
        var name = String(row.name || "").replace(/[<>&]/g, "").substring(0, 32)
        if (name === "") continue
        clean.top.push({
          name: name,
          pid: Math.max(0, Number(row.pid) || 0),
          rss: Math.max(0, Number(row.rss) || 0),
          cpu: Math.max(0, Number(row.cpu) || 0),
          mem: Math.max(0, Number(row.mem) || 0)
        })
      }
    }

    stats = clean

    var next = history.slice()
    next.push({ time: Date.now(), value: clean.cpu })
    while (next.length > 1 && next[0].time < Date.now() - root.graphSeconds * 1000) next.shift()
    history = next
  }

  Process {
    id: sampler
    command: ["bash", String(Qt.resolvedUrl("sampler.sh")).replace(/^file:\/\//, ""), String(root.intervalMs)]
    environment: ({ LC_ALL: "C" })
    running: true
    stdout: SplitParser {
      onRead: function(line) { root.handleSample(line) }
    }
    onExited: {
      if (!root.restartQueued) {
        root.restartQueued = true
        restartTimer.restart()
      }
    }
  }

  Timer {
    id: restartTimer
    interval: 2000
    onTriggered: {
      root.restartQueued = false
      sampler.running = true
    }
  }

  // persistence queue

  Process {
    id: setter
    running: false
    command: []
    onExited: root.processSetQueue()
  }

  function persistSetting(key, value) {
    root.setQueue = root.setQueue.concat([{ key: key, value: JSON.stringify(value) }])
    root.processSetQueue()
  }

  function processSetQueue() {
    if (setter.running || root.setQueue.length === 0) return
    var item = root.setQueue.shift()
    root.setQueue = root.setQueue
    setter.command = ["omarchy", "bar", "set", "local.system-monitor", item.key, item.value, "--json"]
    setter.running = true
  }

  // settings cursor helpers

  function settingsMove(dx, dy) {
    if (dx !== 0) {
      var cur = root.settingsFocusables.length > 0 ? root.settingsFocusables[root.settingsCursor] : null
      if (cur && cur.field) {
        var v = cur.value + (dx > 0 ? cur.stepSize : -cur.stepSize)
        v = Math.max(cur.from, Math.min(cur.to, v))
        cur.value = v
        root.persistSetting("interval", v)
      }
      return
    }
    if (dy !== 0 && root.settingsFocusables.length > 0) {
      root.settingsCursor = Math.max(0, Math.min(root.settingsFocusables.length - 1, root.settingsCursor + dy))
      root.syncSettingsCursor()
    }
  }

  function settingsActivate() {
    var cur = root.settingsFocusables.length > 0 ? root.settingsFocusables[root.settingsCursor] : null
    if (!cur) return
    if (typeof cur.toggle === "function") { cur.toggle(); return }
    if (typeof cur.clicked === "function") { cur.clicked(); return }
    if (cur.field && typeof cur.field.forceActiveFocus === "function") { cur.field.forceActiveFocus(); return }
  }

  function syncSettingsCursor() {
    for (var i = 0; i < root.settingsFocusables.length; i++) {
      var it = root.settingsFocusables[i]
      if (it) it.hasCursor = (i === root.settingsCursor)
    }
  }

  onSettingsOpenChanged: {
    if (settingsOpen) {
      settingsCursor = 0
      Qt.callLater(function() { root.syncSettingsCursor() })
    } else {
      for (var i = 0; i < settingsFocusables.length; i++) {
        var it = settingsFocusables[i]
        if (it) it.hasCursor = false
      }
    }
  }

  // -------------------------------------------------------------------- bar item

  Text {
    id: widthProbe
    visible: false
    text: root.barLabel
    font.family: root.bar.fontFamily
    font.pixelSize: Style.bar.iconFont
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    anchors.leftMargin: Style.space(14)
    bar: root.bar
    text: ""
    labelText: root.barLabel
    slotSize: Math.max(Style.bar.iconSlot, widthProbe.implicitWidth + Style.space(42))
    tooltipText: root.tooltipText
    onPressed: function(b) {
      if (b === Qt.MiddleButton) {
        if (root.bar) root.bar.run("omarchy-launch-or-focus-tui btop")
        return
      }
      root.toggle()
    }
  }

  // ---------------------------------------------------------------------- popup

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(root.panelWidth))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: PanelKeyCatcher {
      anchors.fill: parent
      implicitHeight: contentColumn.implicitHeight
      blocked: (root.settingsOpen && metricsSelect.popupOpen) || (intervalField.field && intervalField.field.activeFocus)
      onCloseRequested: {
        if (root.settingsOpen) root.settingsOpen = false
        else root.close()
      }
      onMoveRequested: function(dx, dy) {
        if (root.settingsOpen) root.settingsMove(dx, dy)
      }
      onActivateRequested: {
        if (root.settingsOpen) root.settingsActivate()
      }
      onReturnRequested: {
        if (root.settingsOpen) root.settingsActivate()
      }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
      Column {
        id: contentColumn
        width: parent.width
        spacing: Style.space(12)

        // ---- monitor view ----
        Column {
          id: monitorView
          visible: !root.settingsOpen
          width: parent.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: strings.t("title")
            meta: root.uptimeLabel + "  ·  " + strings.t("load") + " " + root.loadText
            detail: root.percent(root.cpuValue)
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            iconComponent: Component {
              Text {
                textFormat: Text.PlainText
                text: "󰐰"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          Button {
            width: parent.width
            text: root.paused ? strings.t("resume") : strings.t("pause")
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            onClicked: root.paused = !root.paused
          }
          PanelSeparator { foreground: root.bar.foreground }

          Item {
            width: parent.width
            implicitHeight: cpuHeader.height + Style.space(6) + spark.height

            Item {
              id: cpuHeader
              width: parent.width
              height: Math.max(cpuGlyph.implicitHeight, cpuTitle.implicitHeight, cpuValueText.implicitHeight)

              Text {
                id: cpuGlyph
                textFormat: Text.PlainText
                text: "󰻠"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: cpuTitle
                textFormat: Text.PlainText
                text: strings.t("cpu")
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                anchors.left: cpuGlyph.right
                anchors.leftMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: cpuValueText
                textFormat: Text.PlainText
                text: root.percent(root.cpuValue)
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Canvas {
              id: spark
              width: parent.width
              height: Style.space(root.graphHeight)
              anchors.top: cpuHeader.bottom
              anchors.topMargin: Style.space(6)

              property var samples: root.history
              property color lineColor: Commons.Color.accent

              onSamplesChanged: requestPaint()
              onLineColorChanged: requestPaint()
              onWidthChanged: requestPaint()
              onHeightChanged: requestPaint()

              onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)

                ctx.strokeStyle = Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0.10)
                ctx.lineWidth = 1
                for (var g = 1; g < 4; g++) {
                  var gy = Math.round(height * g / 4) + 0.5
                  ctx.beginPath()
                  ctx.moveTo(0, gy)
                  ctx.lineTo(width, gy)
                  ctx.stroke()
                }

                var data = samples
                if (!data || data.length < 2) return

                var baseY = height - 1

                function pointX(index) {
                  return width - (data[data.length - 1].time - data[index].time) / (root.graphSeconds * 1000) * width
                }
                function pointY(value) {
                  return height - 1 - Math.max(0, Math.min(100, value)) / 100 * (height - 2)
                }

                ctx.beginPath()
                ctx.moveTo(pointX(0), baseY)
                for (var i = 0; i < data.length; i++) ctx.lineTo(pointX(i), pointY(data[i].value))
                ctx.lineTo(pointX(data.length - 1), baseY)
                ctx.closePath()
                ctx.fillStyle = Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0.10)
                ctx.fill()

                ctx.beginPath()
                for (var j = 0; j < data.length; j++) {
                  var x = pointX(j)
                  var y = pointY(data[j].value)
                  if (j === 0) ctx.moveTo(x, y)
                  else ctx.lineTo(x, y)
                }
                ctx.strokeStyle = lineColor
                ctx.lineWidth = 1.5
                ctx.lineJoin = "round"
                ctx.lineCap = "round"
                ctx.stroke()
                ctx.fillStyle = lineColor
                ctx.font = "10px sans-serif"
                ctx.fillText("100%", 4, 12)
                ctx.fillText("0%", 4, height - 4)
              }
            }
          }

          Meter {
            visible: root.showMemory
            glyph: "󰍜"
            label: strings.t("memory")
            value: root.gib(root.stats.memUsedMb) + " / " + root.gib(root.stats.memTotalMb) + " GB"
            fraction: root.memValue / 100
          }

          Meter {
            visible: root.showSwap && (Number(root.stats.swapTotalMb) || 0) > 0
            glyph: "󰓢"
            label: strings.t("swap")
            value: root.gib(root.stats.swapUsedMb) + " / " + root.gib(root.stats.swapTotalMb) + " GB"
            fraction: root.swapValue / 100
          }

          Meter {
            visible: root.showGpu && root.gpu !== null
            glyph: "󰣈"
            label: strings.t("gpu")
            value: root.gpu
              ? root.percent(root.gpu.util) + (root.gpu.temp > 0 ? "  ·  " + Commons.I18n.formatNumber(root.gpu.temp) + " °C" : "")
              : ""
            fraction: root.gpu ? root.gpu.util / 100 : 0
          }

          Meter {
            visible: root.showDisk
            glyph: "󰋊"
            label: strings.t("disk")
            value: root.percent(root.diskValue) + "  ·  " + root.gib((Number(root.stats.diskUsedGb) || 0) * 1024) + " / " + root.gib((Number(root.stats.diskTotalGb) || 0) * 1024) + " GB"
            fraction: root.diskValue / 100
          }

          PanelSeparator { foreground: root.bar.foreground }

          Column {
            width: parent.width
            spacing: Style.space(6)

            InfoPair {
              visible: root.showTemperature
              label: strings.t("temperature")
              value: root.temperatureText
            }

            InfoPair {
              visible: root.showNetwork
              label: strings.t("network")
              value: "󰇚 " + root.rate(root.stats.rx) + "    󰕒 " + root.rate(root.stats.tx)
            }

            InfoPair {
              visible: root.showUptime
              label: strings.t("uptimeLabel")
              value: root.uptimeText(root.stats.uptime)
            }

            InfoPair {
              visible: root.showLoad
              label: strings.t("load")
              value: root.loadText
            }
          }

          Column {
            visible: root.showTopProcesses && root.topProcesses.length > 0
            width: parent.width
            spacing: Style.space(6)

            PanelSeparator { foreground: root.bar.foreground }

            PanelSectionHeader {
              text: strings.t("topProcesses") + " (" + root.topProcesses.length + ")"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }

            Button {
              width: parent.width
              text: root.sortMemory ? strings.t("sortMemory") : strings.t("sortCpu")
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              onClicked: root.sortMemory = !root.sortMemory
            }
            Text {
              textFormat: Text.PlainText
              text: strings.t("cpuLifetime")
              color: root.bar.foreground
              font.pixelSize: Style.font.bodySmall
            }
            Repeater {
              model: root.visibleProcesses

              delegate: Item {
                required property var modelData
                width: parent.width
                height: Math.max(processName.implicitHeight, processCpu.implicitHeight)

                Text {
                  id: processName
                  textFormat: Text.PlainText
                  text: modelData.pid + "  " + modelData.name
                  color: root.bar.foreground
                  opacity: 0.85
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                  width: Math.max(0, parent.width - processCpu.implicitWidth - Style.space(12))
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  id: processCpu
                  textFormat: Text.PlainText
                  text: root.percent(modelData.cpu) + " · " + Commons.I18n.formatNumber(modelData.rss, 0) + " MiB"
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
            }
          }

          Button {
            width: parent.width
            text: strings.t("openBtop")
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            bordered: true
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            onClicked: {
              if (root.bar) root.bar.run("omarchy-launch-or-focus-tui btop")
              root.close()
            }
          }

          Button {
            width: parent.width
            text: strings.t("settings")
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            bordered: true
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            onClicked: root.settingsOpen = true
          }
        }

        // ---- settings view ----
        Column {
          id: settingsView
          visible: root.settingsOpen
          width: parent.width
          spacing: Style.space(12)

          Component.onCompleted: {
            root.settingsFocusables = [metricsSelect, tMemory, tSwap, tGpu, tDisk, tTop, tTemp, tNet, tUptime, tLoad, intervalField, backButton, settingsBtopButton]
            root.syncSettingsCursor()
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            Button {
              id: backButton
              text: "← " + strings.t("back")
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              bordered: true
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY
              hasCursor: false
              onClicked: root.settingsOpen = false
            }

            Text {
              textFormat: Text.PlainText
              text: strings.t("settings")
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          MultiSelect {
            id: metricsSelect
            width: parent.width
            label: strings.t("barMetrics")
            foreground: root.bar.foreground
            background: Commons.Color.popups.background
            popupBorder: Commons.Color.popups.border
            accent: Commons.Color.accent
            fontFamily: root.bar.fontFamily
            values: root.barMetrics
            options: [
              { "value": "cpu", "label": strings.t("cpu") },
              { "value": "memory", "label": strings.t("memory") },
              { "value": "temperature", "label": strings.t("temperature") },
              { "value": "gpu", "label": strings.t("gpu") },
              { "value": "disk", "label": strings.t("disk") },
              { "value": "network", "label": strings.t("network") }
            ]
            hasCursor: false
            onChanged: function(vals) { root.persistSetting("barMetrics", vals) }
          }

          Toggle {
            id: tMemory
            width: parent.width
            label: strings.t("showMemory")
            checked: root.showMemory
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            hasCursor: false
            onClicked: root.persistSetting("showMemory", !root.showMemory)
          }

          Toggle {
            id: tSwap
            width: parent.width
            label: strings.t("showSwap")
            checked: root.showSwap
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            hasCursor: false
            onClicked: root.persistSetting("showSwap", !root.showSwap)
          }

          Toggle {
            id: tGpu
            width: parent.width
            label: strings.t("showGpu")
            checked: root.showGpu
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            hasCursor: false
            onClicked: root.persistSetting("showGpu", !root.showGpu)
          }

          Toggle {
            id: tDisk
            width: parent.width
            label: strings.t("showDisk")
            checked: root.showDisk
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            hasCursor: false
            onClicked: root.persistSetting("showDisk", !root.showDisk)
          }

          Toggle {
            id: tTop
            width: parent.width
            label: strings.t("showTopProcesses")
            checked: root.showTopProcesses
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            hasCursor: false
            onClicked: root.persistSetting("showTopProcesses", !root.showTopProcesses)
          }

          Toggle {
            id: tTemp
            width: parent.width
            label: strings.t("showTemperature")
            checked: root.showTemperature
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            hasCursor: false
            onClicked: root.persistSetting("showTemperature", !root.showTemperature)
          }

          Toggle {
            id: tNet
            width: parent.width
            label: strings.t("showNetwork")
            checked: root.showNetwork
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            hasCursor: false
            onClicked: root.persistSetting("showNetwork", !root.showNetwork)
          }

          Toggle {
            id: tUptime
            width: parent.width
            label: strings.t("showUptime")
            checked: root.showUptime
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            hasCursor: false
            onClicked: root.persistSetting("showUptime", !root.showUptime)
          }

          Toggle {
            id: tLoad
            width: parent.width
            label: strings.t("showLoad")
            checked: root.showLoad
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            hasCursor: false
            onClicked: root.persistSetting("showLoad", !root.showLoad)
          }

          NumberField {
            id: intervalField
            width: parent.width
            label: strings.t("interval")
            value: root.intervalMs
            from: 250
            to: 10000
            stepSize: 250
            foreground: root.bar.foreground
            accent: Commons.Color.accent
            fontFamily: root.bar.fontFamily
            hasCursor: false
            onModified: function(v) { root.persistSetting("interval", v) }
          }

          NumberField {
            width: parent.width
            label: strings.t("graphSeconds")
            value: root.graphSeconds
            from: 10
            to: 300
            stepSize: 10
            foreground: root.bar.foreground
            accent: Commons.Color.accent
            fontFamily: root.bar.fontFamily
            onModified: function(v) { root.persistSetting("graphSeconds", v) }
          }
          NumberField {
            width: parent.width
            label: strings.t("graphHeight")
            value: root.graphHeight
            from: 30
            to: 150
            stepSize: 10
            foreground: root.bar.foreground
            accent: Commons.Color.accent
            fontFamily: root.bar.fontFamily
            onModified: function(v) { root.persistSetting("graphHeight", v) }
          }
          NumberField {
            width: parent.width
            label: strings.t("processLimit")
            value: root.processLimit
            from: 3
            to: 15
            stepSize: 1
            foreground: root.bar.foreground
            accent: Commons.Color.accent
            fontFamily: root.bar.fontFamily
            onModified: function(v) { root.persistSetting("processLimit", v) }
          }
          NumberField {
            width: parent.width
            label: strings.t("panelWidth")
            value: root.panelWidth
            from: 320
            to: 700
            stepSize: 20
            foreground: root.bar.foreground
            accent: Commons.Color.accent
            fontFamily: root.bar.fontFamily
            onModified: function(v) { root.persistSetting("panelWidth", v) }
          }
          Button {
            id: settingsBtopButton
            width: parent.width
            text: strings.t("openBtop")
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            bordered: true
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            hasCursor: false
            onClicked: {
              if (root.bar) root.bar.run("omarchy-launch-or-focus-tui btop")
              root.close()
            }
          }
        }
      }
      }
    }
  }

  // A titled label with a filled meter, used for the headline percentages.
  component Meter: Item {
    id: meter

    property string glyph: ""
    property string label: ""
    property string value: ""
    property real fraction: 0

    readonly property bool high: fraction >= 0.85
    readonly property color fillColor: high ? Commons.Color.urgent : root.bar.foreground

    width: parent ? parent.width : 0
    implicitHeight: header.height + Style.space(6) + track.height

    Item {
      id: header
      width: parent.width
      height: Math.max(glyphText.implicitHeight, labelText.implicitHeight, valueText.implicitHeight)

      Text {
        id: glyphText
        textFormat: Text.PlainText
        text: meter.glyph
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: labelText
        textFormat: Text.PlainText
        text: meter.label
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
        anchors.left: glyphText.right
        anchors.leftMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: valueText
        textFormat: Text.PlainText
        text: meter.value
        color: root.bar.foreground
        opacity: 0.85
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.bodySmall
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Rectangle {
      id: track
      anchors.top: header.bottom
      anchors.topMargin: Style.space(6)
      width: parent.width
      height: Math.max(4, Style.space(4))
      radius: height / 2
      color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.14)

      Rectangle {
        width: track.width * Math.max(0, Math.min(1, meter.fraction))
        height: parent.height
        radius: parent.radius
        color: meter.fillColor

        Behavior on width {
          NumberAnimation {
            duration: Style.duration(180)
            easing.type: Easing.OutCubic
          }
        }
      }
    }
  }

  component InfoPair: Item {
    id: pair

    property string label: ""
    property string value: ""

    width: parent ? parent.width : 0
    height: Math.max(labelText.implicitHeight, valueText.implicitHeight)

    Text {
      id: labelText
      textFormat: Text.PlainText
      text: pair.label
      color: root.bar.foreground
      opacity: 0.6
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.bodySmall
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: valueText
      textFormat: Text.PlainText
      text: pair.value
      color: root.bar.foreground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.bodySmall
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
    }
  }
}
