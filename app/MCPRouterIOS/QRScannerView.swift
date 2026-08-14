@preconcurrency import AVFoundation
import MCPRouterKit
import SwiftUI
import UIKit

/// The QR scanner.
///
/// **Metadata only, and that is the structural guarantee rather than a promise in the copy.** The
/// session is configured with exactly one output — an `AVCaptureMetadataOutput` restricted to
/// `.qr` — and no `AVCaptureVideoDataOutput`, no `AVCapturePhotoOutput`, no `AVCaptureMovieFileOutput`.
/// There is therefore no frame buffer to write, nothing to persist and nothing to upload; the
/// scanner receives decoded *strings*, not images. `ScannerOutputTests` asserts the configured
/// outputs, because a promise a test cannot read is a promise that decays.
///
/// The pre-scan surface tells the user "no image is stored or sent anywhere". This class is what
/// makes that sentence true.
final class QRScannerController: UIViewController {
    private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?

    /// Called with each decoded string, on the main actor.
    private let onCode: @MainActor @Sendable (String) -> Void
    private let delegateBox = MetadataDelegate()

    init(onCode: @escaping @MainActor @Sendable (String) -> Void) {
        self.onCode = onCode
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError("not used") }

    /// The only kind of output this scanner will ever add to its session, and the only code type it
    /// will read. `configureSession` builds from these two constants rather than naming the classes
    /// inline, so the test that asserts them is asserting the thing the code actually uses — not a
    /// parallel description of it that is free to drift.
    ///
    /// A metadata output delivers decoded **strings**. There is no `AVCaptureVideoDataOutput` and no
    /// `AVCapturePhotoOutput` here, so no frame is ever produced, which is what makes "no image is
    /// stored or sent anywhere" true by construction rather than by promise.
    static let outputKinds: [AVCaptureOutput.Type] = [AVCaptureMetadataOutput.self]
    static let scannedTypes: [AVMetadataObject.ObjectType] = [.qr]

    /// What the session ended up with. Empty on a simulator, which has no camera — the guarantee is
    /// carried by `outputKinds` above, which is asserted directly.
    private(set) var configuredOutputs: [AVCaptureOutput] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        configureSession()
    }

    private func configureSession() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)

        let metadata = AVCaptureMetadataOutput()
        guard Self.outputKinds.contains(where: { $0 == AVCaptureMetadataOutput.self }),
              session.canAddOutput(metadata) else { return }
        session.addOutput(metadata)
        // Set *after* adding to the session: the available types are empty until then, and
        // assigning `.qr` beforehand traps.
        metadata.metadataObjectTypes = Self.scannedTypes
        delegateBox.onCode = { [onCode] text in
            Task { @MainActor in onCode(text) }
        }
        metadata.setMetadataObjectsDelegate(delegateBox, queue: .main)
        configuredOutputs = session.outputs

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        preview = layer

        // `startRunning` blocks, so it never belongs on the main thread.
        let session = session
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        let session = session
        DispatchQueue.global(qos: .userInitiated).async { session.stopRunning() }
    }

    /// The delegate is a separate object so the callback stays `nonisolated` — `AVFoundation` calls
    /// it from its own queue, and making the view controller itself the delegate would need an
    /// isolation promise this does not have to make.
    private final class MetadataDelegate: NSObject, AVCaptureMetadataOutputObjectsDelegate, @unchecked Sendable {
        // Mutable, but written once during `configureSession` on the main actor and read only on
        // the metadata queue afterwards. That is the whole synchronisation story, stated because
        // `@unchecked Sendable` is a promise and an unexplained one reads as a mistake.
        var onCode: (@Sendable (String) -> Void)?

        func metadataOutput(
            _: AVCaptureMetadataOutput,
            didOutput objects: [AVMetadataObject],
            from _: AVCaptureConnection
        ) {
            for object in objects {
                guard let readable = object as? AVMetadataMachineReadableCodeObject,
                      QRScannerController.scannedTypes.contains(readable.type),
                      let text = readable.stringValue else { continue }
                onCode?(text)
                return
            }
        }
    }
}

/// The scanner as a SwiftUI view.
struct QRScannerView: UIViewControllerRepresentable {
    let onCode: @MainActor @Sendable (String) -> Void

    func makeUIViewController(context _: Context) -> QRScannerController {
        QRScannerController(onCode: onCode)
    }

    func updateUIViewController(_: QRScannerController, context _: Context) {}
}
