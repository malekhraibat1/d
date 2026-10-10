import Foundation
import ARKit

enum ARError: LocalizedError {
    case trackingNotAvailable
    case insufficientFeatures
    case worldMapTooLarge
    case relocalizationFailed
    case deviceNotSupported

    var errorDescription: String? {
        switch self {
        case .trackingNotAvailable:
            return "تتبع AR غير متاح. تحقق من الإضاءة والكاميرا."
        case .insufficientFeatures:
            return "تفاصيل غير كافية. امسح السطح ببطء أكثر."
        case .worldMapTooLarge:
            return "الخريطة كبيرة جدًا (> 100 MB). جرّب منطقة أصغر."
        case .relocalizationFailed:
            return "لم نتمكن من إيجاد موقعك السابق. ابدأ من جديد."
        case .deviceNotSupported:
            return "جهازك لا يدعم هذه الميزة."
        }
    }
}

struct ARErrorHandler {
    static func handle(_ error: Error) -> String {
        if let arError = error as? ARError {
            return arError.errorDescription ?? "خطأ غير معروف"
        }
        return error.localizedDescription
    }
}
