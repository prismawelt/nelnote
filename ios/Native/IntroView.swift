import SwiftUI

// MARK: - 캐릭터와 로고를 화면 중앙에 배치한 시작 애니메이션

struct IntroView: View {
    let onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var badgeIn = false
    @State private var peek = false
    @State private var drawn = false
    @State private var dot = false
    @State private var hop = false
    @State private var finished = false

    private let size: CGFloat = 156

    private var characterOffset: CGFloat {
        (peek ? 0 : size * 0.93) - (hop ? size * 0.04 : 0)
    }

    var body: some View {
        ZStack {
            Theme.paper
            VStack(spacing: 28) {
                CharacterBadge(size: size, imageOffsetY: reduceMotion ? 0 : characterOffset)
                    .shadow(color: Color.blue.opacity(0.25), radius: 16, x: 0, y: 10)
                    .scaleEffect(reduceMotion || badgeIn ? 1 : 0.72)
                    .opacity(reduceMotion || badgeIn ? 1 : 0)
                Wordmark(height: 32, drawn: drawn, dotShown: dot, animated: !reduceMotion)
            }
            .offset(y: -30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .accessibilityLabel("NEL NOTE")
        .accessibilityHint("탭하여 시작 화면 건너뛰기")
        .task { await play() }
    }

    @MainActor
    private func play() async {
        do {
            if reduceMotion {
                badgeIn = true
                peek = true
                drawn = true
                dot = true
                try await Task.sleep(nanoseconds: 350_000_000)
            } else {
                withAnimation(.spring(response: 0.48, dampingFraction: 0.82)) { badgeIn = true }
                try await Task.sleep(nanoseconds: 160_000_000)
                withAnimation(.spring(response: 0.62, dampingFraction: 0.86)) { peek = true }
                drawn = true
                try await Task.sleep(nanoseconds: 1_080_000_000)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { dot = true }
                withAnimation(.easeInOut(duration: 0.18)) { hop = true }
                try await Task.sleep(nanoseconds: 180_000_000)
                withAnimation(.easeInOut(duration: 0.22)) { hop = false }
                try await Task.sleep(nanoseconds: 440_000_000)
            }
            finish()
        } catch {
            // Leaving or skipping the intro cancels every pending animation.
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onFinish()
    }
}
