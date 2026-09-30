import ActivityKit
import Flutter
import Foundation

// ช่องทางให้ Flutter สั่งเริ่ม/อัปเดต/จบ Live Activity (หน้าล็อก + Dynamic Island)
// อัปเดตจากแอปเองทั้งหมด ไม่ใช้ push จึงใช้กับบัญชี Apple ฟรีได้
enum LiveActivityBridge {
  // เคสที่ผู้ใช้ปัด Live Activity ทิ้งเอง — ไม่สร้างกลับขึ้นมาใหม่ (จนกว่าแอปจะเปิดใหม่)
  @MainActor private static var dismissedByUser = Set<String>()
  @MainActor private static var endedByApp = Set<String>()

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.routealert/live_activity",
      binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      guard #available(iOS 16.2, *) else {
        result("ios_too_old")
        return
      }
      let args = call.arguments as? [String: Any] ?? [:]
      Task { @MainActor in
        switch call.method {
        case "startOrUpdate":
          result(await startOrUpdate(args))
        case "end":
          await end(args)
          result(true)
        case "endAllExcept":
          await endAll(except: args["incidentId"] as? String ?? "")
          result(true)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }

  @available(iOS 16.2, *)
  @MainActor
  private static func startOrUpdate(_ args: [String: Any]) async -> Any {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return "disabled" }
    let incidentId = args["incidentId"] as? String ?? ""
    if dismissedByUser.contains(incidentId) { return "dismissed" }
    let content = ActivityContent(state: state(from: args), staleDate: staleDate(from: args))

    let activities = Activity<RouteAlertActivityAttributes>.activities
    if let current = activities.first(where: { $0.attributes.incidentId == incidentId }) {
      switch current.activityState {
      case .active, .stale:
        await current.update(content)
        await endAll(except: incidentId)
        return true
      case .dismissed:
        dismissedByUser.insert(incidentId)
        return "dismissed"
      default:
        break  // .ended — สร้างใหม่ด้านล่าง
      }
    }

    await endAll(except: "")
    do {
      let activity = try Activity.request(
        attributes: RouteAlertActivityAttributes(
          incidentId: incidentId,
          incidentType: args["incidentType"] as? String ?? ""),
        content: content,
        pushType: nil)
      endedByApp.remove(incidentId)
      observeDismissal(of: activity, incidentId: incidentId)
      return true
    } catch {
      // มักเป็นเพราะแอปไม่ได้อยู่หน้าจอ — ฝั่ง Flutter จะลองใหม่ตอนเปิดแอปกลับมา
      return FlutterError(
        code: "request_failed", message: error.localizedDescription, details: nil)
    }
  }

  @available(iOS 16.2, *)
  @MainActor
  private static func observeDismissal(
    of activity: Activity<RouteAlertActivityAttributes>, incidentId: String
  ) {
    Task { @MainActor in
      for await state in activity.activityStateUpdates where state == .dismissed {
        if !endedByApp.contains(incidentId) { dismissedByUser.insert(incidentId) }
        break
      }
    }
  }

  @available(iOS 16.2, *)
  @MainActor
  private static func end(_ args: [String: Any]) async {
    let incidentId = args["incidentId"] as? String ?? ""
    let seconds = args["dismissAfterSeconds"] as? Int ?? 0
    let finalContent: ActivityContent<RouteAlertActivityAttributes.ContentState>? =
      args["phase"] is String ? ActivityContent(state: state(from: args), staleDate: nil) : nil
    let policy: ActivityUIDismissalPolicy =
      seconds > 0 ? .after(Date().addingTimeInterval(TimeInterval(seconds))) : .immediate
    for activity in Activity<RouteAlertActivityAttributes>.activities
    where activity.attributes.incidentId == incidentId {
      endedByApp.insert(incidentId)
      await activity.end(finalContent, dismissalPolicy: policy)
    }
  }

  // [except] ว่าง = จบทุกอัน (เช่นของรอบก่อนที่แอปถูกปิดไป หรือตอน logout)
  @available(iOS 16.2, *)
  @MainActor
  private static func endAll(except incidentId: String) async {
    for activity in Activity<RouteAlertActivityAttributes>.activities
    where activity.attributes.incidentId != incidentId || incidentId.isEmpty {
      endedByApp.insert(activity.attributes.incidentId)
      await activity.end(nil, dismissalPolicy: .immediate)
    }
  }

  // เวลาที่ข้อมูลถือว่าเก่า (context.isStale) — ส่งมาจาก Flutter เฉพาะช่วงที่มี ETA
  private static func staleDate(from args: [String: Any]) -> Date? {
    guard let seconds = args["staleInSeconds"] as? Int else { return nil }
    return Date().addingTimeInterval(TimeInterval(seconds))
  }

  @available(iOS 16.2, *)
  private static func state(from args: [String: Any]) -> RouteAlertActivityAttributes.ContentState {
    RouteAlertActivityAttributes.ContentState(
      phase: args["phase"] as? String ?? "pending",
      title: args["title"] as? String ?? "",
      subtitle: args["subtitle"] as? String ?? "",
      etaMinutes: args["etaMinutes"] as? Int,
      distanceMeters: args["distanceMeters"] as? Int,
      progress: (args["progress"] as? NSNumber)?.doubleValue ?? 0)
  }
}
