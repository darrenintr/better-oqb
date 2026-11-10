import Flutter
import UIKit

public class OqbPencilBridgePlugin: NSObject, FlutterPlugin, UIPencilInteractionDelegate {
  private var channel: FlutterMethodChannel!
  private weak var hostView: UIView?
  private var pencil: UIPencilInteraction?
  private weak var controller: UIViewController?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = OqbPencilBridgePlugin()
    instance.channel = FlutterMethodChannel(name: "better_oqb/pencil", binaryMessenger: registrar.messenger())
    instance.controller = registrar.viewController
    registrar.addMethodCallDelegate(instance, channel: instance.channel)
  }
  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "enable":
      let activeRoot = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .filter { $0.activationState == .foregroundActive }
        .flatMap { $0.windows }.first { $0.isKeyWindow }?.rootViewController
      let host = controller ?? activeRoot
      if pencil == nil, let view = host?.view {
        let interaction = UIPencilInteraction()
        interaction.delegate = self
        view.addInteraction(interaction)
        pencil = interaction
        hostView = view
      }
      result(pencil != nil)
    case "disable":
      if let interaction = pencil { hostView?.removeInteraction(interaction) }
      pencil = nil
      result(nil)
    default: result(FlutterMethodNotImplemented)
    }
  }
  private func tap() {
    switch UIPencilInteraction.preferredTapAction {
    case .ignore: break
    case .showColorPalette: channel.invokeMethod("palette", arguments: nil)
    default: channel.invokeMethod("toggleEraser", arguments: nil)
    }
  }
  public func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
    if #available(iOS 17.5, *) { return }
    tap()
  }
  @available(iOS 17.5, *)
  public func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
    self.tap()
  }
  @available(iOS 17.5, *)
  public func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
    if squeeze.phase == .ended && UIPencilInteraction.preferredSqueezeAction != .ignore {
      channel.invokeMethod("palette", arguments: nil)
    }
  }
}
