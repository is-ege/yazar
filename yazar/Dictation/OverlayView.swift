import SwiftUI

struct OverlayView: View {
    @Bindable var yazar: Yazar
    @Bindable var settings: Settings
    // Drives the entrance animation: the panel keeps this view alive across
    // sessions, so the blur/fade is keyed off the idle transition, not onAppear.
    @State private var visible = false

    static let panelSize = CGSize(width: 420, height: 80)
    static let capsuleAnimationDuration: TimeInterval = 0.3
    private static let capsuleAnimation = Animation.spring(
        duration: capsuleAnimationDuration,
        bounce: 0.25
    )

    var body: some View {
        ZStack {
            Group {
                switch yazar.state {
                case .idle:
                    EmptyView()
                case .warmingUp:
                    ProgressView()
                        .controlSize(.small)
                        .brightness(0.4)
                        .accessibilityLabel("Preparing microphone")
                case .recording:
                    recordingView
                case .transcribing:
                    // The system spinner draws its own grey and ignores .tint, so it
                    // gets lifted toward white with a brightness filter instead.
                    ProgressView()
                        .controlSize(.small)
                        .brightness(0.4)
                case .noSpeech:
                    HStack(spacing: 6) {
                        Image(systemName: "mic.slash")
                        Text("No speech")
                    }
                    .foregroundStyle(.white)
                case .error(let failure):
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(failure.message)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }
                    .foregroundStyle(.white)
                }
            }
            .id(yazar.state)
            .transition(.blurReplace)
        }
        .animation(.easeInOut(duration: 0.18), value: yazar.state)
        .font(.system(size: 13, weight: .regular))
        // The capsule is always dark, so pin the content to dark appearance:
        // the transcribing spinner and the `.secondary` waveform stay light
        // even when the system is in light mode.
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, 12)
        // Entrance: the capsule extends horizontally from a sliver to full width,
        // clipping (not squashing) the content while it grows.
        .frame(width: capsuleSize.width, height: capsuleSize.height)
        .frame(width: capsuleWidth)
        .background(backgroundColor, in: Capsule())
        .opacity(visible ? 1 : 0)
        .clipShape(Capsule())
        // .blur(radius: visible ? 0 : 10)
        .animation(Self.capsuleAnimation, value: capsuleWidth)
        // Pins the capsule to the centre of the panel so the width change
        // expands symmetrically instead of growing from the leading edge.
        .frame(width: Self.panelSize.width, height: Self.panelSize.height, alignment: .center)
        .onChange(of: yazar.state == .idle) { _, idle in
            // Animate both ways so an interrupted entrance reverses smoothly
            // rather than snapping closed.
            visible = !idle
        }
    }

    private var recordingView: some View {
        HStack(spacing: 8) {
            WaveformView(yazar: yazar)
            if settings.showRecordingTimer {
                TimelineView(.periodic(from: .now, by: 0.1)) { context in
                    Text(elapsed(at: context.date), format: .number.precision(.fractionLength(1)))
                        .monospacedDigit()
                }
            }
        }
        .foregroundStyle(.white)
    }

    private var backgroundColor: Color {
        if case .error = yazar.state { return .red.opacity(0.92) }
        return .black.opacity(0.82)
    }

    private var capsuleSize: CGSize {
        switch yazar.state {
        case .error: CGSize(width: 350, height: 35)
        case .noSpeech: CGSize(width: 135, height: 35)
        case .warmingUp, .recording:
            CGSize(width: settings.showRecordingTimer ? 115 : 65, height: 35)
        default: CGSize(width: 115, height: 35)
        }
    }

    private var capsuleWidth: CGFloat {
        visible ? capsuleSize.width : 5
    }

    private func elapsed(at date: Date) -> Double {
        max(0, date.timeIntervalSince(yazar.recordingStartedAt ?? date))
    }
}
