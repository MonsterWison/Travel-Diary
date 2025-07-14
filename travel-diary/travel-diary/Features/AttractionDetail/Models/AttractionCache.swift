import Foundation

struct AttractionCache: Identifiable, Codable {
    let id = UUID()
    let names: [String: String] // 語言代碼: 名稱
    let addresses: [String: String]? // 語言代碼: 地址
    let latitude: Double
    let longitude: Double
    let descriptions: [String: String]? // 語言代碼: 介紹
    let source: String? // 來源（如 Wikipedia 條目）
} 