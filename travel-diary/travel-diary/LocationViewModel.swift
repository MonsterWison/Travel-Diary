import Foundation
import CoreLocation
import Combine
import MapKit
import SwiftUI

/// 搜索結果數據模型
struct SearchResult: Identifiable {
    let id = UUID()
    let name: String
    let subtitle: String?
    let coordinate: CLLocationCoordinate2D
    let placemark: MKPlacemark
}

/// 位置ViewModel - 處理地圖相關的業務邏輯
class LocationViewModel: ObservableObject {
    private let locationService = LocationService()
    private var cancellables = Set<AnyCancellable>()
    
    // 常數定義
    private static let hongKongLatitude: Double = 22.307761
    private static let hongKongLongitude: Double = 114.257263
    private static let mapMovementThreshold: Double = 0.0005 // 約50米
    
    // HIG: 地圖縮放級別常數 - 按照 Apple 推薦的街道級別視圖
    private static let streetLevelSpan = MKCoordinateSpan(latitudeDelta: 0.001, longitudeDelta: 0.001) // 約100米範圍
    private static let neighborhoodSpan = MKCoordinateSpan(latitudeDelta: 0.003, longitudeDelta: 0.003) // 約300米範圍
    
    // MARK: - Published Properties
    @Published var currentLocation: CLLocation?
    @Published var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 22.3193, longitude: 114.1694), // 預設香港座標
        span: streetLevelSpan // HIG: 使用街道級別的默認縮放
    )
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var showingLocationAlert = false
    @Published var currentAddress: String = "定位中..."
    @Published var travelPoints: [TravelPoint] = []
    @Published var debugInfo: String = "初始化中..."
    @Published var locationError: Error?
    @Published var isTrackingUser: Bool = false // 是否跟隨用戶位置
    
    // MARK: - 搜索相關屬性
    @Published var searchText: String = ""
    @Published var searchResults: [SearchResult] = []
    @Published var isSearching: Bool = false
    @Published var selectedSearchResult: SearchResult?
    @Published var showingSearchResults: Bool = false
    @Published var gpsSignalStrength: GPSSignalStrength = .invalid
    
    // HIG: 方向指示相關屬性 - 符合Apple Maps標準
    @Published var currentHeading: CLHeading?
    @Published var headingAccuracy: CLLocationDegrees = -1
    @Published var headingError: Error?
    
    // 私有屬性 - 追蹤是否已經獲取過真實位置
    private var hasReceivedFirstRealLocation = false
    // 追蹤用戶是否手動移動了地圖
    @Published var userHasMovedMap: Bool = false
    // 追蹤是否正在程序化更新地圖（防止觸發用戶移動標記）
    private var isProgrammaticUpdate: Bool = false
    // 追蹤上一次的地圖中心位置
    private var lastKnownMapCenter: CLLocationCoordinate2D?
    
    // 搜索相關私有屬性
    private var searchCompleter = MKLocalSearchCompleter()
    private var searchCancellable: AnyCancellable?
    
    // 計算屬性：判斷地圖是否中心在當前位置
    var isMapCenteredOnLocation: Bool {
        guard let currentLocation = currentLocation else { return false }
        
        let currentCoordinate = currentLocation.coordinate
        let mapCenter = region.center
        
        // 計算距離差（使用較小的閾值，約100米）
        let latDiff = abs(currentCoordinate.latitude - mapCenter.latitude)
        let lonDiff = abs(currentCoordinate.longitude - mapCenter.longitude)
        
        // 約100米的緯度差
        let threshold = 0.001
        
        return latDiff < threshold && lonDiff < threshold
    }
    
    // 計算屬性：智能定位按鈕狀態
    var shouldShowActiveLocationButton: Bool {
        return !isMapCenteredOnLocation && currentLocation != nil
    }
    
    // MARK: - Initialization
    init() {
        bindLocationService()
        setupSearch()
        updateDebugInfo()
        
        // HIG: 立即請求位置權限，不延遲
        requestLocationPermission()
    }
    
    // MARK: - Private Methods
    private func bindLocationService() {
        // 綁定位置服務的狀態
        locationService.$currentLocation
            .receive(on: DispatchQueue.main)
            .sink { [weak self] location in
                self?.handleLocationUpdate(location)
            }
            .store(in: &cancellables)
        
        locationService.$authorizationStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.authorizationStatus = status
                self?.handleAuthorizationChange(status)
            }
            .store(in: &cancellables)
        
        locationService.$locationError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                self?.handleLocationError(error)
            }
            .store(in: &cancellables)
        
        locationService.$gpsSignalStrength
            .receive(on: DispatchQueue.main)
            .sink { [weak self] strength in
                self?.gpsSignalStrength = strength
            }
            .store(in: &cancellables)
        
        // HIG: 綁定方向相關屬性 - 符合Apple Maps標準
        locationService.$currentHeading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] heading in
                self?.currentHeading = heading
                self?.updateDebugInfo()
            }
            .store(in: &cancellables)
        
        locationService.$headingAccuracy
            .receive(on: DispatchQueue.main)
            .sink { [weak self] accuracy in
                self?.headingAccuracy = accuracy
            }
            .store(in: &cancellables)
        
        locationService.$headingError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                self?.headingError = error
            }
            .store(in: &cancellables)
    }
    
    private func handleLocationUpdate(_ location: CLLocation?) {
        guard let location = location else { return }
        
        currentLocation = location
        updateDebugInfo()
        
        // 檢查是否為固定的香港位置
        if isFixedHongKongLocation(location) {
            currentAddress = "香港新界將軍澳彩明苑彩富閣"
        }
        
        // 改進的地圖跟隨邏輯
        let isFirstRealLocation = !hasReceivedFirstRealLocation
        let shouldAutoFollow = !userHasMovedMap || isFirstRealLocation
        
        if shouldAutoFollow {
            // HIG: 首次位置使用街道級別，後續使用當前縮放級別
            let zoomLevel = isFirstRealLocation ? Self.streetLevelSpan : region.span
            updateMapRegion(to: location.coordinate, span: zoomLevel)
            
            // 重置用戶移動標記，開始新的自動跟隨
            if userHasMovedMap {
                userHasMovedMap = false
            }
            
            // 標記已經獲取過真實位置
            if isFirstRealLocation {
                hasReceivedFirstRealLocation = true
            }
        }
        
        // 獲取地址信息（只有在非固定位置時才進行地理編碼）
        if !isFixedHongKongLocation(location) {
            locationService.getAddressFromLocation(location) { [weak self] address in
                DispatchQueue.main.async {
                    self?.currentAddress = address ?? "無法獲取地址"
                    self?.updateDebugInfo()
                }
            }
        } else {
            updateDebugInfo()
        }
    }
    
    /// 檢查是否為固定香港位置
    private func isFixedHongKongLocation(_ location: CLLocation) -> Bool {
        return abs(location.coordinate.latitude - Self.hongKongLatitude) < 0.0001 &&
               abs(location.coordinate.longitude - Self.hongKongLongitude) < 0.0001
    }
    
    private func handleAuthorizationChange(_ status: CLAuthorizationStatus) {
        updateDebugInfo()
        switch status {
        case .denied, .restricted:
            showingLocationAlert = true
            currentAddress = "位置權限被拒絕"
        case .authorizedWhenInUse, .authorizedAlways:
            showingLocationAlert = false
            currentAddress = "正在獲取位置..."
        case .notDetermined:
            currentAddress = "等待位置權限..."
        @unknown default:
            break
        }
    }
    
    private func handleLocationError(_ error: Error?) {
        locationError = error
        if let error = error {
            currentAddress = "位置獲取失敗: \(error.localizedDescription)"
        }
        updateDebugInfo()
    }
    
    // HIG: 改進的地圖區域更新方法，支持自定義縮放
    private func updateMapRegion(to coordinate: CLLocationCoordinate2D, span: MKCoordinateSpan? = nil) {
        isProgrammaticUpdate = true
        let newSpan = span ?? region.span
        
        withAnimation(.easeInOut(duration: 1.0)) {
            region = MKCoordinateRegion(
                center: coordinate,
                span: newSpan
            )
        }
        
        // 更新已知的地圖中心位置
        lastKnownMapCenter = coordinate
        
        // 延遲重置標記，確保動畫完成後才允許檢測用戶移動
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            self.isProgrammaticUpdate = false
        }
    }
    
    /// 處理用戶手動移動地圖
    func handleUserMapMovement() {
        guard !isProgrammaticUpdate else { 
            return 
        }
        
        // 檢查地圖中心是否有顯著變化
        let currentMapCenter = region.center
        
        if let lastCenter = lastKnownMapCenter {
            let latDiff = abs(currentMapCenter.latitude - lastCenter.latitude)
            let lonDiff = abs(currentMapCenter.longitude - lastCenter.longitude)
            
            // 如果變化超過閾值（約50米），認為是用戶手動移動
            if latDiff > Self.mapMovementThreshold || lonDiff > Self.mapMovementThreshold {
                if !userHasMovedMap {
                    userHasMovedMap = true
                }
                lastKnownMapCenter = currentMapCenter
            }
        } else {
            // 首次設置基準位置
            lastKnownMapCenter = currentMapCenter
        }
    }
    
    // MARK: - Public Methods
    func requestLocationPermission() {
        hasReceivedFirstRealLocation = false // 重置標記，下次獲取位置時自動跟隨
        locationService.requestLocationPermission()
    }
    
    /// 添加旅行路徑點
    func addTravelPoint() {
        guard let location = currentLocation else { return }
        
        let newPoint = TravelPoint(
            id: UUID(),
            coordinate: location.coordinate,
            timestamp: Date(),
            address: currentAddress
        )
        
        travelPoints.append(newPoint)
    }
    
    /// 中心化到當前位置並恢復自動跟隨
    func centerOnCurrentLocation() {
        guard let location = currentLocation else {
            requestLocationPermission()
            return
        }
        
        // 重置用戶移動標記，恢復自動跟隨
        userHasMovedMap = false
        
        // HIG: 定位按鈕點擊時使用街道級別縮放
        updateMapRegion(to: location.coordinate, span: Self.streetLevelSpan)
    }
    
    /// 切換用戶位置跟隨模式（保持向後兼容）
    func toggleUserTracking() {
        // 新邏輯：直接調用中心化方法
        centerOnCurrentLocation()
    }
    
    /// 清除所有旅行路徑點
    func clearTravelPoints() {
        travelPoints.removeAll()
    }
    
    /// 更新調試信息
    private func updateDebugInfo() {
        let authStatus = locationService.authorizationStatus
        let hasLocation = currentLocation != nil
        let errorInfo = locationError?.localizedDescription ?? "無"
        debugInfo = """
        權限狀態: \(authStatusString(authStatus))
        當前位置: \(hasLocation ? "有" : "無")
        位置服務: \(CLLocationManager.locationServicesEnabled() ? "開啟" : "關閉")
        錯誤信息: \(errorInfo)
        """
    }
    
    private func authStatusString(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "未決定"
        case .restricted: return "受限制"
        case .denied: return "拒絕"
        case .authorizedAlways: return "總是允許"
        case .authorizedWhenInUse: return "使用時允許"
        @unknown default: return "未知"
        }
    }
    
    // MARK: - 搜索設置（符合HIG本地化標準）
    private func setupSearch() {
        // HIG: 設置搜索文字變化監聽，縮短延遲提高響應性
        $searchText
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main) // 縮短延遲
            .removeDuplicates()
            .sink { [weak self] searchText in
                self?.performSearch(query: searchText)
            }
            .store(in: &cancellables)
        
        // HIG: 配置搜索自動完成器使用中文本地化
        configureSearchCompleter()
    }
    
    // MARK: - HIG本地化配置
    private func configureSearchCompleter() {
        // HIG: 確保搜索結果優先顯示中文地名
        searchCompleter.resultTypes = [.address, .pointOfInterest]
        // 設置搜索區域為香港及周邊，確保結果相關性
        if let currentLocation = currentLocation {
            searchCompleter.region = MKCoordinateRegion(
                center: currentLocation.coordinate,
                latitudinalMeters: 50000, // 50公里範圍
                longitudinalMeters: 50000
            )
        } else {
            // 默認香港區域
            searchCompleter.region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 22.3193, longitude: 114.1694),
                latitudinalMeters: 100000, // 100公里範圍覆蓋大灣區
                longitudinalMeters: 100000
            )
        }
    }
    
    /// HIG: 配置應用本地化設置
    func configureLocalization(locale: Locale) {
        // 更新搜索自動完成器的區域設置
        configureSearchCompleter()
    }
    
    // MARK: - HIG標準搜索方法（符合Apple Maps本地化規範）
    func performSearch(query: String) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // HIG: 搜索文字為空時清理搜索狀態
            searchResults = []
            showingSearchResults = false
            selectedSearchResult = nil
            isSearching = false
            return
        }
        
        isSearching = true
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        
        // HIG: 設置本地化搜索，確保結果優先顯示中文地名但包含所有相關信息
        request.region = MKCoordinateRegion(
            center: currentLocation?.coordinate ?? CLLocationCoordinate2D(
                latitude: Self.hongKongLatitude, 
                longitude: Self.hongKongLongitude
            ),
            latitudinalMeters: 100000, // 恢復合理搜索範圍，確保建築物信息完整
            longitudinalMeters: 100000
        )
        
        // HIG: 設置搜索結果類型，完全模仿Apple Maps行為，包含建築物
        request.resultTypes = [.pointOfInterest, .address]
        
        // HIG: 確保搜索結果使用中文本地化，但不過度限制內容
        if #available(iOS 18.0, *) {
            // 使用更寬鬆的地址過濾，確保建築物名稱不會被排除
            request.addressFilter = MKAddressFilter(including: [.locality, .subLocality, .administrativeArea])
        }
        
        let search = MKLocalSearch(request: request)
        
        // 取消之前的搜索
        searchCancellable?.cancel()
        
        searchCancellable = Future<[SearchResult], Error> { promise in
            search.start { response, error in
                if let error = error {
                    promise(.failure(error))
                    return
                }
                
                guard let response = response else {
                    promise(.success([]))
                    return
                }
                
                // HIG: 優化搜索結果，提供更豐富的地址信息
                let results = response.mapItems.map { item in
                    let name = item.name ?? "未知位置"
                    let subtitle = [
                        item.placemark.thoroughfare,
                        item.placemark.locality,
                        item.placemark.administrativeArea
                    ].compactMap { $0 }.joined(separator: ", ")
                    
                    return SearchResult(
                        name: name,
                        subtitle: subtitle.isEmpty ? nil : subtitle,
                        coordinate: item.placemark.coordinate,
                        placemark: item.placemark
                    )
                }
                
                promise(.success(results))
            }
        }
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { [weak self] completion in
                self?.isSearching = false
            },
            receiveValue: { [weak self] results in
                self?.searchResults = results
                // HIG: 保持搜索界面顯示，無論是否有結果
                // showingSearchResults 由View層的onChange控制
            }
        )
    }
    
    // HIG: 選擇搜索結果並更新地圖
    func selectSearchResult(_ result: SearchResult) {
        selectedSearchResult = result
        showingSearchResults = false
        searchText = result.name
        
        // HIG: 重置用戶移動標記，允許搜索結果覆蓋用戶行為
        userHasMovedMap = false
        
        // HIG: 移動地圖到搜索結果位置，使用適當的縮放級別
        moveToLocation(coordinate: result.coordinate, zoomLevel: .neighborhood)
    }
    
    // HIG: 立即執行搜索（用於用戶按執行鍵時）
    func performImmediateSearch() {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        // 取消debounce，立即搜索
        searchCancellable?.cancel()
        performSearch(query: searchText)
    }
    
    // HIG: 清除搜索結果
    func clearSearch() {
        searchText = ""
        searchResults = []
        selectedSearchResult = nil
        showingSearchResults = false
        isSearching = false
    }
    
    // 移動到指定位置的方法（支持不同縮放級別）
    enum ZoomLevel {
        case street    // 街道級別 (100米)
        case neighborhood  // 社區級別 (300米)
        case city      // 城市級別 (1公里)
        
        var span: MKCoordinateSpan {
            switch self {
            case .street:
                return MKCoordinateSpan(latitudeDelta: 0.001, longitudeDelta: 0.001)
            case .neighborhood:
                return MKCoordinateSpan(latitudeDelta: 0.003, longitudeDelta: 0.003)
            case .city:
                return MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            }
        }
    }
    
    // HIG: 移動地圖到指定位置（支持不同縮放級別）
    func moveToLocation(coordinate: CLLocationCoordinate2D, zoomLevel: ZoomLevel = .neighborhood) {
        isProgrammaticUpdate = true
        
        // HIG: 使用平滑動畫移動地圖
        withAnimation(.easeInOut(duration: 1.0)) {
            region = MKCoordinateRegion(
                center: coordinate,
                span: zoomLevel.span
            )
        }
        
        // 延遲重置程序化更新標記
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            self.isProgrammaticUpdate = false
        }
        
        // 標記用戶已移動地圖（如果不是移動到當前位置）
        if let currentLocation = currentLocation {
            let currentCoordinate = currentLocation.coordinate
            let distance = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                .distance(from: CLLocation(latitude: currentCoordinate.latitude, longitude: currentCoordinate.longitude))
            
            if distance > 100 { // 如果距離超過100米，標記為用戶移動
                userHasMovedMap = true
            }
        }
    }
}

// MARK: - TravelPoint Model
struct TravelPoint: Identifiable, Equatable {
    let id: UUID
    let coordinate: CLLocationCoordinate2D
    let timestamp: Date
    let address: String
    
    static func == (lhs: TravelPoint, rhs: TravelPoint) -> Bool {
        lhs.id == rhs.id
    }
}

// 使 CLLocationCoordinate2D 符合 Equatable
extension CLLocationCoordinate2D: @retroactive Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
} 