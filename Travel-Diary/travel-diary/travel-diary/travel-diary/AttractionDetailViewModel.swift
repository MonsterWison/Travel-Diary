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
    
    // Wikipedia API 欄位
    @Published var wikiType: String = ""
    @Published var displayTitle: String = ""
    @Published var namespace: [String: Any] = [:]
    @Published var wikibaseItem: String = ""
    @Published var titles: [String: Any] = [:]
    @Published var pageid: Int = 0
    @Published var lang: String = ""
    @Published var dir: String = ""
    @Published var revision: String = ""
    @Published var tid: String = ""
    @Published var timestamp: String = ""
    @Published var wikiDescriptionSource: String = ""
    @Published var contentUrls: [String: Any] = [:]
    @Published var extractHtml: String = ""
    @Published var normalizedTitle: String = ""
    @Published var originalImage: [String: Any] = [:]
    @Published var coordinates: [String: Any] = [:]
    @Published var pageProps: [String: Any] = [:]
    
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
        let now = Date()
        print("[LOG] fetchDetailIfNeeded called at \(now)")
        if let last = Self.lastWikiQueryTime, now.timeIntervalSince(last) < Self.wikiCooldown {
            print("[Wiki] 冷卻中，跳過查詢")
            return
        }
        Self.lastWikiQueryTime = now
        isWikiSearching = true
        let cacheKey = baseAttraction.id.uuidString
        if Self.lastCacheKey != cacheKey {
            print("[LOG] Cache miss, clear detailCache")
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
            print("[LOG] Cache hit, returning early")
            return
        }
        isLoading = true
        error = nil
        let queryTitle = baseAttraction.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? baseAttraction.name
        let urlStr = "https://zh.wikipedia.org/api/rest_v1/page/summary/\(queryTitle)"
        print("[Wiki] 發送 API 請求: \(urlStr)")
        guard let url = URL(string: urlStr) else {
            print("[Wiki] URL 解析失敗，fallback 到 WebSearch")
            self.triggerFallbackWebSearch()
            return
        }
        let task = URLSession.shared.dataTask(with: url) { data, response, err in
            if let err = err {
                print("[Wiki] API 請求失敗: \(err.localizedDescription)，fallback 到 WebSearch")
                DispatchQueue.main.async {
                    self.error = "Wikipedia API 請求失敗：\(err.localizedDescription)"
                    self.isWikiSearching = false
                    self.triggerFallbackWebSearch()
                }
                return
            }
            guard let data = data,
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("[Wiki] 回傳資料格式錯誤，fallback 到 WebSearch")
                DispatchQueue.main.async {
                    self.error = "Wikipedia API 回傳資料格式錯誤"
                    self.isWikiSearching = false
                    self.triggerFallbackWebSearch()
                }
                return
            }
            print("[LOG] Wikipedia API 回傳內容: \(dict)")
            let summary = dict["extract"] as? String ?? ""
            print("[LOG] Wikipedia summary: \(summary)")
            let title = dict["title"] as? String ?? self.baseAttraction.name
            let thumbnail = (dict["thumbnail"] as? [String: Any])?["source"] as? String
            let description = summary.isEmpty ? "" : summary + "\n\n資料來源：維基百科"
            DispatchQueue.main.async {
                if summary.isEmpty {
                    print("[Wiki] 查無 summary，fallback 到 WebSearch")
                    self.isWikiSearching = false
                    self.triggerFallbackWebSearch()
                    return
                }
                print("[Wiki] 取得 Wikipedia 資料: \(title)")
                self.photoURL = thumbnail != nil ? URL(string: thumbnail!) : nil
                self.name = title
                self.distance = self.calcDistanceString()
                self.address = self.baseAttraction.address ?? ""
                self.description = description
                Self.detailCache[cacheKey] = AttractionDetailCache(photoURL: self.photoURL, name: self.name, distance: self.distance, address: self.address, description: self.description)
                self.isWikiSearching = false
                self.isLoading = false
            }
        }
        task.resume()
    }

    private func triggerFallbackWebSearch() {
        guard !hasFallbackTriggered else {
            print("[Fallback] 已經觸發過 fallback，忽略重複呼叫")
            return
        }
        hasFallbackTriggered = true
        print("[Fallback] 觸發 fallback WebSearch，準備通知 View 層 (dismiss 詳情頁)")
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