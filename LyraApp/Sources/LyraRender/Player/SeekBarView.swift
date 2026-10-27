import SwiftUI
import LyraCore

/// The player's progress bar: elapsed time, a scrubbable track and time remaining.
///
/// It reads the playback clock from the session about five times a second. Clicking or dragging
/// shows the target time while you scrub and seeks on release; the lyrics jump straight away
/// because the session's clock is moved immediately instead of waiting for the next poll.
struct SeekBarView: View {
    /// The current playback state; read about five times a second.
    let snapshot: () -> PlaybackSnapshot
    /// Called with the target time and the track when the user clicks or releases a drag.
    let onSeek: (TimeInterval, Track) -> Void
    @State private var scrubFraction: Double?
    @State private var hovering = false

    private let trackHeight: CGFloat = 4
    private let activeTrackHeight: CGFloat = 7
    private let thumb: CGFloat = 13

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { _ in
            let current = snapshot()
            let track = current.track
            let bar = SeekBar(duration: track?.duration ?? 0)
            let live = current.position()
            let fraction = scrubFraction ?? bar.fraction(position: live)
            let shown = scrubFraction.map(bar.time(forFraction:)) ?? live
            let active = (hovering || scrubFraction != nil) && bar.isSeekable

            HStack(spacing: 10) {
                Text(SeekBar.format(shown))
                    .frame(width: 46, alignment: .trailing)
                trackView(fraction: fraction, active: active, bar: bar, track: track)
                Text(bar.remainingText(position: shown))
                    .frame(width: 52, alignment: .leading)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(bar.isSeekable ? 0.85 : 0.45))
            .shadow(color: .black.opacity(0.5), radius: 2)
            .opacity(track == nil ? 0 : 1)   // nothing to scrub when nothing is loaded
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Playback position")
            .accessibilityValue("\(SeekBar.format(shown)) of \(SeekBar.format(bar.duration))")
            .accessibilityAdjustableAction { direction in
                guard let track, bar.isSeekable else { return }
                let step = direction == .increment ? SeekBar.nudge : -SeekBar.nudge
                seek(to: min(bar.duration, max(0, live + step)), track: track)
            }
        }
    }

    private func trackView(fraction: Double, active: Bool, bar: SeekBar, track: Track?) -> some View {
        GeometryReader { geo in
            let height = active ? activeTrackHeight : trackHeight
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25))
                Capsule().fill(.white.opacity(0.95))
                    .frame(width: max(0, geo.size.width * fraction))
                if active {
                    Circle().fill(.white)
                        .frame(width: thumb, height: thumb)
                        .shadow(color: .black.opacity(0.4), radius: 3)
                        .offset(x: geo.size.width * fraction - thumb / 2)
                }
            }
            .frame(height: height)
            .frame(maxHeight: .infinity)   // centered in the taller hit area
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard bar.isSeekable else { return }
                        scrubFraction = bar.fraction(forX: value.location.x, width: geo.size.width)
                    }
                    .onEnded { value in
                        defer { scrubFraction = nil }
                        guard bar.isSeekable, let track else { return }
                        let target = bar.time(forFraction: bar.fraction(forX: value.location.x, width: geo.size.width))
                        seek(to: target, track: track)
                    }
            )
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: active)
        }
        .frame(height: 22)   // a taller target than the thin visible bar
        .allowsHitTesting(bar.isSeekable)
    }

    private func seek(to seconds: TimeInterval, track: Track) {
        onSeek(seconds, track)
    }
}
