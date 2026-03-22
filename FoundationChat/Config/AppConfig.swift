import Foundation

struct AppConfig: Sendable {
  private enum Defaults {
    static let convexURL = "https://industrious-bullfrog-820.convex.cloud"
    static let airtelSMSEndpoint = "https://iqsms.airtel.in/api/v1/send-prepaid-sms"
    static let airtelCustomerID = "8dfa792b-7695-4054-ad5b-0ac872a05453"
    static let airtelDLTTemplateID = "1007495382194071124"
    static let airtelEntityID = "1001711943218436692"
    static let airtelSourceAddress = "MNJWLL"
    static let airtelMessageType = "SERVICE_IMPLICIT"
    static let airtelOTPMessageTemplate =
      "{{OTP}} is the OTP to signup on AIVIDA. Valid for 10 minutes. Do not share this with anyone."
  }

  let convexURL: String
  let airtelSMSEndpoint: String
  let airtelCustomerID: String
  let airtelDLTTemplateID: String
  let airtelEntityID: String
  let airtelSourceAddress: String
  let airtelMessageType: String
  let airtelOTPMessageTemplate: String

  static let current = load()

  static func load(bundle: Bundle = .main) -> AppConfig {
    func value(for key: String, fallback: String) -> String {
      guard let rawValue = bundle.object(forInfoDictionaryKey: key) as? String,
        !rawValue.isEmpty
      else {
        return fallback
      }
      return rawValue
    }

    return AppConfig(
      convexURL: value(for: "CONVEX_URL", fallback: Defaults.convexURL),
      airtelSMSEndpoint: value(for: "AIRTEL_SMS_ENDPOINT", fallback: Defaults.airtelSMSEndpoint),
      airtelCustomerID: value(for: "AIRTEL_CUSTOMER_ID", fallback: Defaults.airtelCustomerID),
      airtelDLTTemplateID: value(
        for: "AIRTEL_DLT_TEMPLATE_ID",
        fallback: Defaults.airtelDLTTemplateID
      ),
      airtelEntityID: value(for: "AIRTEL_ENTITY_ID", fallback: Defaults.airtelEntityID),
      airtelSourceAddress: value(
        for: "AIRTEL_SOURCE_ADDRESS",
        fallback: Defaults.airtelSourceAddress
      ),
      airtelMessageType: value(for: "AIRTEL_MESSAGE_TYPE", fallback: Defaults.airtelMessageType),
      airtelOTPMessageTemplate: value(
        for: "AIRTEL_OTP_MESSAGE_TEMPLATE",
        fallback: Defaults.airtelOTPMessageTemplate
      )
    )
  }
}
