import ActivityKit
import SwiftUI
import WidgetKit

@main
struct RouteAlertLiveActivityBundle: WidgetBundle {
  var body: some Widget {
    RouteAlertLiveActivityWidget()
  }
}

typealias TrackingState = RouteAlertActivityAttributes.ContentState

private enum Palette {
  static let background = Color(red: 0.07, green: 0.09, blue: 0.13)

  static func accent(_ phase: String) -> Color {
    switch phase {
    case "pending": return Color(red: 1.0, green: 0.72, blue: 0.22)
    case "enroute": return Color(red: 0.95, green: 0.27, blue: 0.27)
    case "near": return Color(red: 1.0, green: 0.52, blue: 0.12)
    case "arrived", "done": return Color(red: 0.16, green: 0.78, blue: 0.48)
    default: return Color(red: 0.0, green: 0.66, blue: 0.59)  // transport — สีหลักของแอป
    }
  }

  static func symbol(_ phase: String) -> String {
    switch phase {
    case "pending": return "hourglass"
    case "arrived": return "checkmark.circle.fill"
    case "done": return "checkmark.seal.fill"
    case "transport": return "cross.circle.fill"
    default: return "cross.case.fill"
    }
  }
}

private enum Formatting {
  static func distance(_ meters: Int?) -> String? {
    guard let meters else { return nil }
    if meters >= 1000 { return String(format: "%.1f กม.", Double(meters) / 1000) }
    return "\(meters) ม."
  }

  static func shortEta(_ state: TrackingState) -> String {
    if let eta = state.etaMinutes { return "\(eta) น." }
    switch state.phase {
    case "arrived", "done": return "ถึงแล้ว"
    case "pending": return "รอ"
    default: return "…"
    }
  }
}

struct RouteAlertLiveActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: RouteAlertActivityAttributes.self) { context in
      LockScreenView(state: context.state, isStale: context.isStale)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .activityBackgroundTint(Palette.background)
        .activitySystemActionForegroundColor(.white)
    } dynamicIsland: { context in
      let state = context.state
      let accent = Palette.accent(state.phase)
      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          HStack(spacing: 6) {
            PhaseIcon(phase: state.phase, size: 15)
            Text(state.subtitle)
              .font(.caption.weight(.semibold))
              .foregroundStyle(.white.opacity(0.85))
              .lineLimit(1)
          }
          .padding(.leading, 4)
        }
        DynamicIslandExpandedRegion(.trailing) {
          EtaView(state: state, numberSize: 26)
            .padding(.trailing, 4)
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(alignment: .leading, spacing: 10) {
            Text(state.title)
              .font(.system(size: 16, weight: .bold))
              .foregroundStyle(.white)
              .lineLimit(1)
            RouteProgressBar(progress: state.progress, tint: accent)
          }
          .padding(.horizontal, 4)
          .padding(.bottom, 2)
        }
      } compactLeading: {
        PhaseIcon(phase: state.phase, size: 14)
      } compactTrailing: {
        Text(Formatting.shortEta(state))
          .font(.system(size: 13, weight: .bold, design: .rounded))
          .monospacedDigit()
          .foregroundStyle(accent)
      } minimal: {
        PhaseIcon(phase: state.phase, size: 13)
      }
      .keylineTint(accent)
    }
  }
}

private struct PhaseIcon: View {
  let phase: String
  let size: CGFloat

  var body: some View {
    Image(systemName: Palette.symbol(phase))
      .font(.system(size: size, weight: .bold))
      .foregroundStyle(Palette.accent(phase))
  }
}

private struct EtaView: View {
  let state: TrackingState
  let numberSize: CGFloat

  var body: some View {
    VStack(alignment: .trailing, spacing: 0) {
      if let eta = state.etaMinutes {
        Text("\(eta)")
          .font(.system(size: numberSize, weight: .heavy, design: .rounded))
          .monospacedDigit()
          .foregroundStyle(.white)
          .contentTransition(.numericText())
        Text("นาที")
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.white.opacity(0.7))
      } else if state.phase == "arrived" || state.phase == "done" {
        Text("ถึงแล้ว")
          .font(.system(size: numberSize * 0.62, weight: .heavy, design: .rounded))
          .foregroundStyle(Palette.accent(state.phase))
      } else {
        Text("–")
          .font(.system(size: numberSize, weight: .heavy, design: .rounded))
          .foregroundStyle(.white.opacity(0.5))
      }
    }
  }
}

// เส้นทางจากรถ → จุดหมาย: รถขยับไปทางขวาตามความคืบหน้า (เหมือนแอปเรียกรถ)
private struct RouteProgressBar: View {
  let progress: Double
  let tint: Color

  var body: some View {
    GeometryReader { geo in
      let width = geo.size.width
      let clamped = min(max(progress, 0), 1)
      let markerSize: CGFloat = 22
      let travel = max(width - markerSize, 0)
      ZStack(alignment: .leading) {
        Capsule()
          .fill(Color.white.opacity(0.16))
          .frame(height: 6)
        Capsule()
          .fill(tint)
          .frame(width: max(markerSize / 2 + clamped * travel, 6), height: 6)
        Image(systemName: "mappin.circle.fill")
          .font(.system(size: 18, weight: .bold))
          .foregroundStyle(.white.opacity(0.9))
          .frame(maxWidth: .infinity, alignment: .trailing)
        Image(systemName: "car.side.fill")
          .font(.system(size: 11, weight: .bold))
          .foregroundStyle(.white)
          .frame(width: markerSize, height: markerSize)
          .background(Circle().fill(tint))
          .overlay(Circle().stroke(Palette.background, lineWidth: 2))
          .offset(x: clamped * travel)
      }
      .frame(height: markerSize)
    }
    .frame(height: 22)
  }
}

private struct LockScreenView: View {
  let state: TrackingState
  let isStale: Bool

  var body: some View {
    let accent = Palette.accent(state.phase)
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .center, spacing: 12) {
        PhaseIcon(phase: state.phase, size: 18)
          .frame(width: 40, height: 40)
          .background(Circle().fill(accent.opacity(0.18)))
        VStack(alignment: .leading, spacing: 3) {
          Text(state.title)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(1)
          HStack(spacing: 6) {
            Text(state.subtitle).lineLimit(1)
            if let distance = Formatting.distance(state.distanceMeters) {
              Text("·")
              Text(distance).monospacedDigit()
            }
          }
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(.white.opacity(0.68))
        }
        Spacer(minLength: 8)
        EtaView(state: state, numberSize: 30)
      }
      RouteProgressBar(progress: state.progress, tint: accent)
      HStack(spacing: 4) {
        Text("RouteAlert")
          .font(.caption2.weight(.bold))
          .foregroundStyle(.white.opacity(0.45))
        if isStale {
          Text("· กำลังรอตำแหน่งล่าสุดของรถ")
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.45))
        }
      }
    }
  }
}
