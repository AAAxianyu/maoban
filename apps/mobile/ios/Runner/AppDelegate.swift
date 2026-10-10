import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var pushChannel: FlutterMethodChannel?
  private var registrationResult: FlutterResult?
  private var deviceToken: String?
  private var pendingTap: [String: String]?

  override func application(_ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "MiaobanPush") else { return }
    let channel = FlutterMethodChannel(name: "com.miaoban/push", binaryMessenger: registrar.messenger())
    pushChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      if call.method == "register" {
        if let token = self.deviceToken { result(token); return }
        self.registrationResult = result
        UIApplication.shared.registerForRemoteNotifications()
      } else if call.method == "initialNotification" {
        result(self.pendingTap)
        self.pendingTap = nil
      } else { result(FlutterMethodNotImplemented) }
    }
  }

  override func application(_ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    self.deviceToken = deviceToken.map { String(format: "%02x", $0) }.joined()
    registrationResult?(self.deviceToken)
    registrationResult = nil
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(_ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error) {
    registrationResult?(FlutterError(code: "APNS_REGISTRATION_FAILED",
      message: "推送注册未完成，请检查签名和设备网络", details: nil))
    registrationResult = nil
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  override func userNotificationCenter(_ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
    let info = response.notification.request.content.userInfo
    var payload: [String: String] = [:]
    for key in ["space_id", "entity_id", "notification_id"] {
      if let value = info[key] as? String { payload[key] = value }
    }
    if !payload.isEmpty {
      pendingTap = payload
      pushChannel?.invokeMethod("notificationTap", arguments: payload)
    }
    super.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
  }
}
