import Foundation

enum LicenseConfig {
    static var checkoutURL: URL {
        if let raw = ProcessInfo.processInfo.environment["ZONEBOX_CHECKOUT_URL"],
           let url = URL(string: raw)
        {
            return url
        }
        return URL(string: "https://zonebox-site.vercel.app/buy")!
    }

    static var licenseAPIURL: URL {
        if let raw = ProcessInfo.processInfo.environment["ZONEBOX_LICENSE_API"],
           let url = URL(string: raw)
        {
            return url
        }
        return URL(string: "https://zonebox-site.vercel.app/api/license")!
    }
}
