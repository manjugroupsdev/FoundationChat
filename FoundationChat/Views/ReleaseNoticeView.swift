import SwiftUI

struct ReleaseNoticeView: View {
    let campaign: ReleaseNoticeCampaign
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.58)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Image("ManjuGroupsLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 150, height: 86)
                        .frame(width: 162, height: 94)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .accessibilityLabel("Manju Groups logo")

                    Image("ReleaseNoticeApology")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 172, height: 172)
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
                        .font(.system(size: 23, weight: .semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 14)

                    Text(campaign.tamilTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(red: 0.043, green: 0.38, blue: 0.792))
                        .multilineTextAlignment(.center)
                        .padding(.top, 7)

                    Text(campaign.transliteratedTamilTitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 3)

                    Text(campaign.message)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .padding(.top, 12)

                    VStack(alignment: .leading, spacing: 10) {
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
                    .padding(.top, 16)

                    Text(campaign.attribution)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(.top, 13)

                    Button(action: onContinue) {
                        Text("Continue")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Color(red: 0.106, green: 0.792, blue: 0.043))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 18)
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 22)
            }
            .frame(maxWidth: 420, maxHeight: 650)
            .background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(uiColor: .separator), lineWidth: 0.5)
            }
            .padding(.horizontal, 20)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
        .accessibilityAddTraits(.isModal)
    }
}
