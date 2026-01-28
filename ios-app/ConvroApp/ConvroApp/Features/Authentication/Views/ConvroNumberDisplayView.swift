import SwiftUI

// MARK: - Convro Number Display View
struct ConvroNumberDisplayView: View {
    let convroNumber: String
    let onContinue: () -> Void
    @State private var copied = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                // Success icon
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundColor(Color("ConvroGreen"))

                VStack(spacing: 8) {
                    Text("You're in")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    Text("Your Convro Number")
                        .font(.subheadline)
                        .foregroundColor(Color.white.opacity(0.4))
                }

                // Number display
                Text(convroNumber)
                    .font(.system(.title, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(Color("ConvroBlue"))
                    .padding(.vertical, 16)
                    .padding(.horizontal, 24)
                    .background(Color(red: 0.1, green: 0.1, blue: 0.1))
                    .cornerRadius(14)

                Text("Save this number. Your contacts\nwill use it to reach you.")
                    .font(.subheadline)
                    .foregroundColor(Color.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)

                // Copy button
                Button {
                    UIPasteboard.general.string = convroNumber
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copied = false
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        Text(copied ? "Copied" : "Copy Number")
                    }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(Color("ConvroBlue"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color("ConvroBlue").opacity(0.15))
                    .cornerRadius(14)
                }
                .padding(.horizontal, 28)

                // Continue button
                Button {
                    onContinue()
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color("ConvroBlue"))
                        .foregroundColor(.white)
                        .cornerRadius(16)
                }
                .padding(.horizontal, 28)

                Spacer()
                Spacer()
            }
        }
    }
}
