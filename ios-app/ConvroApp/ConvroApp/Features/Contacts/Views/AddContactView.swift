import SwiftUI

struct AddContactView: View {
    @StateObject private var viewModel = AddContactViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section("Contact Information") {
                    TextField("Convro Number", text: $viewModel.convroNumber)
                    TextField("Display Name", text: $viewModel.displayName)
                }

                Button("Add Contact") {
                    Task {
                        try? await viewModel.addContact()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Add Contact")
        }
    }
}
