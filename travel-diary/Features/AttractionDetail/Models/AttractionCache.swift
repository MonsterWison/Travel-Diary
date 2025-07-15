import Foundation

struct AttractionCache: Identifiable, Codable {
    let id: UUID
    let names: [String: String] // 語言代碼: 名稱
    let addresses: [String: String]? // 語言代碼: 地址
    let latitude: Double
    let longitude: Double
    let descriptions: [String: String]? // 語言代碼: 介紹
    let source: String? // 來源（如 Wikipedia 條目）
    
    init(id: UUID = UUID(), names: [String: String], addresses: [String: String]?, latitude: Double, longitude: Double, descriptions: [String: String]?, source: String?) {
        self.id = id
        self.names = names
        self.addresses = addresses
        self.latitude = latitude
        self.longitude = longitude
        self.descriptions = descriptions
        self.source = source
    }
} 