#!/usr/bin/env ruby

# Compile the production capture lifecycle with a synthetic context service.
abort "usage: #{$PROGRAM_NAME} source output" unless ARGV.length == 2
source_path, output_path = ARGV
lines = File.readlines(source_path)
File.write(output_path, "// Generated from AppState.swift; do not edit.\nimport Foundation\n")

context_names = %w[startContextCapture contextForTranscription contextForPublication disabledContext]
context_methods = context_names.map do |name|
  start = lines.index { |line| line.match?(/^    private (?:static )?func #{name}\b/) }
  abort "missing context method #{name}" unless start
  finish = ((start + 1)...lines.length).find { |index| lines[index] == "    }\n" }
  lines[start..finish].join.sub("private ", "")
end
start = lines.index { |line| line.include?("@Published var contextCaptureEnabled: Bool {") }
finish = ((start + 1)...lines.length).find { |index| lines[index] == "    }\n" }
preference = lines[start..finish].join.gsub("@Published ", "").gsub("UserDefaults.standard", "defaults")
default_start = lines.index { |line| line.include?("let contextCaptureEnabled = UserDefaults.standard.object(") }
abort "missing context preference default" unless default_start
load_preference = lines[default_start, 3].join.gsub("UserDefaults.standard", "defaults")
File.open(output_path, "a") do |file|
  file.write("\n@MainActor final class TestContextState {\n")
  file.write("    let defaults: UserDefaults\n    let contextCaptureEnabledStorageKey = \"context_capture_enabled\"\n")
  file.write(preference)
  file.write(<<~SWIFT)
      let contextService = TestContextService()
      var contextCaptureGeneration = UUID()
      var contextCaptureTask: Task<AppContext?, Never>?
      var capturedContext: AppContext?
      var lastContextSummary = ""
      var lastPostProcessingStatus = ""
      var lastContextScreenshotDataURL: String?
      var lastContextScreenshotStatus = ""
      var lastContextAppName = ""
      var lastContextBundleIdentifier = ""
      var lastContextWindowTitle = ""
      var lastContextSelectedText = ""
      var lastContextLLMPrompt = ""
      var screenshotIssueCalls = 0
      init(defaults: UserDefaults) {
          self.defaults = defaults
#{load_preference}
          self.contextCaptureEnabled = contextCaptureEnabled
      }
      func handleScreenshotCaptureIssue(_ message: String?) { screenshotIssueCalls += 1 }
      func fallbackContextAtStop() -> AppContext { Self.disabledContext() }
  SWIFT
  file.write(context_methods.join("\n"))
  file.write("\n}\n")
end
