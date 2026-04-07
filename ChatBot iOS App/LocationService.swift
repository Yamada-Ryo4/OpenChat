import Foundation
import CoreLocation
import Combine

/// 注意：此类不能标记为 @MainActor，因为 CLLocationManagerDelegate 的回调可能在非主线程到达。
/// 所有 UI 更新均通过 DispatchQueue.main.async 确保线程安全。
class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationService()
    
    @Published var locationInfo: String? = nil
    
    private let locationManager = CLLocationManager()
    private var isUpdating = false
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters // 降低精度以省电
    }
    
    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    func updateLocation() {
        guard !isUpdating else { return }
        isUpdating = true
        
        // 1. 尝试 GPS 定位
        if locationManager.authorizationStatus == .authorizedWhenInUse || locationManager.authorizationStatus == .authorizedAlways {
            locationManager.requestLocation()
        } else {
            // 如果没权限，直接使用 IP 定位
            fetchIPLocation()
        }
    }
    
    // MARK: - CLLocationManagerDelegate
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        // 获取到 GPS 坐标，进行反地理编码
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            guard let self = self else { return }
            if let p = placemarks?.first {
                let city = p.locality ?? p.administrativeArea ?? ""
                let district = p.subLocality ?? ""
                let country = p.country ?? ""
                let address = "\(country) \(city) \(district)".trimmingCharacters(in: .whitespaces)
                
                DispatchQueue.main.async {
                    self.locationInfo = "Location: \(address) (Source: GPS)"
                    self.isUpdating = false
                }
            } else {
                // 反编码失败，回退到 IP
                self.fetchIPLocation()
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("GPS Failed: \(error), falling back to IP")
        fetchIPLocation()
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestLocation()
        }
    }
    
    // MARK: - IP Location
    private func fetchIPLocation() {
        // v1.12: 使用 HTTPS 避免明文传输用户 IP 和位置信息
        guard let url = URL(string: "https://ipapi.co/json/") else {
            DispatchQueue.main.async { [weak self] in self?.isUpdating = false }
            return
        }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self else { return }
            
            guard let data = data, error == nil else {
                DispatchQueue.main.async { self.isUpdating = false }
                return
            }
            
            // 简单的 JSON 解析结构
            struct IPInfo: Decodable {
                let country_name: String
                let city: String
            }
            
            if let ipInfo = try? JSONDecoder().decode(IPInfo.self, from: data) {
                DispatchQueue.main.async {
                    // 如果 GPS 已经成功了，就不覆盖
                    if self.locationInfo?.contains("GPS") == true { return }
                    self.locationInfo = "Location: \(ipInfo.country_name) \(ipInfo.city) (Source: IP)"
                    self.isUpdating = false
                }
            } else {
                DispatchQueue.main.async { self.isUpdating = false }
            }
        }.resume()
    }
}
