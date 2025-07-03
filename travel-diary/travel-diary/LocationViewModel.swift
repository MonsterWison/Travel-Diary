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
    
    // MARK: - 附近景點面板屬性
    @Published var nearbyAttractions: [NearbyAttraction] = []
    @Published var isLoadingAttractions: Bool = false
    @Published var isUsingCachedData: Bool = false // 標示是否正在使用緩存數據
    
    // MARK: - 手動更新冷卻機制
    @Published private var lastManualRefreshTime: Date?
    @Published var isManualRefreshing: Bool = false // 標示是否正在手動更新中
    private let manualRefreshCooldown: TimeInterval = 10.0 // 10秒冷卻期，遵循Apple MapKit API最佳實踐
    
    // MARK: - 倒數計時器
    @Published private var timerTrigger: Int = 0 // 觸發UI更新的計時器屬性
    private var cooldownTimer: Timer? // 倒數計時器
    
    // HIG: 數據持久化屬性
    private let attractionsCacheKey = "nearbyAttractionsCache"
    
    // HIG: 面板狀態管理（遵循Apple Maps交互設計）
    @Published var attractionPanelState: AttractionPanelState = .hidden
    @Published var attractionPanelOffset: CGFloat = 0
    
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
        
        // 用戶要求：每次打開時景點搜尋器是縮小狀態（compact）
        attractionPanelState = .compact
        
        // HIG: 立即請求位置權限，不延遲
        requestLocationPermission()
    }
    
    // MARK: - Deinitialization
    deinit {
        stopCooldownTimer()
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
        
        // HIG: 智能景點搜索觸發邏輯
        if isFirstRealLocation {
            searchNearbyAttractions()
        } else {
            // 檢查是否需要重新搜索（應用重啟或長時間未搜索時）
            checkAndTriggerAttractionsSearchIfNeeded()
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
    
    // MARK: - MVVM: ViewModel從Model獲取數據
    /// MVVM架構：ViewModel從Model獲取處理好的景點數據
    func searchNearbyAttractions() {
        print("🎯 ViewModel: 開始從Model獲取景點數據...")
        print("   - 當前位置: \(currentLocation?.coordinate.latitude ?? 0),\(currentLocation?.coordinate.longitude ?? 0)")
        print("   - 面板狀態: \(attractionPanelState)")
        
        guard let location = currentLocation else { 
            print("❌ 沒有當前位置，搜索取消")
            return 
        }
        
        guard !isLoadingAttractions else {
            print("🔍 正在搜索中，跳過重複請求")
            return
        }
        
        isLoadingAttractions = true
        print("🔍 ViewModel: 開始從Model獲取數據，面板保持縮小狀態")
        
        // MVVM: ViewModel使用Model來處理業務邏輯
        let attractionsModel = NearbyAttractionsModel()
        attractionsModel.searchNearbyAttractions(coordinate: location.coordinate) { [weak self] processedAttractions in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                // ViewModel從Model獲取處理好的數據
                self.nearbyAttractions = processedAttractions
                self.isLoadingAttractions = false
                
                print("✅ ViewModel: 從Model成功獲取 \(processedAttractions.count) 個景點")
                
                if !processedAttractions.isEmpty {
                    // 顯示距離範圍信息
                    if let nearest = processedAttractions.first, let farthest = processedAttractions.last {
                        let nearestDistance = nearest.distanceFromUser < 1000 ? 
                            "\(Int(nearest.distanceFromUser))米" : 
                            String(format: "%.1fkm", nearest.distanceFromUser/1000)
                        let farthestDistance = farthest.distanceFromUser < 1000 ? 
                            "\(Int(farthest.distanceFromUser))米" : 
                            String(format: "%.1fkm", farthest.distanceFromUser/1000)
                        print("📏 距離範圍：最近\(nearestDistance) - 最遠\(farthestDistance)")
                    }
                    
                    // MVVM: 標記為實時數據（非緩存）
                    self.isUsingCachedData = false
                    
                    // HIG: 後台自動保存到緩存
                    self.autoSaveAttractionsToCache()
                    
                    // 用戶要求：面板始終保持縮小狀態，更新景點數據
                    print("🔄 景點搜尋器保持縮小狀態，數據已更新（\(processedAttractions.count)個景點）")
                    // 確保面板是縮小狀態（只有當前不是展開狀態時才自動縮小）
                    if self.attractionPanelState != .compact && self.attractionPanelState != .expanded {
                        self.attractionPanelState = .compact
                    }
                } else {
                    print("❌ Model返回空數據")
                    print("📱 沒有景點，保持搜尋器縮小狀態")
                    
                    // 用戶要求：沒有景點時保持面板縮小狀態
                    if self.attractionPanelState != .compact {
                        self.attractionPanelState = .compact
                    }
                    self.isUsingCachedData = false
                }
            }
        }
    }
    
    /// HIG: 檢查並觸發必要的景點搜索（解決應用重啟後面板消失的問題）
    private func checkAndTriggerAttractionsSearchIfNeeded() {
        print("🔍 檢查景點搜索條件:")
        print("   - 有位置: \(currentLocation != nil)")
        print("   - 景點數據為空: \(nearbyAttractions.isEmpty)")
        print("   - 搜索中: \(isLoadingAttractions)")
        print("   - 面板狀態: \(attractionPanelState)")
        
        // 更寬鬆的條件：只要有位置且沒在搜索中就觸發
        guard let _ = currentLocation,
              !isLoadingAttractions else {
            print("❌ 不符合搜索條件，跳過觸發")
            return
        }
        
        // 如果已經有景點數據，確保面板是縮小狀態
        if !nearbyAttractions.isEmpty {
            print("✅ 有景點數據，確保面板是縮小狀態")
            DispatchQueue.main.async {
                if self.attractionPanelState != .compact {
                    self.attractionPanelState = .compact
                }
            }
            return
        }
        
        // 如果沒有景點數據，觸發搜索
        if nearbyAttractions.isEmpty {
            print("✅ 沒有景點數據，觸發搜索")
            searchNearbyAttractions()
        } else if isUsingCachedData {
            // 如果正在使用緩存數據，觸發後台更新
            print("🔄 正在使用緩存數據，觸發後台更新")
            DispatchQueue.global(qos: .utility).async {
                DispatchQueue.main.async {
                    self.searchNearbyAttractions()
                }
            }
        } else {
            print("✅ 已有最新數據，無需搜索")
        }
    }
    
    /// HIG: 基於MKMapItem的實際POI類型進行正確分類（符合Apple HIG規範）
    private func getCategoryFromMKMapItem(_ mapItem: MKMapItem, searchQuery: String) -> AttractionCategory {
        // 1. 首先檢查MKMapItem的pointOfInterestCategory（最準確）
        if #available(iOS 16.0, *) {
            if let poiCategory = mapItem.pointOfInterestCategory {
                switch poiCategory {
                case .restaurant, .foodMarket, .bakery, .brewery:
                    return .restaurant
                case .store, .gasStation:
                    return .shoppingCenter
                case .hospital, .pharmacy:
                    return .other
                case .school, .university, .library, .museum:
                    return .museum
                case .park, .nationalPark, .zoo, .aquarium:
                    return .park
                case .beach:
                    return .park  // 海灘歸類為自然景觀
                case .amusementPark:
                    return .amusementPark
                case .bank, .atm:
                    return .other
                case .hotel:
                    return .other
                default:
                    break
                }
            }
        }
        
        // 2. 基於景點名稱智能分類（處理中文和英文）
        let name = mapItem.name?.lowercased() ?? ""
        
        // 餐飲類別（包含常見中英文餐廳名稱）
        if name.contains("restaurant") || name.contains("cafe") || name.contains("coffee") ||
           name.contains("mcdonald") || name.contains("kfc") || name.contains("starbucks") ||
           name.contains("餐廳") || name.contains("茶餐廳") || name.contains("酒樓") || name.contains("茶樓") ||
           name.contains("咖啡") || name.contains("翠華") || name.contains("大家樂") || name.contains("美心") ||
           name.contains("太平洋咖啡") || name.contains("食") || name.contains("廳") ||
           name.contains("pizza") || name.contains("burger") || name.contains("subway") ||
           name.contains("粥") || name.contains("麵") || name.contains("飯") || name.contains("點心") ||
           name.contains("甜品") || name.contains("燒臘") || name.contains("海鮮") {
            return .restaurant
        }
        
        // 購物類別
        if name.contains("shop") || name.contains("store") || name.contains("mall") || name.contains("market") ||
           name.contains("7-eleven") || name.contains("circle k") || name.contains("ok便利店") ||
           name.contains("商場") || name.contains("購物") || name.contains("便利店") || name.contains("超市") ||
           name.contains("商店") || name.contains("百貨") || name.contains("shopping") ||
           name.contains("惠康") || name.contains("百佳") || name.contains("萬寧") || name.contains("屈臣氏") ||
           name.contains("街市") || name.contains("市場") {
            return .shoppingCenter
        }
        
        // 醫療機構
        if name.contains("hospital") || name.contains("clinic") || name.contains("pharmacy") ||
           name.contains("醫院") || name.contains("診所") || name.contains("藥房") || name.contains("醫療") {
            return .other
        }
        
        // 教育機構
        if name.contains("school") || name.contains("university") || name.contains("college") || name.contains("library") ||
           name.contains("學校") || name.contains("大學") || name.contains("學院") || name.contains("圖書館") {
            return .museum
        }
        
        // 公園和自然景觀（包括海灘）
        if name.contains("park") || name.contains("garden") || name.contains("beach") ||
           name.contains("公園") || name.contains("花園") || name.contains("海灘") || name.contains("郊野公園") ||
           name.contains("山") || name.contains("海") || name.contains("自然") {
            return .park
        }
        
        // 廟宇和宗教場所
        if name.contains("temple") || name.contains("church") || name.contains("mosque") ||
           name.contains("廟") || name.contains("寺") || name.contains("教堂") || name.contains("天主教") ||
           name.contains("佛教") || name.contains("道觀") {
            return .temple
        }
        
        // 博物館和文化場所
        if name.contains("museum") || name.contains("gallery") || name.contains("cultural") ||
           name.contains("博物館") || name.contains("美術館") || name.contains("文化") || name.contains("藝術") {
            return .museum
        }
        
        // 娛樂場所
        if name.contains("cinema") || name.contains("theater") || name.contains("entertainment") ||
           name.contains("電影") || name.contains("戲院") || name.contains("劇院") || name.contains("娛樂") {
            return .amusementPark
        }
        
        // 觀景台和地標
        if name.contains("viewpoint") || name.contains("observation") || name.contains("peak") ||
           name.contains("觀景") || name.contains("山頂") || name.contains("天橋") || name.contains("地標") {
            return .viewpoint
        }
        
        // 歷史古蹟
        if name.contains("heritage") || name.contains("historic") || name.contains("monument") ||
           name.contains("古蹟") || name.contains("歷史") || name.contains("古建築") || name.contains("文物") {
            return .historicalSite
        }
        
        // 3. 作為fallback，使用搜索關鍵詞分類
        return getCategoryFromQuery(searchQuery)
    }
    
    /// HIG: 從搜索查詢推斷景點類別（作為fallback方法）
    private func getCategoryFromQuery(_ query: String) -> AttractionCategory {
        let lowercaseQuery = query.lowercased()
        
        // 餐飲類 (全球通用)
        if ["restaurant", "cafe", "coffee shop", "麥當勞", "肯德基", "星巴克", "必勝客", "漢堡王",
            "mcdonald's", "kfc", "starbucks", "pizza hut", "burger king", "subway",
            "餐廳", "咖啡廳", "茶餐廳", "食店", "小食店", "快餐店"].contains(lowercaseQuery) {
            return .restaurant
        }
        
        // 購物類 (全球通用)
        if ["shopping mall", "supermarket", "grocery store", "convenience store", "store", "shop", "market",
            "7-eleven", "shell", "bp", "exxon", "chevron",
            "商店", "便利店", "超市", "購物中心", "商場", "市場", "百貨公司"].contains(lowercaseQuery) {
            return .shoppingCenter
        }
        
        // 自然景觀類 (全球通用)
        if ["park", "beach", "mountain", "lake", "river", "forest", "nature reserve", "national park",
            "botanical garden", "zoo", "aquarium",
            "公園", "海灘", "山", "湖", "河", "森林", "自然保護區", "國家公園", "植物園", "動物園", "水族館"].contains(lowercaseQuery) {
            return .park
        }
        
        // 文化教育類 (全球通用)
        if ["museum", "art gallery", "cultural center", "exhibition hall", "library", "school", "university",
            "博物館", "美術館", "文化中心", "展覽館", "圖書館", "學校", "大學"].contains(lowercaseQuery) {
            return .museum
        }
        
        // 宗教類 (全球通用)
        if ["church", "cathedral", "mosque", "temple", "synagogue", "shrine", "monastery", "abbey", "chapel",
            "教堂", "清真寺", "寺廟", "廟宇", "道觀", "神社", "修道院"].contains(lowercaseQuery) {
            return .temple
        }
        
        // 娛樂類 (全球通用)
        if ["amusement park", "theme park", "entertainment center", "cinema", "theater", "concert hall",
            "opera house", "stadium", "arena", "bowling alley", "arcade",
            "遊樂園", "主題公園", "娛樂中心", "電影院", "劇院", "音樂廳", "體育場", "保齡球館"].contains(lowercaseQuery) {
            return .amusementPark
        }
        
        // 觀景地點 (全球通用)
        if ["viewpoint", "observation deck", "scenic spot", "landmark", "monument",
            "觀景台", "風景區", "地標", "名勝"].contains(lowercaseQuery) {
            return .viewpoint
        }
        
        // 旅遊景點 (全球通用)
        if ["tourist attraction", "sightseeing", "point of interest", "heritage site", "palace", "castle",
            "旅遊景點", "觀光", "景點", "宮殿", "古建築"].contains(lowercaseQuery) {
            return .historicalSite
        }
        
        // 醫療服務 (全球通用)
        if ["hospital", "clinic", "dental clinic", "pharmacy",
            "醫院", "診所", "藥房"].contains(lowercaseQuery) {
            return .other
        }
        
        // 交通及其他服務 (全球通用)
        if ["gas station", "bank", "atm", "post office", "police station", "fire station",
            "加油站", "銀行", "ATM", "郵局", "警察局", "消防局"].contains(lowercaseQuery) {
            return .other
        }
        
        // 預設分類
        return .other
    }
    
    /// 聚焦到指定景點
    func focusOnAttraction(_ attraction: NearbyAttraction) {
        let coordinate = CLLocationCoordinate2D(
            latitude: attraction.coordinate.latitude,
            longitude: attraction.coordinate.longitude
        )
        selectedAttraction = attraction
        moveToLocation(coordinate: coordinate, zoomLevel: .neighborhood)
    }
    
    // MARK: - HIG面板狀態管理方法
    
    /// 根據拖拽手勢更新面板位置（拖拽過程中只更新位置，不切換狀態）
    func updatePanelState(dragValue: DragGesture.Value, screenHeight: CGFloat) {
        let dragOffset = dragValue.translation.height
        
        // HIG: 在拖拽過程中只更新偏移量，不切換狀態
        switch attractionPanelState {
        case .compact:
            // 緊湊模式：可以向上拖拽到展開，向下拖拽到隱藏
            attractionPanelOffset = max(-200, min(100, dragOffset))
        case .expanded:
            // 展開模式：只允許向下拖拽到緊湊或隱藏
            attractionPanelOffset = max(-50, min(300, dragOffset))
        case .hidden:
            // 隱藏模式：只允許向上拖拽到緊湊
            attractionPanelOffset = max(-150, min(50, dragOffset))
        }
    }
    
    /// 完成拖拽手勢時的處理 - HIG標準Apple Maps狀態切換邏輯
    func finalizePanelState(dragValue: DragGesture.Value) {
        let dragOffset = dragValue.translation.height
        let velocity = dragValue.predictedEndTranslation.height - dragValue.translation.height
        
        var newState = attractionPanelState
        
        // HIG: Apple Maps標準狀態切換邏輯
        if abs(velocity) > 400 { // 快速手勢
            if velocity > 0 { // 快速向下拖拽
                switch attractionPanelState {
                case .expanded:
                    newState = .compact  // 展開→緊湊
                case .compact:
                    newState = .hidden   // 緊湊→隱藏
                case .hidden:
                    break
                }
            } else { // 快速向上拖拽
                switch attractionPanelState {
                case .hidden:
                    newState = .compact   // 隱藏→緊湊
                case .compact:
                    newState = .expanded  // 緊湊→展開
                case .expanded:
                    break
                }
            }
        } else { // 根據拖拽距離判斷
            switch attractionPanelState {
            case .hidden:
                if dragOffset < -50 { // 向上拖拽超過50pt
                    newState = .compact
                }
            case .compact:
                if dragOffset > 50 { // 向下拖拽超過50pt
                    newState = .hidden
                } else if dragOffset < -80 { // 向上拖拽超過80pt
                    newState = .expanded
                }
            case .expanded:
                if dragOffset > 100 { // 向下拖拽超過100pt
                    newState = .compact
                }
            }
        }
        
        // HIG: 使用平滑動畫切換狀態
        withAnimation(.easeOut(duration: 0.4)) {
            attractionPanelState = newState
            attractionPanelOffset = 0 // 重置偏移量
        }
    }
    
    /// 隱藏景點面板
    func hideAttractionPanel() {
        withAnimation(.easeOut(duration: 0.3)) {
            attractionPanelState = .hidden
            attractionPanelOffset = 0
        }
    }
    
    /// 用戶要求：每次打開apps時自動搜尋幾十米至50km範圍內50個景點（公開方法供View調用）
    func autoSearchAttractionsOnAppStart() {
        print("📱 應用啟動自動搜尋景點（全球適用）- 範圍：幾十米至50km，數量：50個，排序：由近至遠")
        
        // 用戶要求：面板始終保持縮小狀態
        print("📱 景點面板保持縮小狀態")
        
        // 檢查位置服務狀態
        if currentLocation == nil {
            print("⚠️ 沒有當前位置，啟動位置服務並延遲搜尋")
            locationService.requestLocationPermission()
            locationService.startLocationUpdates()
            
            // 延遲搜尋，等待位置更新
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if let location = self.currentLocation {
                    print("📍 位置已獲取，開始搜尋幾十米至50km範圍內景點")
                    print("📍 當前位置: \(location.coordinate.latitude), \(location.coordinate.longitude)")
                    self.searchNearbyAttractions()
                } else {
                    print("⚠️ 仍然沒有位置，稍後再試")
                    // 再次嘗試
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        if let location = self.currentLocation {
                            print("📍 延遲位置已獲取，開始搜尋景點")
                            print("📍 當前位置: \(location.coordinate.latitude), \(location.coordinate.longitude)")
                            self.searchNearbyAttractions()
                        } else {
                            print("❌ 無法獲取位置，景點搜尋暫停")
                        }
                    }
                }
            }
        } else {
            print("📍 已有位置，立即搜尋景點")
            print("📍 當前位置: \(currentLocation!.coordinate.latitude), \(currentLocation!.coordinate.longitude)")
            print("🔍 開始執行景點搜索...")
            // 立即搜尋景點
            searchNearbyAttractions()
            print("✅ 搜索方法已調用")
        }
    }
    
    /// 手動更新景點搜索（用戶點擊左下角放大鏡圖標時觸發）
    func manualRefreshAttractions() {
        print("🔄 用戶手動更新景點搜索")
        
        // 檢查冷卻期：防止過於頻繁的MKLocalSearch API調用
        let now = Date()
        if let lastRefresh = lastManualRefreshTime {
            let timeSinceLastRefresh = now.timeIntervalSince(lastRefresh)
            if timeSinceLastRefresh < manualRefreshCooldown {
                let remainingTime = Int(manualRefreshCooldown - timeSinceLastRefresh)
                print("⏰ 手動更新冷卻中，還需等待 \(remainingTime) 秒（防止API限流）")
                return
            }
        }
        
        // 檢查位置服務狀態
        guard let location = currentLocation else {
            print("⚠️ 沒有當前位置，無法手動更新景點")
            return
        }
        
        print("📍 手動更新位置: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        
        // 如果正在搜索中，提供用戶反饋但不重複搜索
        if isLoadingAttractions {
            print("⏳ 正在搜索中，忽略手動更新請求")
            return
        }
        
        // 記錄手動更新時間
        lastManualRefreshTime = now
        print("✅ 手動更新冷卻期開始，10秒後可再次使用")
        
        // 啟動倒數計時器
        startCooldownTimer()
        
        // 強制刷新景點搜索（繞過緩存）
        print("🔄 強制刷新景點搜索（繞過緩存）")
        
        // 清除當前景點數據，確保顯示載入狀態
        isLoadingAttractions = true
        isManualRefreshing = true // 標示開始手動更新
        isUsingCachedData = false
        
        // MVVM: ViewModel使用Model來處理業務邏輯（遵循現有代碼模式）
        let attractionsModel = NearbyAttractionsModel()
        attractionsModel.searchNearbyAttractions(coordinate: location.coordinate) { [weak self] processedAttractions in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                self.nearbyAttractions = processedAttractions
                self.isLoadingAttractions = false
                self.isManualRefreshing = false // 標示手動更新完成
                
                print("✅ 手動更新完成: \(processedAttractions.count) 個景點")
                
                if !processedAttractions.isEmpty {
                    // 顯示距離範圍信息
                    if let nearest = processedAttractions.first, let farthest = processedAttractions.last {
                        let nearestDistance = nearest.distanceFromUser < 1000 ? 
                            "\(Int(nearest.distanceFromUser))米" : 
                            String(format: "%.1fkm", nearest.distanceFromUser/1000)
                        let farthestDistance = farthest.distanceFromUser < 1000 ? 
                            "\(Int(farthest.distanceFromUser))米" : 
                            String(format: "%.1fkm", farthest.distanceFromUser/1000)
                        print("📏 手動更新範圍：最近\(nearestDistance) - 最遠\(farthestDistance)")
                    }
                    
                    // 確保面板是縮小狀態（只有當前不是展開狀態時才自動縮小）
                    if self.attractionPanelState != .compact && self.attractionPanelState != .expanded {
                        self.attractionPanelState = .compact
                    }
                    
                    // 標記為最新數據（非緩存）
                    self.isUsingCachedData = false
                    
                    // 保存到緩存
                    self.autoSaveAttractionsToCache()
                    
                    print("🔄 手動更新完成，面板保持縮小狀態")
                } else {
                    print("❌ 手動更新沒有找到景點")
                    // 即使沒有找到景點，也要結束手動更新狀態
                    self.isManualRefreshing = false
                }
            }
        }
    }
    
    /// HIG: 應用恢復時檢查並觸發必要的搜索（公開方法供View調用）
    func checkAttractionsOnAppResume() {
        print("📱 應用恢復檢查")
        
        // 檢查位置服務狀態
        if currentLocation == nil {
            print("⚠️ 沒有當前位置，重新啟動位置服務")
            locationService.requestLocationPermission()
            locationService.startLocationUpdates()
            return
        }
        
        checkAndTriggerAttractionsSearchIfNeeded()
    }
    
    // MARK: - MVVM & HIG 緩存持久化方法
    
    /// MVVM & HIG: 自動保存景點數據到緩存（符合Apple數據持久化規範）
    private func autoSaveAttractionsToCache() {
        // HIG: 後台靜默保存，不阻塞UI
        DispatchQueue.global(qos: .utility).async {
            self.saveAttractionsToCache()
        }
    }
    
    /// HIG: 保存景點數據到緩存（提供離線體驗）
    func saveAttractionsToCache() {
        print("🔄 === 開始保存景點數據到緩存 ===")
        
        guard !nearbyAttractions.isEmpty else {
            print("💾 跳過保存：沒有景點數據")
            return
        }
        
        guard let currentLocation = currentLocation else {
            print("💾 跳過保存：沒有當前位置")
            return
        }
        
        print("📍 保存位置: \(currentLocation.coordinate.latitude), \(currentLocation.coordinate.longitude)")
        print("🎯 保存景點數量: \(nearbyAttractions.count)")
        print("📊 使用緩存狀態: \(isUsingCachedData)")
        print("📱 當前面板狀態: \(attractionPanelState)")
        
        // 將面板狀態轉換為字符串
        let panelStateString: String
        switch attractionPanelState {
        case .hidden: panelStateString = "hidden"
        case .compact: panelStateString = "compact"
        case .expanded: panelStateString = "expanded"
        }
        
        let cache = NearbyAttractionsCache(
            attractions: nearbyAttractions,
            lastUserLocation: AttractionsCoordinate(from: currentLocation.coordinate),
            searchRadius: 50000, // 50km
            maxResults: 50,
            panelState: panelStateString
        )
        
        do {
            let data = try JSONEncoder().encode(cache)
            UserDefaults.standard.set(data, forKey: attractionsCacheKey)
            
            // HIG: 立即同步確保數據安全
            UserDefaults.standard.synchronize()
            
            print("✅ 成功保存 \(nearbyAttractions.count) 個景點到緩存")
            print("📊 緩存數據大小: \(data.count) bytes")
            print("🔑 緩存Key: \(attractionsCacheKey)")
            print("⏰ 保存時間: \(Date())")
            
            // 即時驗證緩存完整性
            self.verifyCacheIntegrity()
            
        } catch {
            print("❌ 保存緩存失敗: \(error.localizedDescription)")
            print("🔍 錯誤詳情: \(error)")
        }
        
        print("🔄 === 緩存保存完成 ===")
    }
    
    /// MVVM & HIG: 驗證緩存完整性
    private func verifyCacheIntegrity() {
        if let data = UserDefaults.standard.data(forKey: attractionsCacheKey) {
            do {
                let cache = try JSONDecoder().decode(NearbyAttractionsCache.self, from: data)
                print("✅ 緩存驗證成功: \(cache.attractions.count) 個景點")
            } catch {
                print("❌ 緩存驗證失敗: \(error)")
            }
        } else {
            print("❌ 緩存驗證失敗: 無法讀取數據")
        }
    }
    
    /// MVVM & HIG: 從緩存加載景點數據（立即響應用戶）
    func loadAttractionsFromCache() {
        print("🔄 === 開始加載緩存景點數據 ===")
        
        guard let data = UserDefaults.standard.data(forKey: attractionsCacheKey) else {
            print("💾 沒有找到緩存數據（Key: \(attractionsCacheKey)）")
            print("🔄 === 緩存加載結束（無數據）===")
            return
        }
        
        print("📊 找到緩存數據，大小: \(data.count) bytes")
        
        do {
            let cache = try JSONDecoder().decode(NearbyAttractionsCache.self, from: data)
            print("✅ 成功解碼緩存數據")
            print("📍 緩存位置: \(cache.lastUserLocation.latitude), \(cache.lastUserLocation.longitude)")
            print("⏰ 緩存時間: \(cache.lastUpdated)")
            print("🎯 景點數量: \(cache.attractions.count)")
            
            let cacheAge = Date().timeIntervalSince(cache.lastUpdated)
            print("📅 緩存年齡: \(String(format: "%.1f", cacheAge/3600)) 小時")
            
            // 檢查緩存是否過期（6小時 = 21600秒）
            if cache.isExpired(maxAge: 21600) {
                print("💾 緩存已過期，清理並跳過加載")
                clearExpiredCache()
                print("🔄 === 緩存加載結束（已過期）===")
                return
            }
            
            print("🎉 緩存數據有效，立即加載到UI")
            print("🔄 開始更新ViewModel狀態...")
            
            // MVVM: 在主線程更新UI綁定的數據
            DispatchQueue.main.async {
                // 立即加載緩存數據
                self.nearbyAttractions = cache.sortedAttractions
                self.isUsingCachedData = true
                
                print("✅ ViewModel狀態已更新")
                print("   - 景點數量: \(self.nearbyAttractions.count)")
                print("   - 使用緩存: \(self.isUsingCachedData)")
                print("💾 緩存面板狀態: \(cache.panelState)")
                
                // 用戶要求：每次打開時面板都是縮小狀態，不管緩存中保存的是什麼狀態
                if !cache.attractions.isEmpty {
                    print("🚀 確保景點面板始終為縮小狀態（用戶要求）")
                    // 始終設置為compact狀態
                    self.attractionPanelState = .compact
                    print("📱 面板狀態已設置為縮小狀態: \(self.attractionPanelState)")
                } else {
                    print("⚠️ 緩存中沒有景點數據，保持縮小狀態")
                    self.attractionPanelState = .compact
                }
            }
            
        } catch {
            print("❌ 加載緩存失敗: \(error.localizedDescription)")
            print("🔍 錯誤詳情: \(error)")
        }
        
        print("🔄 === 緩存加載完成 ===")
    }
    
    /// HIG: 清除過期緩存數據
    private func clearExpiredCache() {
        UserDefaults.standard.removeObject(forKey: attractionsCacheKey)
        print("🗑️ 已清除過期緩存")
    }
    
    /// MVVM & HIG: 調試用 - 檢查緩存狀態
    func debugCacheStatus() {
        print("🔍 === 緩存狀態調試 ===")
        print("🔑 緩存Key: \(attractionsCacheKey)")
        
        if let data = UserDefaults.standard.data(forKey: attractionsCacheKey) {
            print("📊 找到緩存數據，大小: \(data.count) bytes")
            
            do {
                let cache = try JSONDecoder().decode(NearbyAttractionsCache.self, from: data)
                print("✅ 緩存解碼成功")
                print("📍 緩存位置: \(cache.lastUserLocation.latitude), \(cache.lastUserLocation.longitude)")
                print("⏰ 緩存時間: \(cache.lastUpdated)")
                print("🎯 景點數量: \(cache.attractions.count)")
                print("📱 緩存面板狀態: \(cache.panelState)")
                print("⏳ 緩存年齡: \(Date().timeIntervalSince(cache.lastUpdated)/3600) 小時")
                print("✨ 緩存狀態: \(cache.isExpired(maxAge: 21600) ? "已過期" : "有效")")
                
                if !cache.attractions.isEmpty {
                    print("🎪 前3個景點:")
                    for (index, attraction) in cache.attractions.prefix(3).enumerated() {
                        print("   \(index + 1). \(attraction.name) - \(attraction.distanceFromUser)m")
                    }
                }
            } catch {
                print("❌ 緩存解碼失敗: \(error)")
            }
        } else {
            print("💾 沒有找到緩存數據")
        }
        
        print("🎯 當前ViewModel狀態:")
        print("   - 景點數量: \(nearbyAttractions.count)")
        print("   - 使用緩存: \(isUsingCachedData)")
        print("   - 面板狀態: \(attractionPanelState)")
        print("   - 載入中: \(isLoadingAttractions)")
        print("🔍 === 調試結束 ===")
    }
    
    // MARK: - 手動更新冷卻狀態（UI支援）
    
    /// 檢查手動更新是否可用（用於UI狀態顯示）
    var canManualRefresh: Bool {
        // 依賴 timerTrigger 來觸發UI實時更新
        _ = timerTrigger
        
        guard let lastRefresh = lastManualRefreshTime else { return true }
        let timeSinceLastRefresh = Date().timeIntervalSince(lastRefresh)
        return timeSinceLastRefresh >= manualRefreshCooldown
    }
    
    /// 獲取下次可更新的剩餘時間（用於UI顯示，秒為單位）
    var manualRefreshCooldownRemaining: Int {
        // 依賴 timerTrigger 來觸發UI實時更新
        _ = timerTrigger
        
        guard let lastRefresh = lastManualRefreshTime else { return 0 }
        let timeSinceLastRefresh = Date().timeIntervalSince(lastRefresh)
        let remaining = manualRefreshCooldown - timeSinceLastRefresh
        return max(0, Int(remaining))
    }
    
    // MARK: - 倒數計時器管理
    
    /// 啟動倒數計時器
    private func startCooldownTimer() {
        stopCooldownTimer() // 先停止現有的Timer
        
        cooldownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.timerTrigger += 1 // 觸發UI更新
                
                // 檢查是否倒數完成
                if self.canManualRefresh {
                    self.stopCooldownTimer()
                }
            }
        }
    }
    
    /// 停止倒數計時器
    private func stopCooldownTimer() {
        cooldownTimer?.invalidate()
        cooldownTimer = nil
    }
    
    @Published var selectedAttraction: NearbyAttraction? = nil // 正確放在類內部
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

// MARK: - HIG面板狀態枚舉（遵循Apple Maps設計）
enum AttractionPanelState {
    case hidden     // 完全隱藏
    case compact    // 緊湊顯示（底部小條）
    case expanded   // 展開顯示（半屏）
    
    var heightMultiplier: CGFloat {
        switch self {
        case .hidden: return 0
        case .compact: return 0.15  // 減小到15%，更像Apple Maps
        case .expanded: return 0.6  // 增加到60%，更接近Apple Maps
        }
    }
    
    var visibleHeight: CGFloat {
        switch self {
        case .hidden: return 0
        case .compact: return 80    // 固定80pt高度，像Apple Maps
        case .expanded: return UIScreen.main.bounds.height * 0.6
        }
    }
}

// 使 CLLocationCoordinate2D 符合 Equatable
extension CLLocationCoordinate2D: @retroactive Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
} 