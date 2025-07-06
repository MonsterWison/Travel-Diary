import Foundation
import CoreLocation
import UIKit
import SwiftUI
import MapKit

/// 附近景點數據模型 - 仿Pydantic格式設計
struct NearbyAttraction: Codable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let description: String
    let coordinate: AttractionsCoordinate
    let distanceFromUser: Double // 距離用戶的米數
    let category: AttractionCategory
    let imageURL: String? // 圖片URL
    let imageData: Data? // 本地圖片數據
    let address: String?
    let rating: Double? // 評分 (0-5)
    let lastUpdated: Date
    
    // 初始化方法
    init(id: UUID = UUID(), 
         name: String, 
         description: String, 
         coordinate: AttractionsCoordinate, 
         distanceFromUser: Double, 
         category: AttractionCategory, 
         imageURL: String? = nil, 
         imageData: Data? = nil, 
         address: String? = nil, 
         rating: Double? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.coordinate = coordinate
        self.distanceFromUser = distanceFromUser
        self.category = category
        self.imageURL = imageURL
        self.imageData = imageData
        self.address = address
        self.rating = rating
        self.lastUpdated = Date()
    }
    
    // Equatable協議實現
    static func == (lhs: NearbyAttraction, rhs: NearbyAttraction) -> Bool {
        return lhs.id == rhs.id
    }
}

/// 坐標數據結構 - 可編碼的坐標格式
struct AttractionsCoordinate: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    
    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
    
    init(from coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }
    
    var clLocationCoordinate: CLLocationCoordinate2D {
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// 景點分類枚舉
enum AttractionCategory: String, Codable, CaseIterable {
    case historicalSite = "historical_site"     // 歷史古蹟
    case museum = "museum"                      // 博物館
    case park = "park"                          // 公園
    case temple = "temple"                      // 廟宇
    case beach = "beach"                        // 海灘
    case mountain = "mountain"                  // 山峰
    case viewpoint = "viewpoint"               // 觀景台
    case shoppingCenter = "shopping_center"     // 購物中心
    case culturalCenter = "cultural_center"     // 文化中心
    case amusementPark = "amusement_park"      // 遊樂園
    case restaurant = "restaurant"              // 餐廳
    case other = "other"                       // 其他
    
    var displayName: String {
        switch self {
        case .historicalSite: return "歷史古蹟"
        case .museum: return "博物館"
        case .park: return "公園"
        case .temple: return "廟宇"
        case .beach: return "海灘"
        case .mountain: return "山峰"
        case .viewpoint: return "觀景台"
        case .shoppingCenter: return "購物中心"
        case .culturalCenter: return "文化中心"
        case .amusementPark: return "遊樂園"
        case .restaurant: return "餐廳"
        case .other: return "其他"
        }
    }
    
    var iconName: String {
        switch self {
        case .historicalSite: return "building.columns"     // HIG合規：歷史建築
        case .museum: return "building.2"                   // HIG合規：博物館/圖書館
        case .park: return "tree"                          // HIG合規：公園/自然景觀
        case .temple: return "building.2.crop.circle"      // HIG合規：宗教場所
        case .beach: return "beach.umbrella"               // HIG合規：海灘
        case .mountain: return "mountain.2"                // HIG合規：山峰
        case .viewpoint: return "eye"                      // HIG合規：觀景台
        case .shoppingCenter: return "bag"                 // HIG合規：購物場所
        case .culturalCenter: return "theatermasks"        // HIG合規：文化中心
        case .amusementPark: return "ferriswheel"          // HIG合規：娛樂場所
        case .restaurant: return "fork.knife"              // HIG合規：餐廳
        case .other: return "location.circle"              // HIG合規：通用位置
        }
    }
    
    var uiIconName: String {
        return iconName
    }
    
    var color: Color {
        switch self {
        case .historicalSite: return .brown
        case .museum: return .purple
        case .park: return .green
        case .temple: return .orange
        case .beach: return .blue
        case .mountain: return .gray
        case .viewpoint: return .cyan
        case .shoppingCenter: return .indigo
        case .culturalCenter: return .yellow
        case .amusementPark: return .pink
        case .restaurant: return .red
        case .other: return .mint
        }
    }
}

/// 附近景點緩存數據容器 - 仿Pydantic BaseModel設計
struct NearbyAttractionsCache: Codable {
    var attractions: [NearbyAttraction]
    let lastUserLocation: AttractionsCoordinate
    let lastUpdated: Date
    let searchRadius: Double // 搜索半徑（米）
    let maxResults: Int // 最大結果數量
    let panelState: String // 面板狀態 (hidden/compact/expanded)
    
    init(attractions: [NearbyAttraction] = [], 
         lastUserLocation: AttractionsCoordinate, 
         searchRadius: Double = 20000, // 20km
         maxResults: Int = 50,
         panelState: String = "compact") {
        self.attractions = attractions.sorted { $0.distanceFromUser < $1.distanceFromUser }
        self.lastUserLocation = lastUserLocation
        self.lastUpdated = Date()
        self.searchRadius = searchRadius
        self.maxResults = maxResults
        self.panelState = panelState
    }
    
    /// 按距離排序的景點列表
    var sortedAttractions: [NearbyAttraction] {
        return attractions.sorted { $0.distanceFromUser < $1.distanceFromUser }
    }
    
    /// 按分類分組的景點
    var attractionsByCategory: [AttractionCategory: [NearbyAttraction]] {
        return Dictionary(grouping: attractions) { $0.category }
    }
    
    /// 獲取指定距離內的景點
    func attractions(within distance: Double) -> [NearbyAttraction] {
        return attractions.filter { $0.distanceFromUser <= distance }
    }
    
    /// 檢查是否需要更新（基於位置變化）
    func needsUpdate(for currentLocation: CLLocationCoordinate2D, threshold: Double = 100.0) -> Bool {
        let lastLocation = CLLocation(latitude: lastUserLocation.latitude, longitude: lastUserLocation.longitude)
        let currentLocationObj = CLLocation(latitude: currentLocation.latitude, longitude: currentLocation.longitude)
        let distance = lastLocation.distance(from: currentLocationObj)
        
        return distance >= threshold
    }
    
    /// 檢查緩存是否過期（基於時間）
    func isExpired(maxAge: TimeInterval = 3600) -> Bool { // 預設1小時過期
        return Date().timeIntervalSince(lastUpdated) > maxAge
    }
}

/// 景點搜索配置
struct AttractionSearchConfig {
    let searchRadius: Double // 搜索半徑（米）
    let maxResults: Int // 最大結果數
    let categories: [AttractionCategory] // 搜索的景點類別
    let updateThreshold: Double // 位置更新閾值（米）
    let cacheExpiry: TimeInterval // 緩存過期時間（秒）
    
    static let `default` = AttractionSearchConfig(
        searchRadius: 20000, // 20km
        maxResults: 50,
        categories: AttractionCategory.allCases,
        updateThreshold: 100, // 100米
        cacheExpiry: 900 // 15分鐘（從1小時改為15分鐘）
    )
}

// MARK: - MVVM Model: 業務邏輯層

/// MVVM架構 - Model負責數據和業務邏輯
class NearbyAttractionsModel {
    
    // MARK: - 私有屬性
    private var allSearchResults: [NearbyAttraction] = []
    private(set) var processedAttractions: [NearbyAttraction] = []
    
    // MARK: - 搜索配置（純淨的旅遊關鍵字，不包含垃圾內容）
    private let tourismKeywords = [
        "tourist attraction", "landmark", "museum", "park", "temple",
        "beach", "viewpoint", "cultural center", "historic site",
        "famous restaurant", "shopping mall", "art gallery", "botanical garden", "national park"
    ]
    
    // MARK: - 公共方法
    
    /// 按照用戶建議的正確MVVM流程搜索景點
    /// 1. 先收集每個關鍵字的25個結果
    /// 2. 合併所有結果
    /// 3. 按距離排序
    /// 4. 去重保留最近的
    /// 5. 限制為前50個
    func searchNearbyAttractions(coordinate: CLLocationCoordinate2D, completion: @escaping ([NearbyAttraction]) -> Void) {
        
        // 清空之前的結果
        allSearchResults.removeAll()
        processedAttractions.removeAll()
        
        let group = DispatchGroup()
        var completedSearches = 0
        
        // 步驟1: 收集所有搜索關鍵字的結果
        for keyword in tourismKeywords {
            group.enter()
            
            searchSingleKeyword(keyword: keyword, coordinate: coordinate) { results in
                defer { group.leave() }
                
                completedSearches += 1
                
                // 將結果加入總集合
                self.allSearchResults.append(contentsOf: results)
            }
        }
        
        // 步驟2: 當所有搜索完成時，進行數據處理
        group.notify(queue: .main) {
            self.processCollectedData(completion: completion)
        }
    }
    
    /// 獲取處理後的景點數量
    var attractionCount: Int {
        return processedAttractions.count
    }
    
    /// 根據索引獲取景點
    func attraction(at index: Int) -> NearbyAttraction? {
        guard index < processedAttractions.count else { return nil }
        return processedAttractions[index]
    }
    
    /// 清空所有數據
    func clearAllData() {
        allSearchResults.removeAll()
        processedAttractions.removeAll()
    }
    
    // MARK: - 私有方法
    
    /// 搜索單個關鍵字，限制25個結果
    private func searchSingleKeyword(keyword: String, coordinate: CLLocationCoordinate2D, completion: @escaping ([NearbyAttraction]) -> Void) {
        
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = keyword
        request.region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 100000, // 100km搜索範圍
            longitudinalMeters: 100000
        )
        request.resultTypes = [.pointOfInterest]
        
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            if let error = error {
                completion([])
                return
            }
            
            guard let response = response else {
                completion([])
                return
            }
            
            // 限制每個關鍵字最多25個結果
            let limitedItems = Array(response.mapItems.prefix(25))
            
            let attractions = limitedItems.compactMap { item -> NearbyAttraction? in
                guard let name = item.name, !name.isEmpty else { return nil }
                
                let distance = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                    .distance(from: item.placemark.location ?? CLLocation())
                
                return NearbyAttraction(
                    id: UUID(),
                    name: name,
                    description: name, // 簡化為名稱
                    coordinate: AttractionsCoordinate(from: item.placemark.coordinate),
                    distanceFromUser: distance,
                    category: self.categorizeByKeyword(keyword: keyword),
                    address: self.formatAddress(item.placemark)
                )
            }
            
            completion(attractions)
        }
    }
    
    /// 處理收集到的數據：合併、排序、去重、限制數量
    private func processCollectedData(completion: @escaping ([NearbyAttraction]) -> Void) {
        // 步驟2a: 按距離排序（由近至遠）
        let sortedResults = allSearchResults.sorted { $0.distanceFromUser < $1.distanceFromUser }
        
        // 步驟2b: 去重（按名稱+地址去重，保留距離最近的）
        var uniqueAttractions: [String: NearbyAttraction] = [:]
        for attraction in sortedResults {
            let key = "\(attraction.name)_\(attraction.address ?? "")"
            if uniqueAttractions[key] == nil {
                uniqueAttractions[key] = attraction
            }
        }
        
        let uniqueResults = Array(uniqueAttractions.values).sorted { $0.distanceFromUser < $1.distanceFromUser }
        
        // 步驟2c: 限制為前50個最近的景點
        processedAttractions = Array(uniqueResults.prefix(50))
        
        completion(processedAttractions)
    }
    
    /// 根據搜索關鍵字進行分類
    private func categorizeByKeyword(keyword: String) -> AttractionCategory {
        switch keyword.lowercased() {
        case "tourist attraction", "landmark", "viewpoint":
            return .viewpoint
        case "museum", "art gallery", "cultural center":
            return .museum
        case "park", "botanical garden", "national park", "beach":
            return .park
        case "temple":
            return .temple
        case "famous restaurant":
            return .restaurant
        case "shopping mall":
            return .shoppingCenter
        case "historic site":
            return .historicalSite
        default:
            return .other
        }
    }
    
    /// 格式化地址
    private func formatAddress(_ placemark: MKPlacemark) -> String {
        var components: [String] = []
        
        if let thoroughfare = placemark.thoroughfare {
            components.append(thoroughfare)
        }
        if let locality = placemark.locality {
            components.append(locality)
        }
        if let administrativeArea = placemark.administrativeArea {
            components.append(administrativeArea)
        }
        
        return components.joined(separator: ", ")
    }
} 