#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    @MainActor
    @Observable
    final class PairedDevicesModel {
        private let client: (any ControlAPIClient)?
        private(set) var state: PairingState?
        private(set) var error: ControlAPIError?
        private(set) var notice: String?
        private(set) var isLoading = false
        private(set) var isRevoking = false
        var pendingPhone: ConfirmedPairedPhone?

        init(client: (any ControlAPIClient)?) {
            self.client = client
        }

        var phones: [ConfirmedPairedPhone]? { state?.confirmedPhones }
        var canRevoke: Bool { phones != nil && error == nil && !isLoading && !isRevoking }

        func load() async {
            guard !isLoading, !isRevoking else { return }
            isLoading = true
            defer { isLoading = false }
            notice = nil
            do {
                state = try await availableClient().pairingState()
                error = nil
            } catch {
                self.error = error
            }
        }

        func requestRevoke(_ phone: ConfirmedPairedPhone) {
            guard canRevoke, phones?.contains(phone) == true else { return }
            pendingPhone = phone
        }

        func cancelRevoke() {
            guard !isRevoking else { return }
            pendingPhone = nil
        }

        func confirmRevoke() async {
            guard canRevoke, let phone = pendingPhone else { return }
            isRevoking = true
            notice = nil
            defer { isRevoking = false; pendingPhone = nil }
            do {
                let client = try availableClient()
                let fresh = try await client.pairingState()
                state = fresh
                guard fresh.confirmedPhones?.contains(phone) == true else {
                    notice = "The device list changed. Review the refreshed list before unpairing a phone."
                    return
                }
                do {
                    _ = try await client.revokePairedPhone(id: phone.phoneId)
                } catch {
                    self.error = error
                    // A failed request may have committed before the reply was lost. Read again;
                    // never make an optimistic removal from the old list.
                    state = try? await client.pairingState()
                    notice = "Could not confirm the revocation. Check the device list before trying again."
                    return
                }
                do {
                    state = try await client.pairingState()
                    guard let phones = state?.confirmedPhones else {
                        throw ControlAPIError
                            .malformedResponse(detail: "the router omitted the confirmed-device list")
                    }
                    guard !phones.contains(where: { $0.phoneId == phone.phoneId }) else {
                        throw ControlAPIError
                            .malformedResponse(detail: "the router still lists this phone as confirmed")
                    }
                    error = nil
                    notice = "\(phone.phoneName) is no longer paired with this Mac."
                } catch {
                    state = nil
                    self.error = (error as? ControlAPIError)
                        ?? .malformedResponse(detail: "the device list could not be verified")
                    notice = """
                    The router confirmed the revocation, but the device list could not be verified. \
                    Refresh to check it.
                    """
                }
            } catch {
                self.error = error
            }
        }

        private func availableClient() throws(ControlAPIError) -> any ControlAPIClient {
            guard let client else {
                throw .malformedResponse(detail: "this view has no device-management API client")
            }
            return client
        }
    }
#endif
