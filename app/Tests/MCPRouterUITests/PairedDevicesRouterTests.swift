#if os(macOS)
    import AppKit
    import CryptoKit
    import Foundation
    import MCPRouterKit
    import SwiftUI
    import Testing
    @testable import MCPRouterUI

    @MainActor
    @Suite("Paired devices against a temporary TypeScript router", .serialized)
    struct PairedDevicesRouterTests {
        @Test(
            "a confirmed temporary peer is removed on disk and the other peer remains",
            .enabled(if: ProcessInfo.processInfo.environment["MCPR_DEVICE_ROUTER_TEST"] == "1")
        )
        func realRouterRevoke() async throws {
            let router = try DeviceRouterFixture()
            defer { router.stop() }
            let model = PairedDevicesModel(client: router.client)
            let deadline = ContinuousClock.now.advanced(by: .seconds(10))
            repeat {
                await model.load()
                if model.phones != nil { break }
                try await Task.sleep(for: .milliseconds(25))
            } while router.process.isRunning && ContinuousClock.now < deadline
            let phone = try #require(model.phones?.first)
            #expect(model.phones?.count == 2)
            model.requestRevoke(phone)
            await model.confirmRevoke()
            #expect(model.error == nil)
            #expect(model.phones?.map(\.phoneId) == ["temporary-other"])
            let file = try JSONSerialization
                .jsonObject(with: Data(contentsOf: router.phonesFile)) as? [String: Any]
            let phones = try #require(file?["phones"] as? [[String: String]])
            #expect(phones.map { $0["phoneId"] } == ["temporary-other"])
            #expect(model.state?.listener.enabled == false)
            print("DEVICE-ROUTER confirmed=2 revoked=1 remaining=1 listener=off; temporary fixture only")
        }

        @Test("the populated, empty and unavailable sections and confirmation render offscreen")
        func fixtureRenders() async throws {
            let phone = ConfirmedPairedPhone(
                phoneId: "temporary-one", phoneName: "Luke’s temporary iPhone with a deliberately long name",
                pairedAt: Date(timeIntervalSince1970: 1_793_527_200)
            )
            for (name, phones) in [("populated", [phone]), ("empty", []), ("unavailable", nil)] as [(
                String,
                [ConfirmedPairedPhone]?
            )] {
                let client = RecordingControlAPIClient(
                    wrapping: FixtureControlAPIClient(),
                    pairingStateOverride: { () async throws(ControlAPIError) -> PairingState in
                        PairingState(
                            code: nil,
                            listener: .init(enabled: false, port: nil, advertising: false),
                            confirmedPhones: phones
                        )
                    }
                )
                let model = PairedDevicesModel(client: client)
                await model.load()
                try await render(
                    PairedDevicesSection(devices: model, pairAnother: {}).padding(24),
                    name: name,
                    settled: { !model.isLoading && client.calls.pairingStateReads >= 2 }
                )
                if name == "populated" {
                    model.requestRevoke(phone)
                    try await render(
                        PairedDeviceRevokeSheet(devices: model, phone: phone),
                        name: "confirmation"
                    )
                }
            }
        }

        private func render(
            _ content: some View, name: String, settled: @escaping () -> Bool = { true }
        ) async throws {
            let side = name == "confirmation" ? 512.0 : 680.0
            let height = name == "confirmation" ? 512.0 : 400.0
            let view = NSHostingView(rootView: content
                .frame(width: side, height: height, alignment: .topLeading)
                .background(ColorToken.ground.color)
                .environment(\.colorScheme, .light))
            view.sizingOptions = []
            let frame = NSRect(x: -10000, y: -10000, width: side, height: height)
            let window = NSWindow(
                contentRect: frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.contentView = view
            view.frame = NSRect(origin: .zero, size: frame.size)
            view.layoutSubtreeIfNeeded()
            await Task.yield()
            try await ShellTestSupport.waitUntil(settled)
            view.layoutSubtreeIfNeeded()
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            #expect(bitmap.pixelsWide > 400 && bitmap.pixelsHigh > 100)
            if let directory = ProcessInfo.processInfo.environment["MCPR_DEVICE_SHOTS"] {
                try #require(bitmap.representation(using: .png, properties: [:]))
                    .write(to: URL(fileURLWithPath: directory).appendingPathComponent("devices-\(name).png"))
            }
            window.close()
        }
    }

    private final class DeviceRouterFixture {
        let root: URL
        let process = Process()
        let client: LiveControlAPIClient
        let phonesFile: URL

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("mcpr-devices-" + UUID().uuidString)
            try FileManager.default.createDirectory(
                at: root,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            phonesFile = root.appendingPathComponent("paired-phones.json")
            let token = UUID().uuidString
            try token.write(
                to: root.appendingPathComponent("control.token"),
                atomically: true,
                encoding: .utf8
            )
            try #"{"mcpServers":{},"pairing":{"enabled":false}}"#
                .write(to: root.appendingPathComponent("servers.json"), atomically: true, encoding: .utf8)
            let key = P256.Signing.PrivateKey().publicKey.derRepresentation.base64EncodedString()
            let phones = ["temporary-one", "temporary-other"].map {
                ["phoneId": $0, "phoneName": $0, "phoneKey": key, "pairedAt": "2026-11-01T10:00:00Z"]
            }
            try JSONSerialization.data(withJSONObject: ["phones": phones]).write(to: phonesFile)
            let portProcess = Process()
            portProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            portProcess.arguments = [
                "python3",
                "-c",
                "import socket; s=socket.socket(); s.bind(('127.0.0.1',0)); "
                    + "print(s.getsockname()[1]); s.close()"
            ]
            let pipe = Pipe()
            portProcess.standardOutput = pipe
            try portProcess.run()
            let portData = pipe.fileHandleForReading.readDataToEndOfFile()
            portProcess.waitUntilExit()
            let portText = try #require(String(data: portData, encoding: .utf8))
            let port = try #require(Int(portText.trimmingCharacters(in: .whitespacesAndNewlines)))
            let url = try #require(URL(string: "http://127.0.0.1:\(port)"))
            client = LiveControlAPIClient(
                baseURL: url,
                session: .init(configuration: .ephemeral),
                store: InMemoryTokenStore(token),
                tokenFile: RouterTokenFile(url: root.appendingPathComponent("control.token"))
            )
            let repository = try ShellTestSupport.repoRoot()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [
                "node",
                repository.appendingPathComponent("dist/index.js").path,
                "serve",
                "--port",
                String(port)
            ]
            process.environment = ProcessInfo.processInfo.environment.merging([
                "MCP_ROUTER_HOME": root.path, "MCP_ROUTER_REGISTRY": "http://127.0.0.1:9"
            ]) { _, fixture in fixture }
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
        }

        func stop() {
            if process.isRunning { process.terminate(); process.waitUntilExit() }
            try? FileManager.default.removeItem(at: root)
        }
    }
#endif
