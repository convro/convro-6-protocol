import SwiftUI

struct ProfileView: View {
    var body: some View {
        Form {
            Section("Profile Information") {
                Text("Display Name")
                Text("Convro Number")
            }
        }
        .navigationTitle("Profile")
    }
}
