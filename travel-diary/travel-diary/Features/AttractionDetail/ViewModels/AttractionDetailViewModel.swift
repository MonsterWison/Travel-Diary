import Foundation
import Combine
import CoreLocation
import SwiftUI

class AttractionDetailViewModel: ObservableObject {
    @Published var isLoading: Bool = false
    @Published var error: String? = nil
    @Published var photoURL: URL? = nil
    @Published var name: String = ""
    @Published var distance: String = ""
    @Published var address: String = ""
    @Published var description: String = ""
    @Published var isWikiSearching: Bool = false
    var descriptionTextOnly: String {
        if let range = description.range(of: "\n\n資料來源：") {
            return String(description[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return description.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    var descriptionSource: String? {
        if let range = description.range(of: "\n\n資料來源：") {
            return String(description[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private let baseAttraction: NearbyAttraction
    private let userLocation: CLLocation?
    private var cancellables = Set<AnyCancellable>()
    private static var detailCache: [String: AttractionDetailCache] = [:]
    private static var lastCacheKey: String? = nil
    private static var lastWikiQueryTime: Date? = nil
    private static let wikiCooldown: TimeInterval = 1.0 // 1 秒冷卻
    private var hasFallbackTriggered = false
    
    // 多語言 Wikipedia API 支援
    private let wikiLanguages = ["zh", "en", "ja", "es", "fr", "de", "ko", "it"]
    private var currentLanguageIndex = 0

    /// 用於通知View層fallback到WebSearch
    var onFallbackWebSearch: (() -> Void)? = nil

    struct AttractionDetailCache {
        let photoURL: URL?
        let name: String
        let distance: String
        let address: String
        let description: String
    }

    init(attraction: NearbyAttraction, userLocation: CLLocation?) {
        self.baseAttraction = attraction
        self.userLocation = userLocation
        self.name = attraction.name
        self.address = attraction.address ?? ""
        self.description = ""
        self.distance = ""
    }

    func fetchDetailIfNeeded() {
        hasFallbackTriggered = false // 每次進入時重設 fallback flag
        currentLanguageIndex = 0 // 重設語言索引
        
        // 冷卻判斷
        let now = Date()
        if let last = Self.lastWikiQueryTime, now.timeIntervalSince(last) < Self.wikiCooldown {
            print("[Wiki] 冷卻中，跳過查詢")
            return
        }
        Self.lastWikiQueryTime = now
        isWikiSearching = true
        let cacheKey = baseAttraction.id.uuidString
        if Self.lastCacheKey != cacheKey {
            Self.detailCache.removeAll()
            Self.lastCacheKey = cacheKey
        }
        if let cached = Self.detailCache[cacheKey] {
            print("[Wiki] 使用快取資料: \(cached.name)")
            self.photoURL = cached.photoURL
            self.name = cached.name
            self.distance = cached.distance
            self.address = cached.address
            self.description = cached.description
            return
        }
        isLoading = true
        error = nil
        
        // 開始多語言 Wikipedia API 查詢
        searchWikipediaMultiLanguage()
    }
    
    private func searchWikipediaMultiLanguage() {
        guard currentLanguageIndex < wikiLanguages.count else {
            print("[Wiki] 所有語言都查詢完畢，fallback 到 WebSearch")
            self.triggerFallbackWebSearch()
            return
        }
        
        let currentLang = wikiLanguages[currentLanguageIndex]
        let queryTitle = baseAttraction.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? baseAttraction.name
        let urlStr = "https://\(currentLang).wikipedia.org/api/rest_v1/page/summary/\(queryTitle)"
        print("[Wiki] 嘗試語言 [\(currentLang)] 發送 API 請求: \(urlStr)")
        
        guard let url = URL(string: urlStr) else {
            print("[Wiki] URL 解析失敗，嘗試下一個語言")
            currentLanguageIndex += 1
            searchWikipediaMultiLanguage()
            return
        }
        
        let task = URLSession.shared.dataTask(with: url) { data, response, err in
            if let err = err {
                print("[Wiki] [\(currentLang)] API 請求失敗: \(err.localizedDescription)，嘗試下一個語言")
                DispatchQueue.main.async {
                    self.currentLanguageIndex += 1
                    self.searchWikipediaMultiLanguage()
                }
                return
            }
            
            guard let data = data,
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("[Wiki] [\(currentLang)] 回傳資料格式錯誤，嘗試下一個語言")
                DispatchQueue.main.async {
                    self.currentLanguageIndex += 1
                    self.searchWikipediaMultiLanguage()
                }
                return
            }
            
            let summary = dict["extract"] as? String ?? ""
            let title = dict["title"] as? String ?? self.baseAttraction.name
            let thumbnail = (dict["thumbnail"] as? [String: Any])?["source"] as? String
            
            DispatchQueue.main.async {
                if summary.isEmpty {
                    print("[Wiki] [\(currentLang)] 查無 summary，嘗試下一個語言")
                    self.currentLanguageIndex += 1
                    self.searchWikipediaMultiLanguage()
                    return
                }
                
                // 成功找到資料！
                print("[Wiki] [\(currentLang)] 取得 Wikipedia 資料: \(title)")
                let languageName = self.getLanguageDisplayName(currentLang)
                let description = summary + "\n\n資料來源：Wikipedia (\(languageName))"
                
                self.photoURL = thumbnail != nil ? URL(string: thumbnail!) : nil
                self.name = title
                self.distance = self.calcDistanceString()
                self.address = self.baseAttraction.address ?? ""
                self.description = description
                
                let cacheKey = self.baseAttraction.id.uuidString
                Self.detailCache[cacheKey] = AttractionDetailCache(
                    photoURL: self.photoURL,
                    name: self.name,
                    distance: self.distance,
                    address: self.address,
                    description: self.description
                )
                
                self.isWikiSearching = false
                self.isLoading = false
            }
        }
        task.resume()
    }
    
    private func getLanguageDisplayName(_ langCode: String) -> String {
        switch langCode {
        case "zh": return "中文"
        case "en": return "English"
        case "ja": return "日本語"
        case "es": return "Español"
        case "fr": return "Français"
        case "de": return "Deutsch"
        case "ko": return "한국어"
        case "it": return "Italiano"
        default: return langCode.uppercased()
        }
    }

    private func triggerFallbackWebSearch() {
        guard !hasFallbackTriggered else {
            print("[Fallback] 已經觸發過 fallback，忽略重複呼叫")
            return
        }
        hasFallbackTriggered = true
        print("[Fallback] 觸發 fallback WebSearch，準備通知 View 層")
        DispatchQueue.main.async {
            self.isLoading = false
            self.onFallbackWebSearch?()
        }
    }

    private func calcDistanceString() -> String {
        guard let userLoc = self.userLocation else { return "" }
        let attractionLoc = CLLocation(latitude: self.baseAttraction.coordinate.latitude, longitude: self.baseAttraction.coordinate.longitude)
        let dist = userLoc.distance(from: attractionLoc)
        if dist < 1000 {
            return String(format: "%.0f 公尺", dist)
        } else {
            return String(format: "%.1f 公里", dist/1000)
        }
    }
} 