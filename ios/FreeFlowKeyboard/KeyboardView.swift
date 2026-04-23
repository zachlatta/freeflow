import SwiftUI

enum KeyboardState: Equatable {
    case idle
    case idleNotPrimed
    case idlePrimed(expiresAt: Date?)
    case opening
    case recording
    case transcribing
    case error(String)
    case success(String)
}

struct KeyboardView: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        ZStack {
            Color(.systemGray6).ignoresSafeArea()
            if case .error(let message) = model.state {
                errorView(message: message)
            } else {
                normalView
            }
        }
    }

    private var normalView: some View {
        VStack(spacing: 12) {
            statusRow
            Spacer()
            micButton
            Spacer()
            bottomRow
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Error", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.red)
                Spacer()
                Button("Dismiss") { model.state = .idle }
            }
            ScrollView(.vertical) {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                Button {
                    model.onAdvanceKeyboard?()
                } label: {
                    Image(systemName: "globe").font(.title2).frame(width: 44, height: 44)
                }
                Spacer()
                Button("Try again") { model.state = .idle }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            Text(statusText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var statusText: String {
        if let warning = model.warning { return warning }
        switch model.state {
        case .idle: return "Tap the mic"
        case .idleNotPrimed: return "Tap the mic — FreeFlow will open briefly to prime the session, then return to this app."
        case .idlePrimed(let expiresAt):
            if let expiresAt {
                let remaining = max(0, Int(expiresAt.timeIntervalSinceNow))
                return "Ready to dictate — session stays primed for \(remaining)s. Tap mic to record."
            }
            return "Ready to dictate — tap mic."
        case .opening: return "Opening FreeFlow…"
        case .recording: return "Listening… tap to stop."
        case .transcribing: return "Transcribing…"
        case .success(let m): return m
        case .error(let m): return m
        }
    }

    private var statusColor: Color {
        switch model.state {
        case .idle, .idleNotPrimed: return .orange
        case .idlePrimed: return .green
        case .opening, .transcribing: return .blue
        case .recording: return .red
        case .success: return .green
        case .error: return .red
        }
    }

    private var micButton: some View {
        Button {
            model.toggleRecording()
        } label: {
            ZStack {
                Circle()
                    .fill(recordingColor)
                    .frame(width: 120, height: 120)
                Image(systemName: micIcon)
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .disabled(!model.canTapMic)
        .opacity(model.canTapMic ? 1.0 : 0.5)
    }

    private var micIcon: String {
        switch model.state {
        case .recording: return "stop.fill"
        case .opening, .transcribing: return "hourglass"
        case .idleNotPrimed: return "arrow.up.right.square"
        default: return "mic.fill"
        }
    }

    private var recordingColor: Color {
        switch model.state {
        case .recording: return .red
        case .opening, .transcribing: return .gray
        case .error: return .red.opacity(0.5)
        case .idleNotPrimed: return .orange
        case .idlePrimed: return .green
        default: return .accentColor
        }
    }

    private var bottomRow: some View {
        HStack {
            Button {
                model.onAdvanceKeyboard?()
            } label: {
                Image(systemName: "globe").font(.title2).frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            Spacer()
            Button {
                model.onBackspace?()
            } label: {
                Image(systemName: "delete.left").font(.title2).frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5)
                    .onEnded { _ in model.onBackspaceHold?() }
            )
        }
    }
}

final class KeyboardModel: ObservableObject {
    @Published var state: KeyboardState = .idle
    @Published var warning: String?
    @Published var canTapMic: Bool = true

    var onToggleRecording: (() -> Void)?
    var onAdvanceKeyboard: (() -> Void)?
    var onBackspace: (() -> Void)?
    var onBackspaceHold: (() -> Void)?
    var onOpenApp: (() -> Void)?

    func toggleRecording() { onToggleRecording?() }
}
