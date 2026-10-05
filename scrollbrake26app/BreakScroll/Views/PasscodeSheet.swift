//
//  PasscodeSheet.swift
//  BreakScroll
//

import BreakScrollCore
import SwiftUI

/// Create or enter the parent passcode that protects rules on a child's iPhone.
struct PasscodeSheet: View {
    @Environment(\.dismiss) private var dismiss
    /// False during child setup: the parent must create the passcode.
    var allowsCancel = true
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
                        .focused($focused)
                } footer: {
                    if let message {
                        Text(message).foregroundStyle(.red)
                    } else if isCreating {
                        Text(allowsCancel
                             ? "Only a parent should know this. It's needed to change BreakScroll's rules on this iPhone."
                             : "Parent: create a passcode now. It's needed to change BreakScroll's rules on this iPhone, so only you should know it.")
                    }
                }
            }
            .navigationTitle(isCreating ? "Create Parent Passcode" : "Parent Passcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if allowsCancel {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isCreating && first.isEmpty ? "Next" : "Done", action: submit)
                        .disabled(entry.count < 4)
                }
            }
            .onAppear { focused = true }
            .interactiveDismissDisabled(!allowsCancel)
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
            var lockout = ParentPasscode.lockout
            let now = Date()
            if lockout.isLocked(at: now), let until = lockout.lockedUntil {
                message = "Too many tries. Try again \(until.formatted(.relative(presentation: .named)))."
                entry = ""
                return
            }
            if ParentPasscode.verify(entry) {
                lockout.recordSuccess()
                ParentPasscode.lockout = lockout
                onSuccess()
            } else {
                lockout.recordFailure(at: now)
                ParentPasscode.lockout = lockout
                message = lockout.isLocked(at: now) ? "Too many tries. Please wait before trying again." : "That passcode isn't right."
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
