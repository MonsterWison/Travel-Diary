import Foundation
import CoreLocation

struct CompareModel: Identifiable, Codable {
    var id: UUID
    let name: String // 主要名稱
    let address: String // 地址
    let latitude: Double
    let longitude: Double
    
    /// 便利初始化方法
    init(name: String, address: String, latitude: Double, longitude: Double) {
        self.id = UUID()
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
    }
    
    /// 轉換為CLLocationCoordinate2D
    var coordinate: CLLocationCoordinate2D {
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    /// 計算與另一個位置的距離
    func distance(to other: CompareModel) -> Double {
        let location1 = CLLocation(latitude: latitude, longitude: longitude)
        let location2 = CLLocation(latitude: other.latitude, longitude: other.longitude)
        return location1.distance(from: location2)
    }
    
    /// 計算與坐標的距離
    func distance(to coordinate: CLLocationCoordinate2D) -> Double {
        let location1 = CLLocation(latitude: latitude, longitude: longitude)
        let location2 = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return location1.distance(from: location2)
    }
} 