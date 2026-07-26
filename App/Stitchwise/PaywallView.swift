import SwiftUI
import StitchCore

/// One price, paid once. The copy states plainly what happens if you never pay, because
/// the competitor complaint this app is answering is content vanishing at the end of a trial.
struct PaywallView: View {
    @Environment(PurchaseManager.self) private var purchases
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Image(systemName: "infinity")
                            .font(.system(size: 44, weight: .light))
                            .foregroundStyle(.tint)
                        Text("Stitchwise, unlocked")
                            .font(.title2.weight(.semibold))
                        Text("Pay once. Yours forever. No subscription.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 24)

                    VStack(alignment: .leading, spacing: 16) {
                        FeatureRow(icon: "square.stack.3d.up", title: "Unlimited projects",
                                   detail: "Keep every jumper, sock and blanket on the go at once.")
                        FeatureRow(icon: "highlighter", title: "Pattern annotation",
                                   detail: "Row highlighter, chart bands and notes on your own PDFs.")
                        FeatureRow(icon: "wifi.slash", title: "Fully offline",
                                   detail: "No account, no cloud, no signal needed. Ever.")
                    }
                    .padding(.horizontal)

                    VStack(spacing: 12) {
                        Button {
                            Task { await purchases.purchase(); dismiss() }
                        } label: {
                            HStack {
                                if purchases.purchaseInFlight {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("Unlock for \(purchases.displayPrice)")
                                        .fontWeight(.semibold)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(purchases.purchaseInFlight)
                        .accessibilityIdentifier("purchaseButton")

                        Button("Restore purchase") {
                            Task { await purchases.restore() }
                        }
                        .font(.footnote)
                        .accessibilityIdentifier("restoreButton")
                    }
                    .padding(.horizontal)

                    Text("If you never buy, nothing you have already made is locked or deleted. Your projects, counters and patterns stay open and editable. The free tier limits how many new projects you can start, not what you can reach.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .padding(.bottom, 24)
                        .accessibilityIdentifier("noHostageCopy")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                }
            }
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 28)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
