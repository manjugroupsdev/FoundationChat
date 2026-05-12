import SwiftUI

private struct OnboardingPage {
    let titlePrefix: String
    let titleHighlight: String
    let subtitle: String
    let images: [String]
}

private let pages: [OnboardingPage] = [
    OnboardingPage(
        titlePrefix: "Welcome to ",
        titleHighlight: "Manju Groups",
        subtitle: "Manage Projects, engage customers, and streamline operations - all in one place.",
        images: ["onboard_today_meeting", "onboard_today_activity"]
    ),
    OnboardingPage(
        titlePrefix: "Track ",
        titleHighlight: "Performance Easily",
        subtitle: "Monitor sales, project progress and team activity in real time.",
        images: ["onboard_sales_line", "onboard_sales_bar"]
    ),
    OnboardingPage(
        titlePrefix: "Manage Your ",
        titleHighlight: "Workflow",
        subtitle: "Track tasks, manage site visits, and close deals efficiently.",
        images: ["onboard_milestones", "onboard_todays_tasks"]
    ),
]

struct OnboardingView: View {
    let onComplete: () -> Void

    @State private var currentPage = 0

    private let skyTop    = Color(red: 0.18, green: 0.55, blue: 0.95)
    private let skyBottom = Color(red: 0.93, green: 0.97, blue: 1.0)
    private let green1    = Color(red: 0.10, green: 0.79, blue: 0.04)
    private let green2    = Color(red: 0.24, green: 0.62, blue: 0.01)

    var body: some View {
        GeometryReader { geo in
            let cardHeight = geo.size.height * 0.40
            let illustrationHeight = geo.size.height - cardHeight

            ZStack(alignment: .top) {
                // Sky gradient fills full screen
                LinearGradient(
                    colors: [skyTop, skyBottom],
                    startPoint: .top,
                    endPoint: .init(x: 0.5, y: 0.68)
                )
                .ignoresSafeArea()

                // Illustrations live in the top zone
                VStack(spacing: 0) {
                    illustrationLayer(page: pages[currentPage], geo: geo)
                        .frame(width: geo.size.width, height: illustrationHeight)
                        .clipped()

                    Spacer()
                }

                // Bottom frosted card pinned to bottom
                VStack {
                    Spacer()
                    bottomCard(geo: geo, cardHeight: cardHeight)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: currentPage)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    @ViewBuilder
    private func illustrationLayer(page: OnboardingPage, geo: GeometryProxy) -> some View {
        let w = geo.size.width
        let h = geo.size.height * 0.60

        ZStack(alignment: .top) {
            if page.images.count >= 1 {
                Image(page.images[0])
                    .resizable()
                    .scaledToFit()
                    .frame(width: w * 0.78)
                    .offset(y: h * 0.04)
                    .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
            }
            if page.images.count >= 2 {
                Image(page.images[1])
                    .resizable()
                    .scaledToFit()
                    .frame(width: w * 0.78)
                    .offset(y: h * 0.38)
                    .shadow(color: .black.opacity(0.15), radius: 14, x: 0, y: 6)
            }
        }
        .frame(width: w, height: h, alignment: .top)
    }

    private func bottomCard(geo: GeometryProxy, cardHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            titleText(page: pages[currentPage])
                .font(.system(size: 24, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .animation(.none, value: currentPage)

            Text(pages[currentPage].subtitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(red: 0.28, green: 0.33, blue: 0.40))
                .fixedSize(horizontal: false, vertical: true)
                .animation(.none, value: currentPage)

            // Dot indicators
            HStack(spacing: 8) {
                ForEach(0..<pages.count, id: \.self) { i in
                    Capsule()
                        .fill(
                            i == currentPage
                            ? AnyShapeStyle(LinearGradient(colors: [green1, green2], startPoint: .leading, endPoint: .trailing))
                            : AnyShapeStyle(Color(red: 0.83, green: 0.95, blue: 1.0))
                        )
                        .frame(width: i == currentPage ? 28 : 8, height: 5)
                        .animation(.spring(response: 0.3), value: currentPage)
                }
                Spacer()
            }

            // Buttons
            VStack(spacing: 12) {
                Button(action: handleNext) {
                    Text(currentPage == pages.count - 1 ? "Get Started" : "Next")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(colors: [green1, green2], startPoint: .leading, endPoint: .trailing),
                            in: Capsule()
                        )
                }

                if currentPage < pages.count - 1 {
                    Button(action: handleSkip) {
                        Text("Skip")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color(red: 0.13, green: 0.77, blue: 0.37))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color(red: 0.13, green: 0.77, blue: 0.37), lineWidth: 1.5)
                            )
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, geo.safeAreaInsets.bottom + 20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(.white.opacity(0.35), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func titleText(page: OnboardingPage) -> some View {
        Text("\(Text(page.titlePrefix).foregroundStyle(Color(red: 0.06, green: 0.09, blue: 0.16)))\(Text(page.titleHighlight).foregroundStyle(Color(red: 0.04, green: 0.38, blue: 0.79)))")
    }

    private func handleNext() {
        if currentPage < pages.count - 1 {
            withAnimation(.easeInOut(duration: 0.3)) { currentPage += 1 }
        } else {
            onComplete()
        }
    }

    private func handleSkip() {
        onComplete()
    }
}

#Preview {
    OnboardingView(onComplete: {})
}
