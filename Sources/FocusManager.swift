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

func focusTerminal(_ terminal: Terminal) {
  let app = NSWorkspace.shared.runningApplications
    .first { $0.bundleIdentifier == terminal.bundleIdentifier }
  app?.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
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
