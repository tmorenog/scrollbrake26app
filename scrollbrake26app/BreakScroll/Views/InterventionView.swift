//
//  InterventionView.swift
//  BreakScroll
//
//  Full-screen while a break is in progress. Every step is driven by the
//  engine's phase, so it resumes correctly if the app was killed mid-pause.
//

import SwiftUI
import UIKit
import BreakScrollCore

struct InterventionView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            if let active = model.activeIntervention {
                content(rule: active.rule, session: active.session)
                    .padding(24)
                    .frame(maxWidth: 520)
            }
        }
    }

    @ViewBuilder
    private func content(rule: InterventionRule, session: InterventionSession) -> some View {
        switch session.phase {
        case .shielded:
            DecisionStep(rule: rule) { model.send($0, to: rule) }
        case .pausing(let until, _):
            PauseStep(until: until, total: pauseLength(rule, session)) { model.send(.chooseDone, to: rule) }
        case .challenge(let challenge, let failedAttempts):
            ChallengeStep(challenge: challenge, failedAttempts: failedAttempts) { model.send($0, to: rule) }
        case .rearmFailed:
            Step(symbol: "exclamationmark.triangle", title: "Couldn't restart the timer",
                 message: "Your apps stay paused until this works.") {
                Button("Try Again") { model.send(.retryArm, to: rule) }
                    .buttonStyle(.borderedProminent)
                Button("I'm Done") { model.send(.chooseDone, to: rule) }
            }
        default:
            ProgressView("Starting your next \(ShieldCopy.describe(rule.usageInterval))…")
        }
    }

    private func pauseLength(_ rule: InterventionRule, _ session: InterventionSession) -> TimeInterval {
        if case .pauseAndChallenge(let pause, _) = rule.step(forContinuation: session.continuationsToday + 1) {
            return pause
        }
        return rule.pauseDuration
    }
}

/// Shared layout: icon, title, message, then actions.
private struct Step<Actions: View>: View {
    let symbol: String
    let title: String
    let message: String
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(title)
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            VStack(spacing: 12) { actions }
                .controlSize(.large)
        }
    }
}

private struct DecisionStep: View {
    let rule: InterventionRule
    let send: (InterventionInput) -> Void

    var body: some View {
        Step(
            symbol: "hourglass",
            title: "Time for a quick break",
            message: "You've been using these apps for \(ShieldCopy.describe(rule.usageInterval)). Take a moment before deciding whether you'd like to continue."
        ) {
            Button { send(.chooseDone) } label: {
                Text("I'm Done").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            Button { send(.chooseContinue) } label: {
                Text("Continue").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }
}

private struct PauseStep: View {
    let until: Date
    let total: TimeInterval
    let onDone: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, until.timeIntervalSince(context.date))
            Step(symbol: "wind", title: "Take a breath", message: "Your challenge starts in \(Int(remaining.rounded(.up))) seconds.") {
                ZStack {
                    Circle().stroke(Color(.tertiarySystemFill), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: CGFloat(total > 0 ? 1 - remaining / total : 1))
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(reduceMotion ? nil : .linear(duration: 1), value: remaining)
                    Text("\(Int(remaining.rounded(.up)))")
                        .font(.system(.largeTitle, design: .rounded).monospacedDigit())
                }
                .frame(width: 120, height: 120)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(Int(remaining.rounded(.up))) seconds left")
                Button("I'm Done", action: onDone)
            }
        }
    }
}

private struct ChallengeStep: View {
    let challenge: MathChallenge
    let failedAttempts: Int
    let send: (InterventionInput) -> Void

    @State private var answer = ""
    @State private var showWrong = false
    @FocusState private var focused: Bool

    var body: some View {
        Step(symbol: "brain.head.profile", title: "One quick question", message: "Solve this to continue.") {
            Text(challenge.prompt)
                .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                .accessibilityLabel(Self.spoken(challenge.prompt))
            TextField("Answer", text: $answer)
                .keyboardType(.numberPad)
                .font(.system(.title, design: .rounded).monospacedDigit())
                .multilineTextAlignment(.center)
                .padding(12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .focused($focused)
                .accessibilityLabel("Answer")
            if showWrong {
                Text(wrongAnswerMessage)
                    .foregroundStyle(.secondary)
            }
            Button(action: submit) {
                Text("Submit").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(answer.isEmpty)
            HStack {
                Button("Different Problem") {
                    answer = ""
                    showWrong = false
                    send(.requestDifferentProblem)
                }
                Spacer()
                Button("I'm Done") { send(.chooseDone) }
            }
            .font(.subheadline)
        }
        .onAppear { focused = true }
    }

    private var wrongAnswerMessage: String {
        let replaced = failedAttempts > 0 && failedAttempts % InterventionEngine.attemptsBeforeNewProblem == 0
        return replaced ? "Here's a new one to try." : "Not quite. Try again."
    }

    private func submit() {
        let correct = challenge.isCorrect(answer)
        UINotificationFeedbackGenerator().notificationOccurred(correct ? .success : .error)
        showWrong = !correct
        send(.submitAnswer(answer))
        answer = ""
    }

    /// "62 − 27" reads as "62 minus 27" for VoiceOver.
    static func spoken(_ prompt: String) -> String {
        prompt
            .replacingOccurrences(of: "\u{2212}", with: " minus ")
            .replacingOccurrences(of: "\u{00D7}", with: " times ")
            .replacingOccurrences(of: "\u{00F7}", with: " divided by ")
            .replacingOccurrences(of: "+", with: " plus ")
    }
}
