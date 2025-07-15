import Foundation

/// 暫存記憶體模型 - 用於分階段景點提取的臨時資料儲存
/// 格式與AttractionCache相同，用於暫存處理中的景點資料
struct TemplateMemoryModel: Identifiable, Codable {
    var id: UUID
    let names: [String: String] // 語言代碼: 名稱
    let addresses: [String: String]? // 語言代碼: 地址
    let latitude: Double
    let longitude: Double
    let descriptions: [String: String]? // 語言代碼: 介紹
    let source: String? // 來源（如 Wikipedia 條目）
    let distanceFromUser: Double // 距離用戶的米數
    let searchRadius: String // 搜尋半徑範圍（如 "0-2km", "2-4km"）
    let processingStage: ProcessingStage // 處理階段
    let hasWikipediaData: Bool // 是否有Wikipedia資料
    
    /// 處理階段枚舉
    enum ProcessingStage: String, Codable {
        case extracted = "extracted"           // 已提取
        case wikipediaMatched = "wikipedia_matched" // 已配對Wikipedia
        case sorted = "sorted"                 // 已排序
        case validated = "validated"           // 已驗證
        case ready = "ready"                   // 準備就緒
    }
    
    /// 初始化方法
    init(names: [String: String], 
         addresses: [String: String]? = nil,
         latitude: Double,
         longitude: Double,
         descriptions: [String: String]? = nil,
         source: String? = nil,
         distanceFromUser: Double,
         searchRadius: String,
         processingStage: ProcessingStage = .extracted,
         hasWikipediaData: Bool = false) {
        self.id = UUID()
        self.names = names
        self.addresses = addresses
        self.latitude = latitude
        self.longitude = longitude
        self.descriptions = descriptions
        self.source = source
        self.distanceFromUser = distanceFromUser
        self.searchRadius = searchRadius
        self.processingStage = processingStage
        self.hasWikipediaData = hasWikipediaData
    }
    
    /// 轉換為AttractionCache
    func toAttractionCache() -> AttractionCache {
        return AttractionCache(
            names: names,
            addresses: addresses,
            latitude: latitude,
            longitude: longitude,
            descriptions: descriptions,
            source: source
        )
    }
    
    /// 從AttractionCache建立
    static func from(_ cache: AttractionCache, 
                    distanceFromUser: Double,
                    searchRadius: String) -> TemplateMemoryModel {
        return TemplateMemoryModel(
            names: cache.names,
            addresses: cache.addresses,
            latitude: cache.latitude,
            longitude: cache.longitude,
            descriptions: cache.descriptions,
            source: cache.source,
            distanceFromUser: distanceFromUser,
            searchRadius: searchRadius,
            processingStage: .ready,
            hasWikipediaData: cache.descriptions != nil
        )
    }
} 