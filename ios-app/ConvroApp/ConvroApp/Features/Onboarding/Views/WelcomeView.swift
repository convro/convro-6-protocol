import SwiftUI

struct WelcomeView: View {
    var onContinue: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Illustration - pushed to top
                AsyncImage(url: URL(string: "https://convro.eu/assets/GRUM.png")) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(.horizontal, 40)
                    case .failure:
                        Color.clear.frame(height: 280)
                    case .empty:
                        ProgressView()
                            .tint(.white)
                            .frame(height: 280)
                    @unknown default:
                        Color.clear.frame(height: 280)
                    }
                }
                .offset(y: -20)

                // Text + Button - pulled up to overlap invisible space
                VStack(spacing: 16) {
                    Text("Welcome to Convro")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    Text("Private messaging built on anonymity.\nNo phone number. No identity exposure. Ever.")
                        .font(.body)
                        .foregroundColor(Color.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)

                    Button {
                        onContinue()
                    } label: {
                        Text("Get Started")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color("ConvroBlue"))
                            .foregroundColor(.white)
                            .cornerRadius(16)
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 28)
                .offset(y: -60)

                Spacer()
            }
            .padding(.top, 40)
        }
        .navigationBarHidden(true)
    }
}
