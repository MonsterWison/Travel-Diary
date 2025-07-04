import Foundation
import MapKit
import Combine
import UIKit
import SwiftUI

/// 附近景點服務 - 負責搜索、緩存和管理50km內的全球景點
class NearbyAttractionsService: ObservableObject {
    // MARK: - Published Properties
    @Published var nearbyAttractions: [NearbyAttraction] = []
    @Published var isSearching: Bool = false
    @Published var searchError: Error?
    @Published var lastUpdateLocation: CLLocationCoordinate2D?
    
    // MARK: - Private Properties
    private let config: AttractionSearchConfig
    private let cacheFileName = "nearby_attractions_cache.json"
    private var cancellables = Set<AnyCancellable>()
    private let imageCache = NSCache<NSString, UIImage>()
    
    // 旅遊專用搜索關鍵詞配置 - 專注名勝古蹟、出名食肆、購物及旅遊景點
    private let searchKeywords = [
        // 名勝古蹟景點 (全球適用)
        "tourist attraction", "landmark", "monument", "heritage site", "historic site",
        "viewpoint", "observation deck", "scenic spot", "sightseeing", "point of interest",
        "visitor center", "tourist information", "cultural site",
        
        // 自然景觀及名勝
        "national park", "botanical garden", "zoo", "aquarium", "beach", "waterfall",
        "mountain", "lake", "scenic area", "nature reserve", "hiking trail",
        
        // 文化古蹟場所
        "museum", "art gallery", "cultural center", "exhibition hall", "palace", "castle",
        "historic building", "archaeological site", "heritage building", "monument",
        
        // 宗教古蹟
        "church", "cathedral", "mosque", "temple", "shrine", "monastery", "abbey",
        "basilica", "historic temple", "famous temple",
        
        // 出名食肆及美食
        "famous restaurant", "fine dining", "michelin restaurant", "local cuisine",
        "specialty restaurant", "traditional restaurant", "famous cafe", "rooftop bar",
        "food market", "night market", "street food", "signature restaurant",
        
        // 國際知名餐廳連鎖 (旅遊常去)
        "McDonald's", "KFC", "Starbucks", "Subway", "Pizza Hut", "Burger King",
        "Hard Rock Cafe", "TGI Friday's",
        
        // 大型購物商場
        "shopping mall", "shopping center", "department store", "outlet mall",
        "luxury shopping", "shopping district", "famous shopping", "souvenir shop",
        
        // 娛樂及旅遊設施
        "amusement park", "theme park", "entertainment center", "casino", "theater",
        "opera house", "concert hall", "sports stadium", "arena",
        
        // 中文旅遊關鍵詞
        "旅遊景點", "名勝古蹟", "觀光景點", "風景區", "觀景台", "地標",
        "博物館", "美術館", "文化中心", "宮殿", "古建築", "歷史建築",
        "寺廟", "廟宇", "教堂", "古寺", "名寺", "道觀",
        "出名餐廳", "知名餐廳", "特色餐廳", "美食", "老字號",
        "購物中心", "商場", "百貨公司", "購物區",
        "遊樂園", "主題公園", "娛樂場所",
        "國家公園", "植物園", "動物園", "水族館", "海灘", "瀑布"
    ]
    
    // MARK: - Initialization
    init(config: AttractionSearchConfig = .default) {
        self.config = config
        setupImageCache()
        loadCachedAttractions()
    }
    
    // MARK: - Public Methods
    
    /// 搜索附近景點 - 主要入口方法
    func searchNearbyAttractions(from location: CLLocationCoordinate2D) {
        // 檢查是否需要更新
        if let cachedData = loadCacheFromDisk(),
           !cachedData.needsUpdate(for: location, threshold: config.updateThreshold) &&
           !cachedData.isExpired(maxAge: config.cacheExpiry) {
            // 使用緩存數據
            self.nearbyAttractions = cachedData.sortedAttractions
            self.lastUpdateLocation = location
            return
        }
        
        // 執行新搜索
        performSearch(from: location)
    }
    
    /// 強制刷新附近景點
    func refreshAttractions(from location: CLLocationCoordinate2D) {
        performSearch(from: location)
    }
    
    /// 獲取指定距離內的景點
    func getAttractions(within distance: Double) -> [NearbyAttraction] {
        return nearbyAttractions.filter { $0.distanceFromUser <= distance }
    }
    
    /// 按分類獲取景點
    func getAttractions(by category: AttractionCategory) -> [NearbyAttraction] {
        return nearbyAttractions.filter { $0.category == category }
    }
    
    /// 清除緩存
    func clearCache() {
        nearbyAttractions.removeAll()
        deleteCacheFile()
        imageCache.removeAllObjects()
    }
    
    // MARK: - Private Methods
    
    private func setupImageCache() {
        // 設置圖片緩存配置
        imageCache.countLimit = 100 // 最多緩存100張圖片
        imageCache.totalCostLimit = 50 * 1024 * 1024 // 50MB記憶體限制
    }
    
    /// 執行景點搜索 - 採用高效率15組關鍵詞避免rate limiting
    private func performSearch(from location: CLLocationCoordinate2D) {
        isSearching = true
        searchError = nil
        
        var allResults: [NearbyAttraction] = []
        let dispatchGroup = DispatchGroup()
        
        // 選擇15個旅遊專用高效率關鍵詞進行並行搜索，避免MKLocalSearch rate limiting
        let highEfficiencyKeywords = [
            "tourist attraction", "famous restaurant", "shopping mall", "museum", "landmark",
            "national park", "historic site", "cultural center", "palace", "temple",
            "amusement park", "zoo", "botanical garden", "scenic spot", "heritage site"
        ]
        
        // 並行搜索多個關鍵詞，添加延遲避免rate limiting
        for (index, keyword) in highEfficiencyKeywords.enumerated() {
            dispatchGroup.enter()
            
            // 添加0.2秒延遲避免同時發送過多請求
            DispatchQueue.global().asyncAfter(deadline: .now() + Double(index) * 0.2) { [weak self] in
                self?.searchAttractions(keyword: keyword, location: location) { [weak self] results in
                    defer { dispatchGroup.leave() }
                    
                    guard let self = self else { return }
                    
                    // 過濾重複結果並添加到總結果中
                    let filteredResults = results.filter { newAttraction in
                        !allResults.contains { existing in
                            self.isSameLocation(existing.coordinate, newAttraction.coordinate, threshold: 100)
                        }
                    }
                    
                    allResults.append(contentsOf: filteredResults)
                }
            }
        }
        
        // 所有搜索完成後處理結果
        dispatchGroup.notify(queue: .main) { [weak self] in
            self?.processSearchResults(allResults, userLocation: location)
        }
    }
    
    /// 搜索特定關鍵詞的景點
    private func searchAttractions(keyword: String, location: CLLocationCoordinate2D, completion: @escaping ([NearbyAttraction]) -> Void) {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = keyword
        request.region = MKCoordinateRegion(
            center: location,
            latitudinalMeters: config.searchRadius * 2,
            longitudinalMeters: config.searchRadius * 2
        )
        
        // 設置搜索類型 - 主要搜索興趣點
        request.resultTypes = [.pointOfInterest, .address]
        
        // 全球適用搜索配置
        if #available(iOS 18.0, *) {
            request.addressFilter = MKAddressFilter(including: [.locality, .subLocality])
        }
        
        let search = MKLocalSearch(request: request)
        search.start { [weak self] response, error in
            guard let self = self else {
                completion([])
                return
            }
            
            if let error = error {
                DispatchQueue.main.async {
                    self.searchError = error
                }
                completion([])
                return
            }
            
            guard let response = response else {
                completion([])
                return
            }
            
            // 處理搜索結果
            let userLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
            let attractions = response.mapItems.compactMap { item -> NearbyAttraction? in
                let itemLocation = CLLocation(latitude: item.placemark.coordinate.latitude,
                                            longitude: item.placemark.coordinate.longitude)
                let distance = userLocation.distance(from: itemLocation)
                
                // ✅ 不再限制距離，讓搜索結果自然顯示
                // guard distance <= self.config.searchRadius else { return nil }
                
                // ✅ 不再過濾，讓旅遊專屬搜索關鍵字自然排除非旅遊地點
                
                let category = self.categorizeAttraction(item: item, keyword: keyword)
                
                // ✅ 保留所有分類的地點，讓旅遊專屬搜索關鍵字自然決定結果
                
                return NearbyAttraction(
                    name: item.name ?? "未知景點",
                    description: self.generateDescription(for: item),
                    coordinate: AttractionsCoordinate(from: item.placemark.coordinate),
                    distanceFromUser: distance,
                    category: category,
                    address: self.formatAddress(from: item.placemark),
                    rating: nil // MapKit不提供評分，後續可以從其他API獲取
                )
            }
            
            completion(attractions)
        }
    }
    
    /// 處理搜索結果
    private func processSearchResults(_ results: [NearbyAttraction], userLocation: CLLocationCoordinate2D) {
        // 按距離排序並限制為50個
        let sortedResults = results
            .sorted { $0.distanceFromUser < $1.distanceFromUser }
            .prefix(config.maxResults)
        
        var attractionsWithImages: [NearbyAttraction] = []
        let dispatchGroup = DispatchGroup()
        
        // 為每個景點獲取圖片
        for attraction in sortedResults {
            dispatchGroup.enter()
            
            fetchImage(for: attraction) { attractionWithImage in
                defer { dispatchGroup.leave() }
                attractionsWithImages.append(attractionWithImage)
            }
        }
        
        // 所有圖片獲取完成後更新UI和緩存
        dispatchGroup.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            
            // 重新按距離排序（因為異步獲取可能改變順序）
            let finalResults = attractionsWithImages.sorted { $0.distanceFromUser < $1.distanceFromUser }
            
            self.nearbyAttractions = finalResults
            self.lastUpdateLocation = userLocation
            self.isSearching = false
            
            // 保存到緩存
            self.saveCacheToDisk(attractions: finalResults, userLocation: userLocation)
        }
    }
    
    /// 獲取景點圖片
    private func fetchImage(for attraction: NearbyAttraction, completion: @escaping (NearbyAttraction) -> Void) {
        // 檢查緩存
        if let cachedImage = imageCache.object(forKey: attraction.name as NSString) {
            let imageData = cachedImage.jpegData(compressionQuality: 0.8)
            let updatedAttraction = NearbyAttraction(
                id: attraction.id,
                name: attraction.name,
                description: attraction.description,
                coordinate: attraction.coordinate,
                distanceFromUser: attraction.distanceFromUser,
                category: attraction.category,
                imageURL: attraction.imageURL,
                imageData: imageData,
                address: attraction.address,
                rating: attraction.rating
            )
            completion(updatedAttraction)
            return
        }
        
        // 暫時使用系統圖標代替真實圖片
        // 後續可以整合Unsplash或其他免費圖片API
        let placeholderImage = generatePlaceholderImage(for: attraction.category)
        let imageData = placeholderImage.jpegData(compressionQuality: 0.8)
        
        // 緩存圖片
        imageCache.setObject(placeholderImage, forKey: attraction.name as NSString)
        
        let updatedAttraction = NearbyAttraction(
            id: attraction.id,
            name: attraction.name,
            description: attraction.description,
            coordinate: attraction.coordinate,
            distanceFromUser: attraction.distanceFromUser,
            category: attraction.category,
            imageURL: attraction.imageURL,
            imageData: imageData,
            address: attraction.address,
            rating: attraction.rating
        )
        
        completion(updatedAttraction)
    }
    
    /// 分類景點 - 三層智能分類系統，符合全球適用和HIG規格
    private func categorizeAttraction(item: MKMapItem, keyword: String) -> AttractionCategory {
        let name = item.name?.lowercased() ?? ""
        let category = item.pointOfInterestCategory
        
        // 第一層：MapKit官方POI分類（僅限旅遊價值地點）
        if let poiCategory = category {
            switch poiCategory {
            // 🏛️ 文化旅遊場所
            case .museum: return .museum
            case .library: return .museum                   // 圖書館可能有歷史價值
            
            // 🌳 自然景觀
            case .park: return .park
            case .beach: return .beach
            case .nationalPark: return .park
            
            // 🏛️ 歷史古蹟
            case .castle: return .historicalSite
            case .landmark: return .historicalSite
            
            // 🎪 娛樂旅遊
            case .amusementPark: return .amusementPark
            case .zoo: return .amusementPark
            case .aquarium: return .amusementPark
            case .stadium: return .amusementPark
            case .theater: return .amusementPark
            case .movieTheater: return .amusementPark
            
            // 🍽️ 餐飲（只限著名或特色）
            case .restaurant, .cafe, .foodMarket: 
                // 只保留有特色或著名的餐廳
                if name.contains("famous") || name.contains("michelin") || name.contains("出名") ||
                   name.contains("mcdonalds") || name.contains("kfc") || name.contains("starbucks") ||
                   name.contains("hard rock") || name.contains("specialty") || name.contains("特色") {
                    return .restaurant
                }
                return .other  // 普通餐廳不顯示
            
            // 🛍️ 購物（只限大型商場）
            case .store:
                // 只保留大型購物商場
                if name.contains("mall") || name.contains("shopping center") || name.contains("商場") ||
                   name.contains("百貨") || name.contains("outlet") || name.contains("department") {
                    return .shoppingCenter
                }
                return .other  // 普通商店不顯示
            
            // ⛪ 宗教場所（有歷史文化價值） - 暫時註釋，需要確認API是否存在
            // case .placeOfWorship: return .temple           // 禮拜場所
            
            // 🏨 住宿（著名酒店可能有旅遊價值）
            case .hotel:
                if name.contains("resort") || name.contains("度假") || name.contains("heritage") ||
                   name.contains("historic") || name.contains("luxury") || name.contains("五星") {
                    return .other  // 暫時歸為其他，後續可以考慮增加住宿類別
                }
                return .other
            
            // 🚫 明確排除所有其他類型
            default: return .other
            }
        }
        
        // 第二層：智能名稱分析（專注旅遊價值場所）
        // 出名餐廳類 (Restaurant - fork.knife)
        if name.contains("famous") || name.contains("michelin") || name.contains("fine dining") || name.contains("specialty") ||
           name.contains("出名") || name.contains("知名") || name.contains("特色") || name.contains("老字號") ||
           name.contains("restaurant") || name.contains("餐廳") || name.contains("rooftop") ||
           name.contains("mcdonalds") || name.contains("mcdonald's") || name.contains("麥當勞") ||
           name.contains("kfc") || name.contains("肯德基") || name.contains("starbucks") || name.contains("星巴克") ||
           name.contains("hard rock") || name.contains("tgi") || name.contains("茶樓") || name.contains("酒樓") { return .restaurant }
        
        // 大型購物商場類 (Shopping - bag)
        if name.contains("shopping mall") || name.contains("shopping center") || name.contains("department") ||
           name.contains("outlet") || name.contains("luxury") || name.contains("購物中心") || name.contains("商場") ||
           name.contains("百貨") || name.contains("購物區") || name.contains("souvenir") { return .shoppingCenter }
        
        // 公園類 (Park - tree)
        if name.contains("park") || name.contains("公園") || name.contains("garden") || name.contains("花園") ||
           name.contains("beach") || name.contains("海灘") || name.contains("海灘") || name.contains("forest") ||
           name.contains("森林") || name.contains("nature") || name.contains("自然") { return .park }
        
        // 博物館類 (Museum - building.2)
        if name.contains("museum") || name.contains("博物館") || name.contains("gallery") || name.contains("美術館") ||
           name.contains("library") || name.contains("圖書館") || name.contains("exhibition") || name.contains("展覽") ||
           name.contains("cultural center") || name.contains("文化中心") || name.contains("archive") { return .museum }
        
        // 宗教場所 (Temple - building.2.crop.circle)
        if name.contains("temple") || name.contains("廟") || name.contains("寺") || name.contains("church") ||
           name.contains("教堂") || name.contains("mosque") || name.contains("清真寺") || name.contains("synagogue") ||
           name.contains("cathedral") || name.contains("chapel") || name.contains("monastery") || name.contains("abbey") { return .temple }
        
        // 娛樂場所 (Entertainment - ferriswheel)
        if name.contains("amusement") || name.contains("遊樂園") || name.contains("theme park") || name.contains("主題公園") ||
           name.contains("cinema") || name.contains("電影院") || name.contains("theater") || name.contains("劇院") ||
           name.contains("entertainment") || name.contains("娛樂") || name.contains("arcade") { return .amusementPark }
        
        // 觀景台 (Viewpoint - eye)
        if name.contains("viewpoint") || name.contains("觀景台") || name.contains("observation") || name.contains("observatory") ||
           name.contains("lookout") || name.contains("scenic") || name.contains("風景") || name.contains("vista") { return .viewpoint }
        
        // 歷史建築 (Historical - building.columns)
        if name.contains("palace") || name.contains("宮殿") || name.contains("castle") || name.contains("城堡") ||
           name.contains("monument") || name.contains("紀念") || name.contains("heritage") || name.contains("遺產") ||
           name.contains("historic") || name.contains("古") || name.contains("heritage site") { return .historicalSite }
        
        // 第三層：根據旅遊搜索關鍵詞分類（備用）
        let keywordLower = keyword.lowercased()
        if keywordLower.contains("famous restaurant") || keywordLower.contains("fine dining") || keywordLower.contains("出名餐廳") { return .restaurant }
        if keywordLower.contains("shopping mall") || keywordLower.contains("shopping center") || keywordLower.contains("購物中心") { return .shoppingCenter }
        if keywordLower.contains("national park") || keywordLower.contains("botanical garden") || keywordLower.contains("國家公園") { return .park }
        if keywordLower.contains("museum") || keywordLower.contains("博物館") || keywordLower.contains("cultural center") { return .museum }
        if keywordLower.contains("temple") || keywordLower.contains("church") || keywordLower.contains("寺廟") { return .temple }
        if keywordLower.contains("amusement park") || keywordLower.contains("theme park") || keywordLower.contains("遊樂園") { return .amusementPark }
        if keywordLower.contains("viewpoint") || keywordLower.contains("scenic spot") || keywordLower.contains("觀景台") { return .viewpoint }
        if keywordLower.contains("palace") || keywordLower.contains("castle") || keywordLower.contains("heritage site") { return .historicalSite }
        
        return .other
    }
    
    /// 格式化地址
    private func formatAddress(from placemark: MKPlacemark) -> String? {
        let components = [
            placemark.thoroughfare,
            placemark.locality,
            placemark.administrativeArea
        ].compactMap { $0 }.joined(separator: ", ")
        
        return components.isEmpty ? nil : components
    }
    
    /// 生成景點描述
    private func generateDescription(for item: MKMapItem) -> String {
        var description = ""
        
        if let name = item.name {
            description += "景點名稱: \(name)\n"
        }
        
        if let address = formatAddress(from: item.placemark) {
            description += "地址: \(address)\n"
        }
        
        if let category = item.pointOfInterestCategory {
            description += "類型: \(category.rawValue)\n"
        }
        
        return description.isEmpty ? "詳細信息待更新" : description
    }
    
    /// 檢查兩個坐標是否為同一地點
    private func isSameLocation(_ coord1: AttractionsCoordinate, _ coord2: AttractionsCoordinate, threshold: Double) -> Bool {
        let location1 = CLLocation(latitude: coord1.latitude, longitude: coord1.longitude)
        let location2 = CLLocation(latitude: coord2.latitude, longitude: coord2.longitude)
        return location1.distance(from: location2) < threshold
    }
    
    // MARK: - Cache Management
    
    /// 保存緩存到磁盤
    private func saveCacheToDisk(attractions: [NearbyAttraction], userLocation: CLLocationCoordinate2D) {
        let cache = NearbyAttractionsCache(
            attractions: attractions,
            lastUserLocation: AttractionsCoordinate(from: userLocation),
            searchRadius: config.searchRadius,
            maxResults: config.maxResults
        )
        
        do {
            let data = try JSONEncoder().encode(cache)
            let url = getCacheFileURL()
            try data.write(to: url)
        } catch {
            print("保存景點緩存失敗: \(error)")
        }
    }
    
    /// 從磁盤加載緩存
    private func loadCacheFromDisk() -> NearbyAttractionsCache? {
        do {
            let url = getCacheFileURL()
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(NearbyAttractionsCache.self, from: data)
        } catch {
            print("讀取景點緩存失敗: \(error)")
            return nil
        }
    }
    
    /// 從緩存文件加載景點
    private func loadCachedAttractions() {
        if let cache = loadCacheFromDisk() {
            self.nearbyAttractions = cache.sortedAttractions
            if let lastLocation = lastUpdateLocation {
                self.lastUpdateLocation = lastLocation
            }
        }
    }
    
    /// 刪除緩存文件
    private func deleteCacheFile() {
        do {
            let url = getCacheFileURL()
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            print("刪除景點緩存失敗: \(error)")
        }
    }
    
    /// 獲取緩存文件URL
    private func getCacheFileURL() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent(cacheFileName)
    }
} 