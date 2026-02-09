import AppKit

enum Terminal: String, CaseIterable {
  case ghostty
  case wezterm
  case iterm2
  case kitty

  var bundleIdentifier: String {
    switch self {
    case .ghostty: return "com.mitchellh.ghostty"
    case .wezterm: return "com.github.wez.wezterm"
    case .iterm2: return "com.googlecode.iterm2"
    case .kitty: return "net.kovidgoyal.kitty"
    }
  }

  init?(fromArg value: String) {
    switch value.lowercased() {
    case "ghostty": self = .ghostty
    case "wezterm": self = .wezterm
    case "iterm2", "iterm": self = .iterm2
    case "kitty": self = .kitty
    default: return nil
    }
  }
}

func focusTerminal(_ terminal: Terminal, weztermPaneId: String? = nil) {
  let app = NSWorkspace.shared.runningApplications
    .first { $0.bundleIdentifier == terminal.bundleIdentifier }
  app?.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])

  if terminal == .wezterm, let paneId = weztermPaneId, !paneId.isEmpty {
    focusWezTermPane(paneId: paneId)
  }
}

func focusZellijTab(session: String, tabName: String, paneId: String?) {
  guard let zellijPath = findZellijPath() else { return }

  let process = Process()
  process.executableURL = URL(fileURLWithPath: zellijPath)
  process.arguments = ["--session", session, "action", "go-to-tab-name", tabName]
  process.standardOutput = FileHandle.nullDevice
  process.standardError = FileHandle.nullDevice

  do {
    try process.run()
    process.waitUntilExit()
  } catch {
    return
  }

  if let paneId = paneId, !paneId.isEmpty {
    focusZellijPane(session: session, paneId: paneId)
  }
}

private func focusZellijPane(session: String, paneId: String) {
  guard let zellijPath = findZellijPath() else { return }

  let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
  let pluginPath = "file:\(homeDir)/.config/zellij/plugins/room.wasm"

  let process = Process()
  process.executableURL = URL(fileURLWithPath: zellijPath)
  process.arguments = [
    "--session", session,
    "pipe",
    "--plugin", pluginPath,
    "--name", "focus-pane",
    "--", paneId,
  ]
  process.standardOutput = FileHandle.nullDevice
  process.standardError = FileHandle.nullDevice

  try? process.run()
  process.waitUntilExit()
}

// MARK: - WezTerm tab/pane focusing

private let weztermPaths = [
  "/opt/homebrew/bin/wezterm",
  "/usr/local/bin/wezterm",
  "/Applications/WezTerm.app/Contents/MacOS/wezterm",
]

private func findWezTermPath() -> String? {
  weztermPaths.first { FileManager.default.fileExists(atPath: $0) }
}

private func focusWezTermPane(paneId: String) {
  guard let weztermPath = findWezTermPath() else { return }
  guard let paneIdInt = Int(paneId) else { return }

  // Get pane list to find the tab_id for this pane
  let listProcess = Process()
  listProcess.executableURL = URL(fileURLWithPath: weztermPath)
  listProcess.arguments = ["cli", "list", "--format", "json"]

  let pipe = Pipe()
  listProcess.standardOutput = pipe
  listProcess.standardError = FileHandle.nullDevice

  do {
    try listProcess.run()
    listProcess.waitUntilExit()
  } catch {
    return
  }

  let data = pipe.fileHandleForReading.readDataToEndOfFile()

  guard let panes = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
    return
  }

  guard let paneEntry = panes.first(where: { ($0["pane_id"] as? Int) == paneIdInt }),
    let tabId = paneEntry["tab_id"] as? Int
  else {
    return
  }

  // Activate the tab first, then the pane
  let tabProcess = Process()
  tabProcess.executableURL = URL(fileURLWithPath: weztermPath)
  tabProcess.arguments = ["cli", "activate-tab", "--tab-id", String(tabId)]
  tabProcess.standardOutput = FileHandle.nullDevice
  tabProcess.standardError = FileHandle.nullDevice
  try? tabProcess.run()
  tabProcess.waitUntilExit()

  let paneProcess = Process()
  paneProcess.executableURL = URL(fileURLWithPath: weztermPath)
  paneProcess.arguments = ["cli", "activate-pane", "--pane-id", paneId]
  paneProcess.standardOutput = FileHandle.nullDevice
  paneProcess.standardError = FileHandle.nullDevice
  try? paneProcess.run()
  paneProcess.waitUntilExit()
}
