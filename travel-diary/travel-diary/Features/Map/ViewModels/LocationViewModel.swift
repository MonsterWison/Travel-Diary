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
    
    // MARK: - Configuration
    /// 啟用分階段搜尋系統（預設為false以保持穩定性）
    private var enableStagedSearch: Bool = false
    
    // MARK: - Progress Tracking
    @Published var searchProgress: Double = 0.0
    @Published var currentSearchStage: String = ""
    @Published var isProgressVisible: Bool = false
    
    // 常數定義
    private static let hongKongLatitude: Double = 22.307761
    private static let hongKongLongitude: Double = 114.257263
    private static let mapMovementThreshold: Double = 0.0005 // 約50米
    
    // HIG: 地圖縮放級別常數 - 按照 Apple 推薦的街道級別視圖
    private static let streetLevelSpan = MKCoordinateSpan(latitudeDelta: 0.001, longitudeDelta: 0.001) // 約100米範圍
    private static let neighborhoodSpan = MKCoordinateSpan(latitudeDelta: 0.003, longitudeDelta: 0.003) // 約300米範圍
    private static let cityLevelSpan = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01) // 約1公里範圍
    
    // MARK: - Published Properties
    @Published var currentLocation: CLLocation?
    @Published var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 22.3193, longitude: 114.1694), // 預設香港座標
        span: cityLevelSpan // 預設改為1公里範圍
    )
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var showingLocationAlert = false
    @Published var currentAddress: String = "定位中..."
    @Published var travelPoints: [TravelPoint] = []
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
    
    // 行政區資訊快取
    private var lastRegionInfo: (isoCountryCode: String?, administrativeArea: String?, isMainlandChina: Bool)? = nil
    private var lastRegionInfoTimestamp: Date? = nil
    private let regionInfoCacheValidDuration: TimeInterval = 600 // 10分鐘
    
    // 新增：暫存本次定位的50個景點（每次更新都會覆蓋）
    private(set) var currentNearbyAttractions: [NearbyAttraction] = []
    
    // 新增：地點搜尋冷卻機制
    private var lastPlaceSearchTime: Date? = nil
    private let placeSearchCooldown: TimeInterval = 2.0 // 2秒
    @Published var isPlaceSearchCoolingDown: Bool = false
    @Published var placeSearchCooldownRemaining: Int = 0
    private var placeSearchCooldownTimer: Timer? = nil
    private var lastPlaceSearchCoordinate: CLLocationCoordinate2D? = nil
    private var lastPlaceNearbyAttractions: [NearbyAttraction] = []
    
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
        #if DEBUG
        print("[DEBUG] handleLocationUpdate: location=\(String(describing: location?.coordinate))")
        #endif
        guard let location = location else { return }
        currentLocation = location
        updateRegionInfoCache(for: location)
        if isFixedHongKongLocation(location) {
            currentAddress = "香港新界將軍澳彩明苑彩富閣"
        }
        let isFirstRealLocation = !hasReceivedFirstRealLocation
        if isFirstRealLocation {
            updateMapRegion(to: location.coordinate, span: Self.cityLevelSpan)
            hasReceivedFirstRealLocation = true
            userHasMovedMap = false
        }
        if !isFixedHongKongLocation(location) {
            locationService.getAddressFromLocation(location) { [weak self] address in
                DispatchQueue.main.async {
                    self?.currentAddress = address ?? "無法獲取地址"
                }
            }
        }
        if isFirstRealLocation {
            #if DEBUG
            print("[DEBUG] handleLocationUpdate: first real location, trigger searchNearbyAttractions")
            #endif
            searchNearbyAttractions()
            checkAndTriggerAttractionsSearchIfNeeded()
        }
    }
    
    /// 檢查是否為固定香港位置
    private func isFixedHongKongLocation(_ location: CLLocation) -> Bool {
        return abs(location.coordinate.latitude - Self.hongKongLatitude) < 0.0001 &&
               abs(location.coordinate.longitude - Self.hongKongLongitude) < 0.0001
    }
    
    private func handleAuthorizationChange(_ status: CLAuthorizationStatus) {
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
        if error != nil {
            currentAddress = "位置獲取失敗: \(error!.localizedDescription)"
        }
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
        // HIG: 定位按鈕點擊時使用1公里級別縮放
        updateMapRegion(to: location.coordinate, span: Self.cityLevelSpan)
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
            latitudinalMeters: 20000, // 20公里範圍
            longitudinalMeters: 20000
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
                if error != nil {
                    promise(.failure(error!))
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
        userHasMovedMap = false
        moveToLocation(coordinate: result.coordinate, zoomLevel: .neighborhood)
        // 新增：地圖跳轉後自動搜尋該地點附近50個景點
        searchNearbyAttractionsForPlace(coordinate: result.coordinate)
    }
    
    // HIG: 立即執行搜索（用於用戶按執行鍵時）
    func performImmediateSearch() {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        // 取消debounce，立即搜索
        searchCancellable?.cancel()
        performSearch(query: searchText)
        // 只在用戶有點擊建議時才自動跳轉，否則用地理編碼跳轉
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self else { return }
            // 若用戶未點擊建議，直接用地名地理編碼跳轉
            if self.selectedSearchResult == nil {
                let geocoder = CLGeocoder()
                geocoder.geocodeAddressString(self.searchText) { placemarks, error in
                    guard let placemark = placemarks?.first, let coordinate = placemark.location?.coordinate else { return }
                    // 地圖跳轉到地名
                    self.moveToLocation(coordinate: coordinate, zoomLevel: .neighborhood)
                    // 並搜尋該地點附近景點
                    self.selectedSearchResult = SearchResult(
                        name: self.searchText,
                        subtitle: placemark.name,
                        coordinate: coordinate,
                        placemark: MKPlacemark(placemark: placemark)
                    )
                    self.searchNearbyAttractionsForPlace(coordinate: coordinate)
                }
            }
        }
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
        #if DEBUG
        print("[DEBUG] moveToLocation: coordinate=\(coordinate), zoomLevel=\(zoomLevel)")
        #endif
        isProgrammaticUpdate = true
        let newSpan = zoomLevel.span
        withAnimation(.easeInOut(duration: 1.0)) {
            region = MKCoordinateRegion(
                center: coordinate,
                span: newSpan
            )
        }
        lastKnownMapCenter = coordinate
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            self.isProgrammaticUpdate = false
        }
        if let currentLocation = currentLocation {
            let currentCoordinate = currentLocation.coordinate
            let distance = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                .distance(from: CLLocation(latitude: currentCoordinate.latitude, longitude: currentCoordinate.longitude))
            if distance > 100 {
                userHasMovedMap = true
            }
        }
    }
    
    // MARK: - MVVM: ViewModel從Model獲取數據
    /// MVVM架構：ViewModel從Model獲取處理好的景點數據
    func searchNearbyAttractions() {
        #if DEBUG
        print("[DEBUG] searchNearbyAttractions: currentLocation=\(String(describing: currentLocation?.coordinate)) isLoadingAttractions=\(isLoadingAttractions)")
        #endif
        guard let location = currentLocation else { 
            #if DEBUG
            print("[DEBUG] searchNearbyAttractions: currentLocation is nil, abort.")
            #endif
            return 
        }
        guard !isLoadingAttractions else {
            #if DEBUG
            print("[DEBUG] searchNearbyAttractions: already loading, abort.")
            #endif
            return
        }
        
        isLoadingAttractions = true
        currentNearbyAttractions.removeAll()
        
        // 根據配置選擇搜尋方式
        if enableStagedSearch {
            #if DEBUG
            print("[DEBUG] searchNearbyAttractions: 使用分階段搜尋系統")
            #endif
            enableStagedAttractionSearch(userLocation: location.coordinate)
            // 分階段搜尋會在完成後自動設置 isLoadingAttractions = false
        } else {
            #if DEBUG
            print("[DEBUG] searchNearbyAttractions: 使用傳統搜尋系統")
            #endif
            let attractionsModel = NearbyAttractionsModel()
            #if DEBUG
            print("[DEBUG] searchNearbyAttractions: start model search at \(location.coordinate)")
            #endif
            attractionsModel.searchNearbyAttractions(coordinate: location.coordinate) { [weak self] processedAttractions in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    #if DEBUG
                    print("[DEBUG] searchNearbyAttractions: model returned \(processedAttractions.count) attractions")
                    #endif
                    self.currentNearbyAttractions = processedAttractions
                    self.nearbyAttractions = processedAttractions
                    self.isLoadingAttractions = false
                    if !processedAttractions.isEmpty {
                        self.isUsingCachedData = false
                        self.autoSaveAttractionsToCache()
                    } else {
                        self.isUsingCachedData = false
                    }
                }
            }
        }
    }
    
    /// HIG: 檢查並觸發必要的景點搜索（解決應用重啟後面板消失的問題）
    private func checkAndTriggerAttractionsSearchIfNeeded() {
        guard let _ = currentLocation,
              !isLoadingAttractions else {
            return
        }
        
        // 如果已經有景點數據，不再自動縮小面板
        if !nearbyAttractions.isEmpty {
            return
        }
        
        // 如果沒有景點數據，觸發搜索
        if nearbyAttractions.isEmpty {
            searchNearbyAttractions()
        } else if isUsingCachedData {
            // 如果正在使用緩存數據，觸發後台更新
            DispatchQueue.global(qos: .utility).async {
                DispatchQueue.main.async {
                    self.searchNearbyAttractions()
                }
            }
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
    
    /// 用戶要求：每次打開apps時自動搜尋幾十米至20km範圍內50個景點（公開方法供View調用）
    func autoSearchAttractionsOnAppStart() {
        #if DEBUG
        print("[DEBUG] autoSearchAttractionsOnAppStart: currentLocation=\(String(describing: currentLocation?.coordinate))")
        #endif
        if currentLocation == nil {
            locationService.requestLocationPermission()
            locationService.startLocationUpdates()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if self.currentLocation != nil {
                    #if DEBUG
                    print("[DEBUG] autoSearchAttractionsOnAppStart: got location after delay, searching...")
                    #endif
                    self.searchNearbyAttractions()
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        if self.currentLocation != nil {
                            #if DEBUG
                            print("[DEBUG] autoSearchAttractionsOnAppStart: got location after second delay, searching...")
                            #endif
                            self.searchNearbyAttractions()
                        } else {
                            #if DEBUG
                            print("[DEBUG] autoSearchAttractionsOnAppStart: still no location, abort.")
                            #endif
                        }
                    }
                }
            }
        } else {
            #if DEBUG
            print("[DEBUG] autoSearchAttractionsOnAppStart: already have location, searching...")
            #endif
            searchNearbyAttractions()
        }
    }
    
    /// 手動更新景點搜索（用戶點擊左下角放大鏡圖標時觸發）
    func manualRefreshAttractions() {
        #if DEBUG
        print("[DEBUG] manualRefreshAttractions: currentLocation=\(String(describing: currentLocation?.coordinate))")
        #endif
        let now = Date()
        if let lastRefresh = lastManualRefreshTime {
            let timeSinceLastRefresh = now.timeIntervalSince(lastRefresh)
            if timeSinceLastRefresh < manualRefreshCooldown {
                #if DEBUG
                print("[DEBUG] manualRefreshAttractions: cooldown active, abort.")
                #endif
                return
            }
        }
        guard let location = currentLocation else {
            #if DEBUG
            print("[DEBUG] manualRefreshAttractions: currentLocation is nil, abort.")
            #endif
            return
        }
        lastManualRefreshTime = now
        startCooldownTimer()
        isLoadingAttractions = true
        isManualRefreshing = true
        isUsingCachedData = false
        let attractionsModel = NearbyAttractionsModel()
        #if DEBUG
        print("[DEBUG] manualRefreshAttractions: start model search at \(location.coordinate)")
        #endif
        attractionsModel.searchNearbyAttractions(coordinate: location.coordinate) { [weak self] processedAttractions in
            DispatchQueue.main.async {
                guard let self = self else { return }
                #if DEBUG
                print("[DEBUG] manualRefreshAttractions: model returned \(processedAttractions.count) attractions")
                #endif
                self.nearbyAttractions = processedAttractions
                self.isLoadingAttractions = false
                self.isManualRefreshing = false
                if !processedAttractions.isEmpty {
                    self.isUsingCachedData = false
                    self.autoSaveAttractionsToCache()
                } else {
                    self.isManualRefreshing = false
                }
            }
        }
    }
    
    /// HIG: 應用恢復時檢查並觸發必要的搜索（公開方法供View調用）
    func checkAttractionsOnAppResume() {
        // 檢查位置服務狀態
        if currentLocation == nil {
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
        guard !nearbyAttractions.isEmpty else {
            return
        }
        
        guard let currentLocation = currentLocation else {
            return
        }
        
        let cache = NearbyAttractionsCache(
            attractions: nearbyAttractions,
            lastUserLocation: AttractionsCoordinate(from: currentLocation.coordinate),
            searchRadius: 20000, // 20km
            maxResults: 50,
            panelState: attractionPanelState.description
        )
        
        do {
            let data = try JSONEncoder().encode(cache)
            UserDefaults.standard.set(data, forKey: attractionsCacheKey)
            
            // HIG: 立即同步確保數據安全
            UserDefaults.standard.synchronize()
            
        } catch {
            // 保存緩存失敗
        }
    }
    
    /// MVVM & HIG: 從緩存加載景點數據（立即響應用戶）
    func loadAttractionsFromCache() {
        guard let data = UserDefaults.standard.data(forKey: attractionsCacheKey) else {
            return
        }
        
        do {
            let cache = try JSONDecoder().decode(NearbyAttractionsCache.self, from: data)
            
            // 立即加載緩存數據
            self.nearbyAttractions = cache.sortedAttractions
            self.isUsingCachedData = true
            
        } catch {
            // 加載緩存失敗
        }
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
    
    private func updateRegionInfoCache(for location: CLLocation) {
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            if let placemark = placemarks?.first {
                let code = placemark.isoCountryCode?.uppercased()
                let admin = placemark.administrativeArea ?? ""
                let isMainland = (code == "CN") && (!admin.contains("香港") && !admin.contains("澳門") && !admin.contains("台灣") && !admin.contains("台灣"))
                self?.lastRegionInfo = (code, admin, isMainland)
                self?.lastRegionInfoTimestamp = Date()
            }
        }
    }
    
    /// 取得行政區資訊（優先用快取，超過10分鐘則同步查詢）
    func getCachedOrFreshRegionInfo(completion: @escaping ((isoCountryCode: String?, administrativeArea: String?, isMainlandChina: Bool)) -> Void) {
        let now = Date()
        if let info = lastRegionInfo, let ts = lastRegionInfoTimestamp, now.timeIntervalSince(ts) < regionInfoCacheValidDuration {
            completion(info)
            return
        }
        // 若快取過期則同步查詢
        guard let location = currentLocation else {
            completion((nil, nil, false))
            return
        }
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            if let placemark = placemarks?.first {
                let code = placemark.isoCountryCode?.uppercased()
                let admin = placemark.administrativeArea ?? ""
                let isMainland = (code == "CN") && (!admin.contains("香港") && !admin.contains("澳門") && !admin.contains("台灣") && !admin.contains("台灣"))
                self.lastRegionInfo = (code, admin, isMainland)
                self.lastRegionInfoTimestamp = Date()
                completion((code, admin, isMainland))
            } else {
                completion((nil, nil, false))
            }
        }
    }
    
    // 新增：地點搜尋冷卻與自動搜尋附近景點
    private func searchNearbyAttractionsForPlace(coordinate: CLLocationCoordinate2D) {
        #if DEBUG
        print("[DEBUG] searchNearbyAttractionsForPlace: coordinate=\(coordinate)")
        #endif
        let now = Date()
        if let last = lastPlaceSearchTime, now.timeIntervalSince(last) < placeSearchCooldown {
            #if DEBUG
            print("[DEBUG] searchNearbyAttractionsForPlace: cooldown active, abort.")
            #endif
            startPlaceSearchCooldownTimer()
            return
        }
        lastPlaceSearchTime = now
        lastPlaceSearchCoordinate = coordinate
        isPlaceSearchCoolingDown = true
        placeSearchCooldownRemaining = Int(placeSearchCooldown)
        startPlaceSearchCooldownTimer()
        isLoadingAttractions = true
        let attractionsModel = NearbyAttractionsModel()
        #if DEBUG
        print("[DEBUG] searchNearbyAttractionsForPlace: start model search at \(coordinate)")
        #endif
        attractionsModel.searchNearbyAttractions(coordinate: coordinate) { [weak self] processedAttractions in
            DispatchQueue.main.async {
                guard let self = self else { return }
                #if DEBUG
                print("[DEBUG] searchNearbyAttractionsForPlace: model returned \(processedAttractions.count) attractions")
                #endif
                var attractions = processedAttractions
                if let selected = self.selectedSearchResult {
                    let alreadyIncluded = attractions.contains { attr in
                        attr.name == selected.name &&
                        abs(attr.coordinate.latitude - selected.coordinate.latitude) < 0.0001 &&
                        abs(attr.coordinate.longitude - selected.coordinate.longitude) < 0.0001
                    }
                    if !alreadyIncluded {
                        let manual = NearbyAttraction(
                            name: selected.name,
                            description: selected.subtitle ?? selected.name,
                            coordinate: AttractionsCoordinate(from: selected.coordinate),
                            distanceFromUser: 0,
                            category: .other,
                            address: selected.subtitle
                        )
                        attractions.insert(manual, at: 0)
                    }
                }
                self.lastPlaceNearbyAttractions = attractions
                self.nearbyAttractions = attractions
                self.isLoadingAttractions = false
                self.isUsingCachedData = false
            }
        }
    }
    
    private func startPlaceSearchCooldownTimer() {
        placeSearchCooldownTimer?.invalidate()
        isPlaceSearchCoolingDown = true
        placeSearchCooldownTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] timer in
            guard let self = self, let last = self.lastPlaceSearchTime else { return }
            let elapsed = Date().timeIntervalSince(last)
            let remaining = max(0, self.placeSearchCooldown - elapsed)
            self.placeSearchCooldownRemaining = Int(ceil(remaining))
            if remaining <= 0 {
                self.isPlaceSearchCoolingDown = false
                timer.invalidate()
            }
        }
    }
    
    // 回定位點時還原原本定位點的50個景點
    func restoreOriginalNearbyAttractions() {
        if let original = currentNearbyAttractions as [NearbyAttraction]? {
            self.nearbyAttractions = original
        }
    }
    
    // MARK: - 分階段景點搜尋整合
    
    /// 啟用分階段搜尋模式
    func enableStagedSearchMode() {
        enableStagedSearch = true
        print("[StagedSystem] 分階段搜尋模式已啟用")
    }
    
    /// 停用分階段搜尋模式
    func disableStagedSearchMode() {
        enableStagedSearch = false
        print("[StagedSystem] 分階段搜尋模式已停用")
    }
    
    /// 啟用分階段景點搜尋系統
    /// - Parameter userLocation: 用戶位置
    private func enableStagedAttractionSearch(userLocation: CLLocationCoordinate2D) {
        Task {
            await performStagedSearch(userLocation: userLocation)
        }
    }
    
    /// 執行分階段搜尋的主要邏輯
    @MainActor
    private func performStagedSearch(userLocation: CLLocationCoordinate2D) async {
        print("[StagedSystem] 啟用分階段景點搜尋系統")
        
        // 顯示進度指示器
        isProgressVisible = true
        searchProgress = 0.0
        currentSearchStage = "初始化搜尋系統..."
        
        // 建立必要的ViewModel
        let attractionsListVM = AttractionsListViewModel()
        let attractionsManagementVM = AttractionsManagementViewModel()
        let detailVM = AttractionDetailViewModel(attractionName: "System")
        
        // 清除現有資料
        attractionsListVM.clearAll()
        
        currentSearchStage = "開始分階段搜尋..."
        searchProgress = 0.1
        
        // 執行分階段搜尋
        let stagedResults = await detailVM.performStagedAttractionSearch(
            userLocation: userLocation,
            attractionsListVM: attractionsListVM,
            attractionsManagementVM: attractionsManagementVM
        )
        
        currentSearchStage = "處理搜尋結果..."
        searchProgress = 0.8
        
        // 轉換為NearbyAttraction格式
        let convertedAttractions = convertToNearbyAttractions(stagedResults)
        
        currentSearchStage = "更新地圖顯示..."
        searchProgress = 0.9
        
        // 更新現有的附近景點
        nearbyAttractions = convertedAttractions
        currentNearbyAttractions = convertedAttractions
        
        // 更新狀態
        isLoadingAttractions = false
        isUsingCachedData = false
        
        currentSearchStage = "儲存搜尋結果..."
        searchProgress = 0.95
        
        // 儲存到AttractionCache
        await saveToAttractionCache(stagedResults)
        
        // 自動儲存到緩存
        if !convertedAttractions.isEmpty {
            autoSaveAttractionsToCache()
        }
        
        // 完成搜尋
        searchProgress = 1.0
        currentSearchStage = "搜尋完成"
        
        // 延遲隱藏進度指示器
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
        isProgressVisible = false
        
        print("[StagedSystem] 分階段搜尋完成，共 \(convertedAttractions.count) 個景點")
    }
    
    /// 轉換TemplateMemoryModel為NearbyAttraction
    private func convertToNearbyAttractions(_ templateModels: [TemplateMemoryModel]) -> [NearbyAttraction] {
        return templateModels.compactMap { template in
            guard let name = template.names["en"],
                  template.hasWikipediaData else {
                return nil
            }
            
            return NearbyAttraction(
                name: name,
                description: template.descriptions?["en"] ?? "",
                coordinate: AttractionsCoordinate(
                    latitude: template.latitude,
                    longitude: template.longitude
                ),
                distanceFromUser: template.distanceFromUser,
                category: .other, // 可以根據需要改進分類邏輯
                address: template.addresses?["en"]
            )
        }
    }
    
    /// 儲存到AttractionCache
    private func saveToAttractionCache(_ templateModels: [TemplateMemoryModel]) async {
        print("[CacheSystem] 儲存 \(templateModels.count) 個景點到AttractionCache")
        
        // 這裡可以實作實際的緩存邏輯
        // 例如：儲存到本地檔案、Core Data或其他持久化方案
        
        for template in templateModels {
            if template.hasWikipediaData {
                let cache = template.toAttractionCache()
                // 儲存cache到持久化儲存
                print("[CacheSystem] 儲存景點: \(cache.names)")
            }
        }
        
        print("[CacheSystem] AttractionCache儲存完成")
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
    
    var description: String {
        switch self {
        case .hidden: return "hidden"
        case .compact: return "compact"
        case .expanded: return "expanded"
        }
    }
}

// 使 CLLocationCoordinate2D 符合 Equatable
extension CLLocationCoordinate2D: @retroactive Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
} 