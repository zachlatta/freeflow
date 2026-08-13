# FreeFlow for Windows

Native Windows port of FreeFlow - a free and open source voice dictation application. Provides AI-powered voice-to-text transcription using Whisper API with LLM post-processing for transcript cleanup.

## Features

FreeFlow for Windows provides full feature parity with the macOS version:

### Core Functionality
- **Voice dictation** with AI-powered transcription (Whisper API)
- **LLM post-processing** for transcript cleanup and formatting
- **Hold-to-talk mode** - Hold `Ctrl+Shift+Space` to dictate
- **Toggle mode** - Tap `Ctrl+Alt+Space` to start/stop dictation
- **Automatic paste** - Transcribed text is automatically pasted into the active application

### System Tray
- **Menu bar icon** with status indicators (idle, recording, processing)
- **Theme adaptation** - Icons automatically adjust to Windows light/dark theme
- **Dev build indicator** - Stamped icon for development builds (matching macOS)
- **Full context menu** matching macOS MenuBarView:
  - Status display (Recording.../Processing.../shortcut hint)
  - Start/Stop Dictating
  - Paste Again with last transcript preview
  - Transcript history (last 10 items)
  - Paste Custom Word to Vocabulary
  - Hold/Toggle/Paste Again Shortcut submenus
  - Microphone selection
  - Re-run Setup
  - Settings
  - Check for Updates
  - Show Menu Bar Icon toggle

### Recording Indicator
- **Compact overlay** matching macOS RecordingOverlay design
- **92×38px pill** with black background and rounded corners
- **9-bar waveform** animation during recording
- **Initializing dots** animation (3 dots)
- **Processing bars** animation during transcription
- **Stop button** for manual recording stop
- **Error indicator** (X icon) for error states

### Settings Window
Full settings UI with 5 tabs matching macOS SettingsView:

1. **General** - API configuration, shortcuts, microphone selection, language settings
2. **Prompts** - Post-processing mode, custom vocabulary, system prompts
3. **Macros** - Voice macro configuration (coming soon)
4. **Run Log** - Transcript history and debugging
5. **Debug** - Debug overlay, update testing, log management

### Settings Behavior
- **Auto-save** - All settings are saved immediately when changed (300ms debounce)
- **Immediate apply** - Hotkeys and other settings take effect instantly
- **No save button required** - Matches macOS auto-save behavior

### Security
- **Windows Credential Manager** - API keys stored securely
- **No plain-text storage** - Credentials never written to disk in plain text

## Prerequisites

- Windows 10 or Windows 11
- .NET 8.0 SDK (for building from source only)

## Installation

### Option 1: Download Pre-built Release (Recommended)

1. Download `FreeFlow-Windows-x.x.x-win-x64.zip` from the [releases page](https://github.com/zachlatta/freeflow/releases)
2. Extract the ZIP file to a folder of your choice (e.g., `C:\Program Files\FreeFlow\`)
3. Run `FreeFlow.exe`
4. The app will appear in your system tray

**Note:** The release is a self-contained single-file executable (~85MB). No .NET runtime installation required.

### Option 2: Build from Source

See the [Building](#building) section below.

## Project Structure

```
FreeFlowWindows/
├── FreeFlowWindows.sln              # Solution file
├── .env                             # API keys (gitignored)
├── FreeFlowWindows.App/             # WPF application
│   ├── App.xaml(.cs)                # Application entry point
│   ├── AppState.cs                  # Application state management
│   ├── Services/                    # App-level services
│   │   ├── SystemTrayManager.cs     # Tray icon and menu
│   │   └── WpfHotkeyManager.cs      # Global hotkey handling
│   ├── ViewModels/                  # MVVM ViewModels
│   │   └── SettingsViewModel.cs     # Settings UI logic
│   ├── Windows/                     # WPF Windows
│   │   ├── SettingsWindow.xaml(.cs) # Settings UI
│   │   └── RecordingIndicator.xaml  # Recording overlay
│   └── Resources/                   # Icons and assets
├── FreeFlowWindows.Core/            # Core library (platform-agnostic)
│   ├── Interfaces/                  # Service contracts
│   ├── Models/                      # Data models
│   └── Services/                    # Core service implementations
│       ├── AudioRecorder.cs         # NAudio-based recording
│       ├── TranscriptionService.cs  # Whisper API client
│       ├── PostProcessingService.cs # LLM post-processing
│       ├── PipelineOrchestrator.cs  # Recording pipeline
│       ├── ClipboardManager.cs      # Clipboard operations
│       ├── CredentialStore.cs       # Secure credential storage
│       └── SettingsManager.cs       # Settings persistence
└── FreeFlowWindows.Tests/           # Unit tests
    └── *.cs                         # xUnit + FsCheck tests
```

## Building

### Development Build

```bash
cd FreeFlowWindows
dotnet restore
dotnet build
```

### Release Build

To create a distributable release:

```powershell
cd FreeFlowWindows
.\build-release.ps1
```

Or use the batch file wrapper:

```cmd
cd FreeFlowWindows
build-release.cmd
```

Build options:
- `-Version "1.2.3"` - Set version number (default: 1.0.0)
- `-SkipTests` - Skip running tests
- `-X64Only` - Build only for x64 (skip ARM64)
- `-Arm64Only` - Build only for ARM64 (skip x64)

The release builds will be created in `FreeFlowWindows/releases/v{version}/`.

## Running

```bash
dotnet run --project FreeFlowWindows.App
```

Or build and run the executable directly:

```bash
dotnet build -c Release
./FreeFlowWindows.App/bin/Release/net8.0-windows10.0.19041/FreeFlowWindows.exe
```

## Running Tests

```bash
dotnet test
```

Tests include:
- Unit tests for core services
- Property-based tests using FsCheck
- ViewModel tests for settings logic

## Configuration

### API Key Setup

1. Get a free API key from [groq.com](https://groq.com/)
2. Either:
   - Create a `.env` file in the `FreeFlowWindows/` directory with: `GROQ_API_KEY=your_key_here`
   - Or enter your API key in Settings → General → API Key

### Default Hotkeys

| Action | Hotkey |
|--------|--------|
| Hold to dictate | `Ctrl+Shift+Space` |
| Toggle dictation | `Ctrl+Alt+Space` |

Hotkeys can be customized in Settings or via the tray menu.

## NuGet Packages

### Application
| Package | Version | Purpose |
|---------|---------|---------|
| NAudio | 2.2.1 | Audio capture and processing |
| Hardcodet.NotifyIcon.Wpf | 1.1.0 | System tray integration |
| InputSimulatorStandard | 1.0.0 | Keyboard simulation for paste |
| Microsoft.Extensions.DependencyInjection | 8.0.0 | Dependency injection |
| System.Text.Json | 8.0.0 | JSON serialization |

### Testing
| Package | Version | Purpose |
|---------|---------|---------|
| xUnit | 2.6.2 | Test framework |
| xUnit.runner.visualstudio | 2.5.4 | Test runner |
| FsCheck | 2.16.6 | Property-based testing |
| FsCheck.Xunit | 2.16.6 | FsCheck/xUnit integration |
| Moq | 4.20.70 | Mocking framework |

## Debugging

Debug logs are written to: `%TEMP%\freeflow_debug.log`

To view the log:
1. Open Settings → Debug tab
2. Click "Open Debug Log"

Or manually:
```powershell
notepad $env:TEMP\freeflow_debug.log
```

## Architecture

The application follows a clean architecture pattern:

- **FreeFlowWindows.Core** - Platform-agnostic business logic and interfaces
- **FreeFlowWindows.App** - WPF-specific UI and Windows integration
- **Dependency Injection** - Services registered via Microsoft.Extensions.DependencyInjection
- **MVVM Pattern** - ViewModels for testable UI logic
- **Event-driven** - Pipeline orchestrator uses events for state changes

### Key Components

1. **PipelineOrchestrator** - Coordinates the recording → transcription → post-processing → paste flow
2. **WpfHotkeyManager** - Handles WM_HOTKEY messages for global shortcuts
3. **SystemTrayManager** - Manages tray icon, menu, and notifications
4. **SettingsViewModel** - Manages settings UI with auto-save

## Differences from macOS Version

| Feature | macOS | Windows |
|---------|-------|---------|
| Tray/Menu Bar | MenuBarExtra | NotifyIcon |
| Hotkeys | Fn key support | Ctrl/Alt/Shift modifiers |
| Credential Storage | Keychain | Credential Manager |
| Context Reading | Accessibility API | Not yet implemented |
| Edit Mode | Supported | Settings UI only |

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests: `dotnet test`
5. Submit a pull request

## License

See [LICENSE](../LICENSE) in the parent directory.
