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
    
    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var locationError: Error?
    
    override init() {
        super.init()
        setupLocationManager()
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest // 提高精度
        locationManager.distanceFilter = 5 // 減少距離過濾器，更頻繁更新
        
        // 獲取當前的授權狀態
        authorizationStatus = locationManager.authorizationStatus
        print("🎯 初始權限狀態: \(authorizationStatus.rawValue)")
        
        // 如果已經有權限，直接開始位置更新
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            startLocationUpdates()
        }
    }
    
    /// 請求位置權限
    func requestLocationPermission() {
        print("🎯 當前權限狀態: \(locationManager.authorizationStatus.rawValue)")
        
        switch locationManager.authorizationStatus {
        case .notDetermined:
            print("🎯 請求位置權限...")
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            print("🎯 位置權限被拒絕或受限")
            DispatchQueue.main.async {
                self.authorizationStatus = self.locationManager.authorizationStatus
            }
        case .authorizedWhenInUse, .authorizedAlways:
            print("🎯 位置權限已授予，開始位置更新")
            DispatchQueue.main.async {
                self.authorizationStatus = self.locationManager.authorizationStatus
            }
            
            // 在模擬器環境下直接設置固定位置
            #if targetEnvironment(simulator)
            print("🎯 模擬器環境，直接設置固定香港位置")
            DispatchQueue.main.async {
                self.currentLocation = self.fixedHongKongLocation
                self.locationError = nil
                print("🎯 已設定固定香港位置: \(self.fixedHongKongLocation.coordinate.latitude), \(self.fixedHongKongLocation.coordinate.longitude)")
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
            print("🎯 權限不足，無法開始位置更新")
            return
        }
        
        // 重置重試計數器
        retryCount = 0
        
        print("🎯 開始位置更新...")
        
        // 在模擬器環境下使用固定的香港位置
        #if targetEnvironment(simulator)
        print("🎯 模擬器環境，使用固定香港位置")
        DispatchQueue.main.async {
            self.currentLocation = self.fixedHongKongLocation
            self.locationError = nil
            print("🎯 已設定固定香港位置: \(self.fixedHongKongLocation.coordinate.latitude), \(self.fixedHongKongLocation.coordinate.longitude)")
        }
        return
        #endif
        
        // 在真實設備上才進行實際的位置更新
        locationManager.startUpdatingLocation()
        
        // 設置較長的超時機制
        locationUpdateTimer?.invalidate()
        locationUpdateTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: false) { [weak self] _ in
            print("🎯 位置更新超時，重新嘗試...")
            self?.retryLocationUpdate()
        }
    }
    
    /// 重試位置更新
    private func retryLocationUpdate() {
        print("🎯 重試位置更新")
        locationManager.stopUpdatingLocation()
        
        // 延遲2秒後重新開始
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self else { return }
            if self.authorizationStatus == .authorizedWhenInUse || self.authorizationStatus == .authorizedAlways {
                print("🎯 重新開始位置更新")
                self.locationManager.startUpdatingLocation()
                
                // 模擬器環境下，也嘗試單次請求
                #if targetEnvironment(simulator)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.locationManager.requestLocation()
                }
                #endif
            }
        }
    }
    
    /// 停止位置更新
    func stopLocationUpdates() {
        print("🎯 停止位置更新")
        locationManager.stopUpdatingLocation()
        locationUpdateTimer?.invalidate()
        locationUpdateTimer = nil
    }
    
    /// 取得當前位置的地址（地理編碼）
    func getAddressFromLocation(_ location: CLLocation, completion: @escaping (String?) -> Void) {
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            if let error = error {
                print("🎯 地理編碼錯誤: \(error.localizedDescription)")
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
                print("🎯 地理編碼成功: \(address)")
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
        print("🎯 收到位置更新: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        print("🎯 位置精度: \(location.horizontalAccuracy)m, 時間: \(location.timestamp)")
        
        // 檢查位置是否有效（精度是否足夠好）
        if location.horizontalAccuracy < 0 {
            print("🎯 位置精度無效，忽略此次更新")
            return
        }
        
        // 檢查位置是否太舊（超過5秒）
        if abs(location.timestamp.timeIntervalSinceNow) > 5.0 {
            print("🎯 位置數據太舊，忽略此次更新")
            return
        }
        
        // 清除超時計時器
        locationUpdateTimer?.invalidate()
        locationUpdateTimer = nil
        
        DispatchQueue.main.async {
            self.currentLocation = location
            self.locationError = nil
        }
        
        print("🎯 位置更新成功，已設置到 currentLocation")
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("🎯 位置更新失敗: \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.locationError = error
        }
        
        // 如果是網絡錯誤且未超過重試次數，重試
        if let clError = error as? CLError {
            switch clError.code {
            case .network, .locationUnknown:
                if retryCount < maxRetryCount {
                    retryCount += 1
                    print("🎯 網絡或位置未知錯誤，第 \(retryCount) 次重試（最多 \(maxRetryCount) 次）")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                        self?.retryLocationUpdate()
                    }
                } else {
                    print("🎯 已達到最大重試次數，停止重試")
                    DispatchQueue.main.async {
                        self.locationError = NSError(domain: "LocationService", code: -1, userInfo: [
                            NSLocalizedDescriptionKey: "無法獲取位置，請檢查網絡連接或位置設置"
                        ])
                    }
                }
            default:
                print("🎯 其他位置錯誤，不重試: \(clError.localizedDescription)")
                break
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        print("🎯 授權狀態變更: \(status.rawValue)")
        DispatchQueue.main.async {
            self.authorizationStatus = status
            
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                print("🎯 獲得位置權限，開始位置更新")
                
                // 在模擬器環境下直接設置固定位置
                #if targetEnvironment(simulator)
                print("🎯 模擬器環境，設置固定香港位置")
                self.currentLocation = self.fixedHongKongLocation
                self.locationError = nil
                print("🎯 已設定固定香港位置: \(self.fixedHongKongLocation.coordinate.latitude), \(self.fixedHongKongLocation.coordinate.longitude)")
                #else
                self.startLocationUpdates()
                #endif
            case .denied, .restricted:
                print("🎯 位置權限被拒絕，停止位置更新")
                self.stopLocationUpdates()
            case .notDetermined:
                print("🎯 位置權限未確定")
                break
            @unknown default:
                break
            }
        }
    }
} 