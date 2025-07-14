import Foundation

struct CompareModel: Identifiable, Codable {
    let id = UUID()
    let names: [String: String] // 語言代碼: 名稱
    let address: String?
    let latitude: Double
    let longitude: Double
} 