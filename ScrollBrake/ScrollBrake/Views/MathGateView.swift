//
//  MathGateView.swift
//  ScrollBrake
//
//  Math challenge screen that users must solve to unlock shielded apps.
//  Generates simple arithmetic problems that are easy enough to solve quickly
//  but require enough attention to break the doom-scrolling autopilot.
//

import SwiftUI

struct MathGateView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var shieldManager: ShieldManager
    @EnvironmentObject var monitoringManager: MonitoringManager

    // Math problem state
    @State private var num1: Int = 0
    @State private var num2: Int = 0
    @State private var operation: MathOperation = .addition
    @State private var userAnswer: String = ""
    @State private var showError: Bool = false
    @State private var showSuccess: Bool = false

    // Prevent accidental dismissal
    @State private var attemptCount: Int = 0

    private let persistence = PersistenceManager.shared

    var body: some View {
        ZStack {
            // Background - blocks interaction with anything behind
            Color.black.opacity(0.95)
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // Header
                headerSection

                // Math Problem Display
                problemSection

                // Answer Input
                answerSection

                // Action Buttons
                actionButtons

                Spacer()

                // Attempts counter
                if attemptCount > 0 {
                    Text("Attempts: \(attemptCount)")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .padding(32)

            // Success overlay
            if showSuccess {
                successOverlay
            }
        }
        .onAppear {
            generateNewProblem()
        }
    }

    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 60))
                .foregroundColor(.blue)

            Text("Time for a Break!")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.white)

            Text("You've been scrolling for \(persistence.sessionLimitMinutes) minutes. Solve this quick problem to continue.")
                .font(.body)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Problem Section
    private var problemSection: some View {
        VStack(spacing: 16) {
            Text("What is")
                .font(.headline)
                .foregroundColor(.gray)

            Text("\(num1) \(operation.symbol) \(num2) = ?")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .padding(.vertical, 24)
    }

    // MARK: - Answer Section
    private var answerSection: some View {
        VStack(spacing: 8) {
            TextField("Your answer", text: $userAnswer)
                .keyboardType(.numberPad)
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .padding()
                .background(Color.white.opacity(0.1))
                .cornerRadius(12)
                .foregroundColor(.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(showError ? Color.red : Color.clear, lineWidth: 2)
                )
                .onChange(of: userAnswer) { _ in
                    showError = false
                }

            if showError {
                Text("Incorrect! Try again.")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }

    // MARK: - Action Buttons
    private var actionButtons: some View {
        VStack(spacing: 16) {
            // Submit Button
            Button(action: checkAnswer) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Submit")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(userAnswer.isEmpty ? Color.gray : Color.green)
                .cornerRadius(12)
            }
            .disabled(userAnswer.isEmpty)

            // New Problem Button
            Button(action: generateNewProblem) {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Different Problem")
                }
                .font(.subheadline)
                .foregroundColor(.blue)
            }
        }
    }

    // MARK: - Success Overlay
    private var successOverlay: some View {
        ZStack {
            Color.green.opacity(0.9)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.white)

                Text("Correct!")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Text("Apps unlocked for \(persistence.rewardWindowMinutes) minutes")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.9))
            }
        }
        .transition(.opacity)
    }

    // MARK: - Logic
    private func generateNewProblem() {
        // Generate numbers based on difficulty
        // Keep it simple: single or double digit numbers
        operation = MathOperation.allCases.randomElement() ?? .addition

        switch operation {
        case .addition:
            num1 = Int.random(in: 10...50)
            num2 = Int.random(in: 10...50)
        case .subtraction:
            // Ensure positive result
            num1 = Int.random(in: 20...80)
            num2 = Int.random(in: 10...min(num1, 40))
        case .multiplication:
            num1 = Int.random(in: 2...12)
            num2 = Int.random(in: 2...12)
        case .division:
            // Ensure clean division
            num2 = Int.random(in: 2...10)
            let quotient = Int.random(in: 2...10)
            num1 = num2 * quotient
        }

        userAnswer = ""
        showError = false
    }

    private func checkAnswer() {
        guard let answer = Int(userAnswer) else {
            showError = true
            return
        }

        attemptCount += 1

        if answer == correctAnswer {
            // Success!
            withAnimation {
                showSuccess = true
            }

            // Unlock apps after short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                unlockApps()
            }
        } else {
            // Wrong answer
            withAnimation {
                showError = true
            }
            // Clear for retry
            userAnswer = ""
        }
    }

    private var correctAnswer: Int {
        switch operation {
        case .addition:
            return num1 + num2
        case .subtraction:
            return num1 - num2
        case .multiplication:
            return num1 * num2
        case .division:
            return num1 / num2
        }
    }

    private func unlockApps() {
        // Record that challenge was solved
        persistence.recordChallengeSolved()

        // Remove the shield
        shieldManager.removeShield()

        // Start the reward window timer
        monitoringManager.startRewardWindow()

        // Dismiss the math gate
        withAnimation {
            isPresented = false
        }
    }
}

// MARK: - Math Operation Enum
enum MathOperation: CaseIterable {
    case addition
    case subtraction
    case multiplication
    case division

    var symbol: String {
        switch self {
        case .addition: return "+"
        case .subtraction: return "-"
        case .multiplication: return "×"
        case .division: return "÷"
        }
    }
}

#Preview {
    MathGateView(isPresented: .constant(true))
        .environmentObject(ShieldManager.shared)
        .environmentObject(MonitoringManager.shared)
}
