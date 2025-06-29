import Foundation
import CoreLocation
import Combine

/// 位置服務 - 負責處理所有位置相關的核心功能
class LocationService: NSObject, ObservableObject {
    private let locationManager = CLLocationManager()
    private var locationUpdateTimer: Timer?
    private var retryCount = 0
    private let maxRetryCount = 3
    
    // 固定的香港位置（新界將軍澳彩明苑）
    private let fixedHongKongLocation = CLLocation(
        latitude: 22.307761,
        longitude: 114.257263
    )
    
    // HIG: 位置緩存機制
    private var lastKnownLocation: CLLocation?
    private var lastLocationTimestamp: Date?
    private let locationCacheValidDuration: TimeInterval = 300 // 5分鐘緩存
    
    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var locationError: Error?
    
    override init() {
        super.init()
        setupLocationManager()
        loadCachedLocation()
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        // HIG: 使用平衡的精度設置，而不是最高精度
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters // 10米精度，更快
        locationManager.distanceFilter = 10 // 10米移動才更新
        
        // 獲取當前的授權狀態
        authorizationStatus = locationManager.authorizationStatus
        #if DEBUG
        print("🎯 初始權限狀態: \(authorizationStatus.rawValue)")
        #endif
        
        // 如果已經有權限，直接開始位置更新
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            startLocationUpdates()
        }
    }
    
    /// HIG: 載入緩存的位置
    private func loadCachedLocation() {
        if let cachedLocation = lastKnownLocation,
           let timestamp = lastLocationTimestamp,
           Date().timeIntervalSince(timestamp) < locationCacheValidDuration {
            #if DEBUG
            print("🎯 使用緩存位置，避免重複請求")
            #endif
            DispatchQueue.main.async {
                self.currentLocation = cachedLocation
            }
        }
    }
    
    /// HIG: 緩存位置
    private func cacheLocation(_ location: CLLocation) {
        lastKnownLocation = location
        lastLocationTimestamp = Date()
        // 可以擴展為持久化存儲
    }
    
    /// 請求位置權限
    func requestLocationPermission() {
        #if DEBUG
        print("🎯 當前權限狀態: \(locationManager.authorizationStatus.rawValue)")
        #endif
        
        switch locationManager.authorizationStatus {
        case .notDetermined:
            #if DEBUG
            print("🎯 請求位置權限...")
            #endif
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            #if DEBUG
            print("🎯 位置權限被拒絕或受限")
            #endif
            DispatchQueue.main.async {
                self.authorizationStatus = self.locationManager.authorizationStatus
            }
        case .authorizedWhenInUse, .authorizedAlways:
            #if DEBUG
            print("🎯 位置權限已授予，開始位置更新")
            #endif
            DispatchQueue.main.async {
                self.authorizationStatus = self.locationManager.authorizationStatus
            }
            
            // 在模擬器環境下直接設置固定位置
            #if targetEnvironment(simulator)
            #if DEBUG
            print("🎯 模擬器環境，直接設置固定香港位置")
            #endif
            DispatchQueue.main.async {
                self.currentLocation = self.fixedHongKongLocation
                self.locationError = nil
                #if DEBUG
                print("🎯 已設定固定香港位置: \(self.fixedHongKongLocation.coordinate.latitude), \(self.fixedHongKongLocation.coordinate.longitude)")
                #endif
            }
            #else
            startLocationUpdates()
            #endif
        @unknown default:
            break
        }
    }
    
    /// 開始位置更新
    func startLocationUpdates() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            #if DEBUG
            print("🎯 權限不足，無法開始位置更新")
            #endif
            return
        }
        
        // 重置重試計數器
        retryCount = 0
        
        #if DEBUG
        print("🎯 開始位置更新...")
        #endif
        
        // 在模擬器環境下使用固定的香港位置
        #if targetEnvironment(simulator)
        #if DEBUG
        print("🎯 模擬器環境，使用固定香港位置")
        #endif
        DispatchQueue.main.async {
            self.currentLocation = self.fixedHongKongLocation
            self.locationError = nil
            self.cacheLocation(self.fixedHongKongLocation)
            #if DEBUG
            print("🎯 已設定固定香港位置: \(self.fixedHongKongLocation.coordinate.latitude), \(self.fixedHongKongLocation.coordinate.longitude)")
            #endif
        }
        return
        #endif
        
        // HIG: 先嘗試快速單次位置請求
        locationManager.requestLocation()
        
        // 然後開始持續位置更新
        locationManager.startUpdatingLocation()
        
        // HIG: 縮短超時時間到8秒，提供更快的用戶反饋
        locationUpdateTimer?.invalidate()
        locationUpdateTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: false) { [weak self] _ in
            #if DEBUG
            print("🎯 位置更新超時，重新嘗試...")
            #endif
            self?.retryLocationUpdate()
        }
    }
    
    /// 重試位置更新
    private func retryLocationUpdate() {
        #if DEBUG
        print("🎯 重試位置更新")
        #endif
        locationManager.stopUpdatingLocation()
        
        // HIG: 縮短延遲時間到1秒
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            if self.authorizationStatus == .authorizedWhenInUse || self.authorizationStatus == .authorizedAlways {
                #if DEBUG
                print("🎯 重新開始位置更新")
                #endif
                
                // HIG: 重試時使用更低精度以獲得更快響應
                self.locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
                self.locationManager.startUpdatingLocation()
                
                // 模擬器環境下，也嘗試單次請求
                #if targetEnvironment(simulator)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.locationManager.requestLocation()
                }
                #endif
            }
        }
    }
    
    /// 停止位置更新
    func stopLocationUpdates() {
        #if DEBUG
        print("🎯 停止位置更新")
        #endif
        locationManager.stopUpdatingLocation()
        locationUpdateTimer?.invalidate()
        locationUpdateTimer = nil
    }
    
    /// 取得當前位置的地址（地理編碼）
    func getAddressFromLocation(_ location: CLLocation, completion: @escaping (String?) -> Void) {
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            if let error = error {
                #if DEBUG
                print("🎯 地理編碼錯誤: \(error.localizedDescription)")
                #endif
                completion(nil)
                return
            }
            
            if let placemark = placemarks?.first {
                let address = [
                    placemark.name,
                    placemark.locality,
                    placemark.administrativeArea,
                    placemark.country
                ].compactMap { $0 }.joined(separator: ", ")
                #if DEBUG
                print("🎯 地理編碼成功: \(address)")
                #endif
                completion(address)
            } else {
                completion(nil)
            }
        }
    }
}

// MARK: - CLLocationManagerDelegate
extension LocationService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        #if DEBUG
        print("🎯 收到位置更新: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        print("🎯 位置精度: \(location.horizontalAccuracy)m, 時間: \(location.timestamp)")
        #endif
        
        // 檢查位置是否有效（精度是否足夠好）
        if location.horizontalAccuracy < 0 {
            #if DEBUG
            print("🎯 位置精度無效，忽略此次更新")
            #endif
            return
        }
        
        // HIG: 放寬時間檢查，允許稍舊的位置數據
        if abs(location.timestamp.timeIntervalSinceNow) > 30.0 {
            #if DEBUG
            print("🎯 位置數據太舊，忽略此次更新")
            #endif
            return
        }
        
        // 清除超時計時器
        locationUpdateTimer?.invalidate()
        locationUpdateTimer = nil
        
        // HIG: 緩存位置以供下次快速啟動使用
        cacheLocation(location)
        
        DispatchQueue.main.async {
            self.currentLocation = location
            self.locationError = nil
        }
        
        #if DEBUG
        print("🎯 位置更新成功，已設置到 currentLocation 並緩存")
        #endif
        
        // HIG: 獲得第一個位置後，切換到更高精度但減少頻率的更新
        if retryCount == 0 {
            locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            locationManager.distanceFilter = 20 // 20米才更新，減少頻繁更新
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        #if DEBUG
        print("🎯 位置更新失敗: \(error.localizedDescription)")
        #endif
        DispatchQueue.main.async {
            self.locationError = error
        }
        
        // 如果是網絡錯誤且未超過重試次數，重試
        if let clError = error as? CLError {
            switch clError.code {
            case .network, .locationUnknown:
                if retryCount < maxRetryCount {
                    retryCount += 1
                    #if DEBUG
                    print("🎯 網絡或位置未知錯誤，第 \(retryCount) 次重試（最多 \(maxRetryCount) 次）")
                    #endif
                    // HIG: 縮短重試延遲
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                        self?.retryLocationUpdate()
                    }
                } else {
                    #if DEBUG
                    print("🎯 已達到最大重試次數，停止重試")
                    #endif
                    // HIG: 如果有緩存位置，使用緩存位置作為備用
                    if let cachedLocation = lastKnownLocation {
                        DispatchQueue.main.async {
                            self.currentLocation = cachedLocation
                            self.locationError = nil
                            #if DEBUG
                            print("🎯 使用緩存位置作為備用")
                            #endif
                        }
                    } else {
                        DispatchQueue.main.async {
                            self.locationError = NSError(domain: "LocationService", code: -1, userInfo: [
                                NSLocalizedDescriptionKey: "無法獲取位置，請檢查網絡連接或位置設置"
                            ])
                        }
                    }
                }
            default:
                #if DEBUG
                print("🎯 其他位置錯誤，不重試: \(clError.localizedDescription)")
                #endif
                // HIG: 其他錯誤時也嘗試使用緩存位置
                if let cachedLocation = lastKnownLocation {
                    DispatchQueue.main.async {
                        self.currentLocation = cachedLocation
                        self.locationError = nil
                        #if DEBUG
                        print("🎯 使用緩存位置作為備用")
                        #endif
                    }
                }
                break
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        #if DEBUG
        print("🎯 授權狀態變更: \(status.rawValue)")
        #endif
        DispatchQueue.main.async {
            self.authorizationStatus = status
            
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                #if DEBUG
                print("🎯 獲得位置權限，開始位置更新")
                #endif
                
                // 在模擬器環境下直接設置固定位置
                #if targetEnvironment(simulator)
                #if DEBUG
                print("🎯 模擬器環境，設置固定香港位置")
                #endif
                self.currentLocation = self.fixedHongKongLocation
                self.locationError = nil
                self.cacheLocation(self.fixedHongKongLocation)
                #if DEBUG
                print("🎯 已設定固定香港位置: \(self.fixedHongKongLocation.coordinate.latitude), \(self.fixedHongKongLocation.coordinate.longitude)")
                #endif
                #else
                self.startLocationUpdates()
                #endif
            case .denied, .restricted:
                #if DEBUG
                print("🎯 位置權限被拒絕，停止位置更新")
                #endif
                self.stopLocationUpdates()
            case .notDetermined:
                #if DEBUG
                print("🎯 位置權限未確定")
                #endif
                break
            @unknown default:
                break
            }
        }
    }
} 