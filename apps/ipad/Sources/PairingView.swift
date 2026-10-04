import SwiftUI
import ViewportProtocol
#if canImport(VisionKit)
    import VisionKit
#endif

/// Pair with a Mac: run `mrdpd-host pair` there, then paste the link (Universal Clipboard) or scan it.
struct PairingView: View {
    @EnvironmentObject private var hosts: HostStore
    let onDone: (() -> Void)?
    @State private var manual = ""
    @State private var error: String?
    @State private var scanning = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("On your Mac, run:")
                    Text("mrdpd-host pair --bind <your Mac's Tailscale or LAN IP>")
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                    Text("It copies a pairing link to the Mac's clipboard and shows it as a QR code. The link is a secret key for this iPad only.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Add this iPad") {
                    PasteButton(payloadType: String.self) { strings in
                        if let s = strings.first { accept(s) }
                    }
                    if Self.canScan {
                        Button("Scan the QR code", systemImage: "qrcode.viewfinder") { scanning = true }
                    }
                    TextField("or paste the mrdpd:// link here", text: $manual, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { accept(manual) }
                    Button("Add") { accept(manual) }.disabled(manual.isEmpty)
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Pair with your Mac")
            .toolbar {
                if let onDone { Button("Cancel", action: onDone) }
            }
            .sheet(isPresented: $scanning) {
                QRScannerView { code in
                    scanning = false
                    accept(code)
                }
            }
        }
    }

    private func accept(_ text: String) {
        guard let link = PairingLink(url: text) else {
            error = "That isn't an mrdpd pairing link. Run `mrdpd-host pair` on the Mac and copy it again."
            return
        }
        do {
            try hosts.add(link)
            manual = ""
            error = nil
            onDone?()
        } catch {
            self.error = "Could not save the key in the Keychain (\(error))."
        }
    }

    static var canScan: Bool {
        #if canImport(VisionKit)
            return DataScannerViewController.isSupported && DataScannerViewController.isAvailable
        #else
            return false
        #endif
    }
}

#if canImport(VisionKit)
    struct QRScannerView: UIViewControllerRepresentable {
        let onCode: (String) -> Void

        func makeUIViewController(context: Context) -> DataScannerViewController {
            let vc = DataScannerViewController(
                recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced, isHighlightingEnabled: true)
            vc.delegate = context.coordinator
            try? vc.startScanning()
            return vc
        }

        func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}

        func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

        final class Coordinator: NSObject, DataScannerViewControllerDelegate {
            let onCode: (String) -> Void
            var done = false

            init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

            func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
                for item in items {
                    if case .barcode(let code) = item, let value = code.payloadStringValue, value.hasPrefix("mrdpd://"), !done {
                        done = true
                        onCode(value)
                    }
                }
            }
        }
    }
#else
    struct QRScannerView: View {
        let onCode: (String) -> Void
        var body: some View { Text("Scanning is not available on this device.") }
    }
#endif
