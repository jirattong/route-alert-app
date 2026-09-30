import ActivityKit
import Foundation

// ใช้ร่วมกันทั้งแอป (Runner) และส่วนเสริม Live Activity — ชื่อ/ฟิลด์ต้องตรงกับ
// TrackingState.toChannelArgs() ใน lib/core/services/live_tracking_service.dart
@available(iOS 16.1, *)
struct RouteAlertActivityAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    // pending | enroute | near | arrived | transport | done
    var phase: String
    var title: String
    var subtitle: String
    var etaMinutes: Int?
    var distanceMeters: Int?
    var progress: Double
  }

  var incidentId: String
  var incidentType: String
}
