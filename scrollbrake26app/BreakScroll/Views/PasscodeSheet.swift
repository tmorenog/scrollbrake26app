//
//  PasscodeSheet.swift
//  BreakScroll
//

import SwiftUI

/// Create or enter the parent passcode that protects rules on a child's iPhone.
struct PasscodeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSuccess: () -> Void

    @State private var isCreating = !ParentPasscode.isSet
    @State private var first = ""
    @State private var entry = ""
    @State private var message: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(prompt, text: $entry)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .focused($focused)
                        .onSubmit(submit)
                } footer: {
                    if let message {
                        Text(message).foregroundStyle(.red)
                    } else if isCreating {
                        Text("Only a parent should know this. It's needed to change BreakScroll's rules on this iPhone.")
                    }
                }
            }
            .navigationTitle(isCreating ? "Create Parent Passcode" : "Parent Passcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isCreating && first.isEmpty ? "Next" : "Done", action: submit)
                        .disabled(entry.count < 4)
                }
            }
            .onAppear { focused = true }
        }
    }

    private var prompt: String {
        if !isCreating { return "Passcode" }
        return first.isEmpty ? "New passcode (4–8 digits)" : "Enter it again"
    }

    private func submit() {
        guard (4...8).contains(entry.count), entry.allSatisfy(\.isNumber) else {
            message = "Use 4 to 8 digits."
            return
        }
        if !isCreating {
            if ParentPasscode.verify(entry) {
                onSuccess()
            } else {
                message = "That passcode isn't right."
                entry = ""
            }
            return
        }
        if first.isEmpty {
            first = entry
            entry = ""
            message = nil
        } else if first == entry {
            if ParentPasscode.set(entry) {
                onSuccess()
            } else {
                message = "The passcode couldn't be saved."
            }
        } else {
            message = "Those didn't match. Start again."
            first = ""
            entry = ""
        }
    }
}
