import Foundation
import CoreLocation
import Combine
import MapKit
import SwiftUI

/// 位置ViewModel - 處理地圖相關的業務邏輯
class LocationViewModel: ObservableObject {
    private let locationService = LocationService()
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Published Properties
    @Published var currentLocation: CLLocation?
    @Published var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 22.3193, longitude: 114.1694), // 預設香港座標
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var showingLocationAlert = false
    @Published var currentAddress: String = "定位中..."
    @Published var travelPoints: [TravelPoint] = []
    @Published var debugInfo: String = "初始化中..."
    @Published var locationError: Error?
    @Published var isTrackingUser: Bool = false // 是否跟隨用戶位置
    
    // 私有屬性 - 追蹤是否已經獲取過真實位置
    private var hasReceivedFirstRealLocation = false
    // 追蹤用戶是否手動移動了地圖
    @Published var userHasMovedMap: Bool = false
    // 追蹤是否正在程序化更新地圖（防止觸發用戶移動標記）
    private var isProgrammaticUpdate: Bool = false
    // 追蹤上一次的地圖中心位置
    private var lastKnownMapCenter: CLLocationCoordinate2D?
    
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
        updateDebugInfo()
        
        // 延遲請求權限，確保 UI 已經準備好
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.requestLocationPermission()
        }
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
    }
    
    private func handleLocationUpdate(_ location: CLLocation?) {
        guard let location = location else { return }
        
        currentLocation = location
        updateDebugInfo()
        
        // 檢查是否為固定的香港位置
        if abs(location.coordinate.latitude - 22.307761) < 0.0001 && 
           abs(location.coordinate.longitude - 114.257263) < 0.0001 {
            print("🎯 收到固定香港位置")
            currentAddress = "香港新界將軍澳彩明苑彩富閣"
        }
        
        // 改進的地圖跟隨邏輯
        let isFirstRealLocation = !hasReceivedFirstRealLocation
        let shouldAutoFollow = !userHasMovedMap || isFirstRealLocation
        
        if shouldAutoFollow {
            print("🎯 自動跟隨位置更新: isFirst=\(isFirstRealLocation), userMoved=\(userHasMovedMap)")
            updateMapRegion(to: location.coordinate)
            
            // 重置用戶移動標記，開始新的自動跟隨
            if userHasMovedMap {
                userHasMovedMap = false
                print("🎯 重置用戶移動標記，恢復自動跟隨")
            }
            
            // 標記已經獲取過真實位置
            if isFirstRealLocation {
                hasReceivedFirstRealLocation = true
                print("🎯 首次真實位置獲取完成，已自動跟隨")
            }
        } else {
            print("🎯 用戶已手動移動地圖，跳過自動跟隨")
        }
        
        // 獲取地址信息（只有在非固定位置時才進行地理編碼）
        if !(abs(location.coordinate.latitude - 22.307761) < 0.0001 && 
             abs(location.coordinate.longitude - 114.257263) < 0.0001) {
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
            print("🎯 ViewModel 收到位置錯誤: \(error.localizedDescription)")
            currentAddress = "位置獲取失敗: \(error.localizedDescription)"
        }
        updateDebugInfo()
    }
    
    private func updateMapRegion(to coordinate: CLLocationCoordinate2D) {
        isProgrammaticUpdate = true
        withAnimation(.easeInOut(duration: 1.0)) {
            region = MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
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
            print("🎯 跳過程序化地圖更新")
            return 
        }
        
        // 檢查地圖中心是否有顯著變化
        let currentMapCenter = region.center
        
        if let lastCenter = lastKnownMapCenter {
            let latDiff = abs(currentMapCenter.latitude - lastCenter.latitude)
            let lonDiff = abs(currentMapCenter.longitude - lastCenter.longitude)
            
            // 如果變化超過閾值（約50米），認為是用戶手動移動
            let movementThreshold = 0.0005
            
            if latDiff > movementThreshold || lonDiff > movementThreshold {
                if !userHasMovedMap {
                    userHasMovedMap = true
                    print("🎯 檢測到用戶手動移動地圖，停止自動跟隨")
                    print("🎯 變化: lat=\(latDiff), lon=\(lonDiff)")
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
        print("🎯 重新請求位置權限，重置首次位置標記")
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
        print("🎯 定位按鈕被點擊")
        
        guard let location = currentLocation else {
            print("🎯 沒有當前位置，重新請求位置權限")
            requestLocationPermission()
            return
        }
        
        print("🎯 有當前位置，更新地圖區域到: \(location.coordinate)")
        
        // 重置用戶移動標記，恢復自動跟隨
        userHasMovedMap = false
        print("🎯 重置用戶移動標記，恢復自動跟隨")
        
        updateMapRegion(to: location.coordinate)
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