import Foundation
import Combine
import CoreLocation

/// 景點列表視圖模型 - 負責景點排序、過濾和數量控制
@MainActor
class AttractionsListViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var processedAttractions: [TemplateMemoryModel] = []
    @Published var isProcessing: Bool = false
    @Published var totalValidAttractions: Int = 0
    @Published var currentProcessingStage: String = ""
    @Published var processingError: String?
    
    // MARK: - Private Properties
    private let maxAttractions = 50 // 最大景點數量限制
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Public Methods
    
    /// 處理和排序景點列表
    /// - Parameters:
    ///   - attractions: 待處理的景點列表
    ///   - userLocation: 用戶當前位置
    /// - Returns: 處理後的景點列表
    func processAndSortAttractions(_ attractions: [TemplateMemoryModel], 
                                  userLocation: CLLocationCoordinate2D) async -> [TemplateMemoryModel] {
        isProcessing = true
        currentProcessingStage = "開始處理景點列表..."
        processingError = nil
        
        // 1. 過濾有效景點（有Wikipedia資料的）
        currentProcessingStage = "過濾有效景點..."
        let validAttractions = attractions.filter { $0.hasWikipediaData }
        
        // 2. 按距離排序
        currentProcessingStage = "按距離排序..."
        let sortedAttractions = validAttractions.sorted { attraction1, attraction2 in
            return attraction1.distanceFromUser < attraction2.distanceFromUser
        }
        
        // 3. 更新處理階段
        let processedAttractions = sortedAttractions.map { attraction in
            let updatedAttraction = attraction
            return TemplateMemoryModel(
                names: updatedAttraction.names,
                addresses: updatedAttraction.addresses,
                latitude: updatedAttraction.latitude,
                longitude: updatedAttraction.longitude,
                descriptions: updatedAttraction.descriptions,
                source: updatedAttraction.source,
                distanceFromUser: updatedAttraction.distanceFromUser,
                searchRadius: updatedAttraction.searchRadius,
                processingStage: .sorted,
                hasWikipediaData: updatedAttraction.hasWikipediaData
            )
        }
        
        // 4. 限制數量
        currentProcessingStage = "限制景點數量..."
        let limitedAttractions = Array(processedAttractions.prefix(maxAttractions))
        
        // 5. 最終驗證
        currentProcessingStage = "最終驗證..."
        let finalAttractions = await validateAttractions(limitedAttractions)
        
        // 6. 更新狀態
        await MainActor.run {
            self.processedAttractions = finalAttractions
            self.totalValidAttractions = finalAttractions.count
            self.currentProcessingStage = "處理完成"
            self.isProcessing = false
        }
        
        return finalAttractions
    }
    
    /// 累計處理多個階段的景點
    /// - Parameters:
    ///   - newAttractions: 新的景點列表
    ///   - existingAttractions: 現有的景點列表
    /// - Returns: 合併後的景點列表
    func cumulativeProcess(_ newAttractions: [TemplateMemoryModel], 
                          with existingAttractions: [TemplateMemoryModel]) -> [TemplateMemoryModel] {
        // 合併新舊景點
        var allAttractions = existingAttractions + newAttractions
        
        // 去重（基於經緯度）
        allAttractions = removeDuplicates(allAttractions)
        
        // 按距離排序
        allAttractions.sort { $0.distanceFromUser < $1.distanceFromUser }
        
        // 限制總數量
        let limitedAttractions = Array(allAttractions.prefix(maxAttractions))
        
        // 更新總數
        totalValidAttractions = limitedAttractions.count
        
        return limitedAttractions
    }
    
    /// 檢查是否已達到最大景點數量
    var hasReachedMaxLimit: Bool {
        return totalValidAttractions >= maxAttractions
    }
    
    /// 獲取剩餘可添加的景點數量
    var remainingCapacity: Int {
        return max(0, maxAttractions - totalValidAttractions)
    }
    
    /// 清除所有資料
    func clearAll() {
        processedAttractions.removeAll()
        totalValidAttractions = 0
        currentProcessingStage = ""
        processingError = nil
        isProcessing = false
    }
    
    // MARK: - Private Methods
    
    /// 驗證景點資料
    private func validateAttractions(_ attractions: [TemplateMemoryModel]) async -> [TemplateMemoryModel] {
        return attractions.compactMap { attraction in
            // 驗證必要欄位
            guard !attraction.names.isEmpty,
                  attraction.latitude != 0.0,
                  attraction.longitude != 0.0,
                  attraction.hasWikipediaData else {
                return nil
            }
            
            // 更新為已驗證狀態
            return TemplateMemoryModel(
                names: attraction.names,
                addresses: attraction.addresses,
                latitude: attraction.latitude,
                longitude: attraction.longitude,
                descriptions: attraction.descriptions,
                source: attraction.source,
                distanceFromUser: attraction.distanceFromUser,
                searchRadius: attraction.searchRadius,
                processingStage: .validated,
                hasWikipediaData: attraction.hasWikipediaData
            )
        }
    }
    
    /// 去除重複景點（基於經緯度）
    private func removeDuplicates(_ attractions: [TemplateMemoryModel]) -> [TemplateMemoryModel] {
        var uniqueAttractions: [TemplateMemoryModel] = []
        
        for attraction in attractions {
            let isDuplicate = uniqueAttractions.contains { existing in
                let distance = calculateDistance(
                    from: CLLocationCoordinate2D(latitude: existing.latitude, longitude: existing.longitude),
                    to: CLLocationCoordinate2D(latitude: attraction.latitude, longitude: attraction.longitude)
                )
                return distance < 100 // 100米內視為重複
            }
            
            if !isDuplicate {
                uniqueAttractions.append(attraction)
            }
        }
        
        return uniqueAttractions
    }
    
    /// 計算兩點間距離
    private func calculateDistance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let fromLocation = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let toLocation = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return fromLocation.distance(from: toLocation)
    }
} 