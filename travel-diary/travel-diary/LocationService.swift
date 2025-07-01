import Foundation
import CoreLocation
import Combine

/// GPS信號強度狀態
enum GPSSignalStrength {
    case excellent      // ≤ 5米
    case good          // ≤ 20米
    case fair          // ≤ 50米
    case poor          // ≤ 100米
    case veryPoor      // > 100米
    case invalid       // < 0米（無效）
    
    var description: String {
        switch self {
        case .excellent:
            return "GPS信號優秀"
        case .good:
            return "GPS信號良好"
        case .fair:
            return "GPS信號普通"
        case .poor:
            return "GPS信號較弱"
        case .veryPoor:
            return "GPS信號很弱"
        case .invalid:
            return "GPS信號無效"
        }
    }
    
    var shouldShowWarning: Bool {
        switch self {
        case .poor, .veryPoor, .invalid:
            return true
        default:
            return false
        }
    }
}

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
    @Published var gpsSignalStrength: GPSSignalStrength = .invalid
    
    // HIG: 方向指示功能 - 符合Apple Maps標準
    @Published var currentHeading: CLHeading?
    @Published var headingAccuracy: CLLocationDegrees = -1
    @Published var headingError: Error?
    
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
        
        // HIG: 方向指示器配置 - 符合Apple Maps標準
        if CLLocationManager.headingAvailable() {
            locationManager.headingFilter = 5.0 // 5度變化才更新，避免過於頻繁
            locationManager.headingOrientation = .portrait // 支持設備方向
        }
        
        // 獲取當前的授權狀態
        authorizationStatus = locationManager.authorizationStatus
        
        // 如果已經有權限，直接開始位置更新
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            startLocationUpdates()
            startHeadingUpdates()
        }
    }
    
    /// HIG: 載入緩存的位置
    private func loadCachedLocation() {
        if let cachedLocation = lastKnownLocation,
           let timestamp = lastLocationTimestamp,
           Date().timeIntervalSince(timestamp) < locationCacheValidDuration {
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
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            DispatchQueue.main.async {
                self.authorizationStatus = self.locationManager.authorizationStatus
            }
        case .authorizedWhenInUse, .authorizedAlways:
            DispatchQueue.main.async {
                self.authorizationStatus = self.locationManager.authorizationStatus
            }
            
            // 在模擬器環境下直接設置固定位置
            #if targetEnvironment(simulator)
            DispatchQueue.main.async {
                self.currentLocation = self.fixedHongKongLocation
                self.locationError = nil
            }
            #else
            startLocationUpdates()
            startHeadingUpdates()
            #endif
        @unknown default:
            break
        }
    }
    
    /// 開始位置更新
    func startLocationUpdates() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            return
        }
        
        // 重置重試計數器
        retryCount = 0
        
        // 在模擬器環境下使用固定的香港位置
        #if targetEnvironment(simulator)
        DispatchQueue.main.async {
            self.currentLocation = self.fixedHongKongLocation
            self.locationError = nil
            self.cacheLocation(self.fixedHongKongLocation)
        }
        #else
        // HIG: 先嘗試快速單次位置請求
        locationManager.requestLocation()
        
        // 然後開始持續位置更新
        locationManager.startUpdatingLocation()
        
        // HIG: 縮短超時時間到8秒，提供更快的用戶反饋
        locationUpdateTimer?.invalidate()
        locationUpdateTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: false) { [weak self] _ in
            self?.retryLocationUpdate()
        }
        #endif
    }
    
    /// 重試位置更新
    private func retryLocationUpdate() {
        locationManager.stopUpdatingLocation()
        
        // HIG: 縮短延遲時間到1秒
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            if self.authorizationStatus == .authorizedWhenInUse || self.authorizationStatus == .authorizedAlways {
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
        locationManager.stopUpdatingLocation()
        stopHeadingUpdates()
        locationUpdateTimer?.invalidate()
        locationUpdateTimer = nil
    }
    
    /// HIG: 開始方向更新 - 符合Apple Maps標準
    func startHeadingUpdates() {
        guard CLLocationManager.headingAvailable() else {
            return
        }
        
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            return
        }
        
        locationManager.startUpdatingHeading()
    }
    
    /// HIG: 停止方向更新
    func stopHeadingUpdates() {
        guard CLLocationManager.headingAvailable() else {
            return
        }
        
        locationManager.stopUpdatingHeading()
    }
    
    /// 評估GPS信號強度
    private func evaluateGPSSignalStrength(_ location: CLLocation) -> GPSSignalStrength {
        let accuracy = location.horizontalAccuracy
        
        // 根據環境返回GPS信號強度
        #if targetEnvironment(simulator)
        // 模擬器環境總是返回good信號
        return .good
        #else
        // 實際設備根據精度計算信號強度
        if accuracy < 0 {
            return .invalid
        } else if accuracy <= 5 {
            return .excellent
        } else if accuracy <= 20 {
            return .good
        } else if accuracy <= 50 {
            return .fair
        } else if accuracy <= 100 {
            return .poor
        } else {
            return .veryPoor
        }
        #endif
    }
    
    /// 取得當前位置的地址（地理編碼）
    func getAddressFromLocation(_ location: CLLocation, completion: @escaping (String?) -> Void) {
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            if let error = error {
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
        guard let location = locations.last else { 
            return 
        }
        
        // 檢測GPS信號強度
        let signalStrength = evaluateGPSSignalStrength(location)
        
        // 檢查位置是否有效（精度是否足夠好）
        if location.horizontalAccuracy < 0 {
            DispatchQueue.main.async {
                self.gpsSignalStrength = .invalid
            }
            return
        }
        
        // HIG: 放寬時間檢查，允許稍舊的位置數據
        if abs(location.timestamp.timeIntervalSinceNow) > 30.0 {
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
            self.gpsSignalStrength = signalStrength
        }
        
        // HIG: 獲得第一個位置後，切換到更高精度但減少頻率的更新
        if retryCount == 0 {
            locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            locationManager.distanceFilter = 20 // 20米才更新，減少頻繁更新
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // HIG: 檢查是否為方向更新失敗
        if let clError = error as? CLError, clError.code == .headingFailure {
            DispatchQueue.main.async {
                self.headingError = error
                self.currentHeading = nil
            }
            return
        }
        
        DispatchQueue.main.async {
            self.locationError = error
            self.gpsSignalStrength = .invalid // 定位失敗時設置為無效信號
        }
        
        // 如果是網絡錯誤且未超過重試次數，重試
        if let clError = error as? CLError {
            switch clError.code {
            case .network, .locationUnknown:
                if retryCount < maxRetryCount {
                    retryCount += 1
                    // HIG: 縮短重試延遲
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                        self?.retryLocationUpdate()
                    }
                } else {
                    // HIG: 如果有緩存位置，使用緩存位置作為備用
                    if let cachedLocation = lastKnownLocation {
                        DispatchQueue.main.async {
                            self.currentLocation = cachedLocation
                            self.locationError = nil
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
                // HIG: 其他錯誤時也嘗試使用緩存位置
                if let cachedLocation = lastKnownLocation {
                    DispatchQueue.main.async {
                        self.currentLocation = cachedLocation
                        self.locationError = nil
                    }
                }
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        DispatchQueue.main.async {
            self.authorizationStatus = status
            
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                // 在模擬器環境下直接設置固定位置
                #if targetEnvironment(simulator)
                self.currentLocation = self.fixedHongKongLocation
                self.locationError = nil
                self.cacheLocation(self.fixedHongKongLocation)
                #else
                self.startLocationUpdates()
                self.startHeadingUpdates()
                #endif
            case .denied, .restricted:
                self.stopLocationUpdates()
            case .notDetermined:
                break
            @unknown default:
                break
            }
        }
    }
    
    /// HIG: 方向更新delegate - 符合Apple Maps標準
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // HIG: 過濾無效的方向數據
        guard newHeading.headingAccuracy >= 0 else {
            DispatchQueue.main.async {
                self.headingAccuracy = newHeading.headingAccuracy
                self.headingError = NSError(domain: "HeadingService", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "指南針精度不足"
                ])
            }
            return
        }
        
        DispatchQueue.main.async {
            self.currentHeading = newHeading
            self.headingAccuracy = newHeading.headingAccuracy
            self.headingError = nil
        }
    }
    

} 