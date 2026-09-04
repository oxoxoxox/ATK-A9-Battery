import Foundation

struct DeviceIdentity: Equatable {
    let displayName: String
    let appName: String
    let accessoryIdentifier: String
    let deviceType: String
    let receiverVendorID: Int
    let accessoryProductID: Int
}
