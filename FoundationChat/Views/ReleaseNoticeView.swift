import SwiftUI

struct ReleaseNoticeView: View {
    let campaign: ReleaseNoticeCampaign
    let onContinue: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.58)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    ScrollView {
                        noticeContent
                            .padding(.horizontal, 24)
                            .padding(.top, 14)
                            .padding(.bottom, 16)
                    }
                    .scrollIndicators(.hidden)

                    Divider()

                    Button(action: onContinue) {
                        Text("Continue")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Color(red: 0.106, green: 0.792, blue: 0.043))
                            .clipShape(.rect(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                }
                .frame(maxWidth: 420)
                .frame(height: min(720, max(360, proxy.size.height - 32)))
                .background(Color(uiColor: .systemBackground))
                .clipShape(.rect(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color(uiColor: .separator), lineWidth: 0.5)
                }
                .padding(.horizontal, 20)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
        .accessibilityAddTraits(.isModal)
    }

    private var noticeContent: some View {
        VStack(spacing: 0) {
            Image("ManjuGroupsLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 132, height: 72)
                .accessibilityLabel("Manju Groups logo")

            Image("ReleaseNoticeApology")
                .resizable()
                .scaledToFit()
                .frame(width: 132, height: 132)
                .padding(.top, 2)
                .accessibilityLabel("MConnect service update")

            Text(campaign.label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(red: 0.043, green: 0.38, blue: 0.792))
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Color(red: 0.86, green: 0.92, blue: 0.99))
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color(red: 0.043, green: 0.38, blue: 0.792), lineWidth: 1)
                }

            Text(campaign.title)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .padding(.top, 12)

            Text(campaign.tamilTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(red: 0.043, green: 0.38, blue: 0.792))
                .multilineTextAlignment(.center)
                .padding(.top, 6)

            Text(campaign.transliteratedTamilTitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 2)

            Text(campaign.message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.top, 10)

            VStack(alignment: .leading, spacing: 9) {
                ForEach(campaign.highlights, id: \.self) { highlight in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color(red: 0.106, green: 0.792, blue: 0.043))
                        Text(highlight)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 14)

            Text(campaign.attribution)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.top, 12)
        }
    }
}
