import ArgumentParser

@main
struct ClaudeZellijWhip: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "claude-zellij-whip",
    abstract: "A Swift command-line tool"
  )

  @Flag(name: .shortAndLong, help: "Enable verbose output")
  var verbose: Bool = false

  mutating func run() throws {
    if verbose {
      print("Running in verbose mode")
    }
    print("Hello, world!")
  }
}
