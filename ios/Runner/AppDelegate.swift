import UIKit
import Flutter
import GoogleMaps   // ⬅️ important pour GMSServices

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    // 🔑 Initialisation Google Maps : doit être DANS la méthode
    GMSServices.provideAPIKey("AIzaSyA_-00rdj9W8AMt-ybpDpvJbnPhMHt2MVI")

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
