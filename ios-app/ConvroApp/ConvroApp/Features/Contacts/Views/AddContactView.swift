import SwiftUI

struct AddContactView: View {
    @StateObject private var viewModel = AddContactViewModel()
    let onSuccess: () -> Void
    let onCancel: () -> Void

    var body: some View {
        Form {
            Section("Contact Information") {
                TextField("Convro Number", text: $viewModel.convroNumber)
                    .keyboardType(.numberPad)
                TextField("Display Name (optional)", text: $viewModel.displayName)
            }

            if let validationError = viewModel.validateConvroNumber() {
                Section {
                    Text(validationError)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }

            Section {
                Button("Add Contact") {
                    Task {
                        await viewModel.addContact()
                        if viewModel.addSuccess {
                            onSuccess()
                        }
                    }
                }
                .disabled(viewModel.isLoading || viewModel.convroNumber.isEmpty)
            }
        }
        .navigationTitle("Add Contact")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    onCancel()
                }
            }
        }
        .loadingOverlay(isLoading: viewModel.isLoading)
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.clearError()
            }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
    }
}
