import Foundation
import SwiftUI

// MARK: - Wikipedia 緩存數據結構
struct WikipediaCacheItem: Codable {
    let queryKey: String
    let title: String
    let summary: String
    let thumbnailURL: String?
    let language: String
    let timestamp: Date
    
    init(queryKey: String, title: String, summary: String, thumbnailURL: String?, language: String) {
        self.queryKey = queryKey
        self.title = title
        self.summary = summary
        self.thumbnailURL = thumbnailURL
        self.language = language
        self.timestamp = Date()
    }
}

// MARK: - Wikipedia 緩存管理器
class WikipediaCache: ObservableObject {
    static let shared = WikipediaCache()
    
    private let maxCacheSize = 50
    private let userDefaults = UserDefaults.standard
    private let cacheKey = "WikipediaCacheItems"
    
    @Published private var cacheItems: [WikipediaCacheItem] = []
    
    private init() {
        loadCacheFromStorage()
    }
    
    // MARK: - 緩存操作
    
    /// 生成查詢鍵
    private func generateQueryKey(name: String, language: String) -> String {
        return "\(name.lowercased())_\(language)".replacingOccurrences(of: " ", with: "_")
    }
    
    /// 檢查是否有緩存
    func getCachedItem(for name: String, language: String) -> WikipediaCacheItem? {
        let queryKey = generateQueryKey(name: name, language: language)
        
        print("[WikiCache] 查詢鍵: \(queryKey)")
        print("[WikiCache] 當前緩存項目數: \(cacheItems.count)")
        
        if let item = cacheItems.first(where: { $0.queryKey == queryKey }) {
            // 嚴格驗證緩存項目的名稱匹配度
            let matchScore = calculateCacheMatchScore(queryName: name, cachedTitle: item.title)
            print("[WikiCache] 緩存項目匹配分數: \(matchScore) - 查詢: \(name) vs 緩存: \(item.title)")
            
            // 如果匹配度不足，自動清除該緩存項目
            if matchScore < 0.6 {
                print("[WikiCache] ❌ 緩存項目匹配度不足，自動清除: \(item.title) (分數: \(matchScore))")
                removeCachedItem(for: name, language: language)
                return nil
            }
            
            // 額外檢查：確保有實質的詞語重疊
            if !hasSubstantialWordOverlap(queryName: name, cachedTitle: item.title) {
                print("[WikiCache] ❌ 緩存項目缺乏實質詞語重疊，自動清除: \(item.title)")
                removeCachedItem(for: name, language: language)
                return nil
            }
            
            // 更新訪問時間（LRU 策略）
            updateItemTimestamp(queryKey: queryKey)
            print("[WikiCache] ✅ 緩存項目通過嚴格驗證: \(name) (\(language)) - 標題: \(item.title)")
            return item
        }
        
        print("[WikiCache] ❌ 無緩存資料: \(name) (\(language))")
        print("[WikiCache] 現有緩存鍵: \(cacheItems.map { $0.queryKey }.joined(separator: ", "))")
        return nil
    }
    
    /// 保存到緩存
    func cacheItem(name: String, title: String, summary: String, thumbnailURL: String?, language: String) {
        let queryKey = generateQueryKey(name: name, language: language)
        let newItem = WikipediaCacheItem(
            queryKey: queryKey,
            title: title,
            summary: summary,
            thumbnailURL: thumbnailURL,
            language: language
        )
        
        // 如果已存在，先移除舊的
        cacheItems.removeAll { $0.queryKey == queryKey }
        
        // 添加新項目到開頭
        cacheItems.insert(newItem, at: 0)
        
        // 保持緩存大小限制
        if cacheItems.count > maxCacheSize {
            cacheItems = Array(cacheItems.prefix(maxCacheSize))
        }
        
        // 保存到本地存儲
        saveCacheToStorage()
        
        print("[WikiCache] 💾 緩存新資料: \(title) (\(language)) - 查詢鍵: \(queryKey) - 總數: \(cacheItems.count)/\(maxCacheSize)")
    }
    
    /// 清除特定的緩存項目
    func removeCachedItem(for name: String, language: String) {
        let queryKey = generateQueryKey(name: name, language: language)
        let originalCount = cacheItems.count
        cacheItems.removeAll { $0.queryKey == queryKey }
        
        if cacheItems.count < originalCount {
            saveCacheToStorage()
            print("[WikiCache] 🗑️ 已清除錯誤緩存: \(name) (\(language)) - 查詢鍵: \(queryKey)")
        }
    }
    
    /// 清除所有緩存
    func clearAllCache() {
        cacheItems.removeAll()
        saveCacheToStorage()
        print("[WikiCache] 🗑️ 已清除所有緩存")
    }
    
    /// 更新項目時間戳（LRU 策略）
    private func updateItemTimestamp(queryKey: String) {
        if let index = cacheItems.firstIndex(where: { $0.queryKey == queryKey }) {
            let updatedItem = cacheItems[index]
            cacheItems.remove(at: index)
            
            // 創建新的項目並更新時間戳
            let newItem = WikipediaCacheItem(
                queryKey: updatedItem.queryKey,
                title: updatedItem.title,
                summary: updatedItem.summary,
                thumbnailURL: updatedItem.thumbnailURL,
                language: updatedItem.language
            )
            
            // 插入到開頭
            cacheItems.insert(newItem, at: 0)
            saveCacheToStorage()
        }
    }
    
    /// 清空緩存
    func clearCache() {
        cacheItems.removeAll()
        userDefaults.removeObject(forKey: cacheKey)
        print("[WikiCache] 清空所有緩存")
    }
    
    /// 獲取緩存統計信息
    func getCacheStats() -> (count: Int, maxSize: Int) {
        return (count: cacheItems.count, maxSize: maxCacheSize)
    }
    
    /// 獲取所有緩存項目（用於調試）
    func getAllCacheItems() -> [WikipediaCacheItem] {
        return cacheItems
    }
    
    // MARK: - 本地存儲
    
    private func saveCacheToStorage() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(cacheItems)
            userDefaults.set(data, forKey: cacheKey)
            print("[WikiCache] 緩存已保存到本地存儲")
        } catch {
            print("[WikiCache] 保存緩存失敗: \(error.localizedDescription)")
        }
    }
    
    private func loadCacheFromStorage() {
        guard let data = userDefaults.data(forKey: cacheKey) else {
            print("[WikiCache] 無本地緩存數據")
            return
        }
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            cacheItems = try decoder.decode([WikipediaCacheItem].self, from: data)
            
            // 按時間戳排序（最新的在前）
            cacheItems.sort { $0.timestamp > $1.timestamp }
            
            print("[WikiCache] 從本地存儲載入 \(cacheItems.count) 個緩存項目")
        } catch {
            print("[WikiCache] 載入緩存失敗: \(error.localizedDescription)")
            cacheItems = []
        }
    }
    
    // MARK: - 緩存清理
    
    /// 清理過期緩存（7天前的項目）
    func cleanExpiredItems() {
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let originalCount = cacheItems.count
        
        cacheItems.removeAll { $0.timestamp < sevenDaysAgo }
        
        if cacheItems.count != originalCount {
            saveCacheToStorage()
            print("[WikiCache] 清理過期緩存: \(originalCount - cacheItems.count) 個項目")
        }
    }
    
    /// 計算緩存匹配分數
    private func calculateCacheMatchScore(queryName: String, cachedTitle: String) -> Double {
        let cleanQueryName = queryName.lowercased()
            .replacingOccurrences(of: "[^a-zA-Z0-9\\u{4e00}-\\u{9fff}]", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        let cleanCachedTitle = cachedTitle.lowercased()
            .replacingOccurrences(of: "[^a-zA-Z0-9\\u{4e00}-\\u{9fff}]", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 完全匹配
        if cleanQueryName == cleanCachedTitle {
            return 1.0
        }
        
        // 分詞匹配
        let queryWords = Set(cleanQueryName.components(separatedBy: " ").filter { !$0.isEmpty })
        let cachedWords = Set(cleanCachedTitle.components(separatedBy: " ").filter { !$0.isEmpty })
        
        guard !queryWords.isEmpty && !cachedWords.isEmpty else {
            return 0.0
        }
        
        // 計算詞語重疊度
        let intersection = queryWords.intersection(cachedWords)
        let union = queryWords.union(cachedWords)
        let jaccardSimilarity = Double(intersection.count) / Double(union.count)
        
        // 檢查是否包含核心詞語
        let hasCore = queryWords.contains { word in
            word.count >= 3 && cachedWords.contains { $0.contains(word) || word.contains($0) }
        }
        
        // 如果有核心詞語匹配，提高分數
        if hasCore {
            return min(jaccardSimilarity * 1.5, 1.0)
        }
        
        return jaccardSimilarity
    }
    
    /// 檢查是否有實質的詞語重疊
    private func hasSubstantialWordOverlap(queryName: String, cachedTitle: String) -> Bool {
        let cleanQueryName = queryName.lowercased()
            .replacingOccurrences(of: "[^a-zA-Z0-9\\u{4e00}-\\u{9fff}]", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        let cleanCachedTitle = cachedTitle.lowercased()
            .replacingOccurrences(of: "[^a-zA-Z0-9\\u{4e00}-\\u{9fff}]", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        let queryWords = Set(cleanQueryName.components(separatedBy: " ").filter { $0.count >= 2 })
        let cachedWords = Set(cleanCachedTitle.components(separatedBy: " ").filter { $0.count >= 2 })
        
        // 必須有至少一個有意義的詞語重疊（至少2個字符）
        let meaningfulOverlap = queryWords.intersection(cachedWords)
        
        // 或者有部分匹配的長詞語（至少3個字符）
        let partialMatches = queryWords.filter { queryWord in
            queryWord.count >= 3 && cachedWords.contains { cachedWord in
                cachedWord.count >= 3 && (queryWord.contains(cachedWord) || cachedWord.contains(queryWord))
            }
        }
        
        return !meaningfulOverlap.isEmpty || !partialMatches.isEmpty
    }
}

// MARK: - 緩存管理視圖（用於調試和管理）
struct WikipediaCacheManagementView: View {
    @StateObject private var cache = WikipediaCache.shared
    @State private var cacheItems: [WikipediaCacheItem] = []
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("緩存統計")) {
                    let stats = cache.getCacheStats()
                    HStack {
                        Text("緩存項目數量")
                        Spacer()
                        Text("\(stats.count) / \(stats.maxSize)")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text("緩存項目")) {
                    ForEach(cacheItems, id: \.queryKey) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.headline)
                            Text("語言: \(item.language)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("查詢鍵: \(item.queryKey)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("時間: \(item.timestamp, formatter: dateFormatter)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("Wikipedia 緩存")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("清空緩存") {
                        cache.clearCache()
                        refreshCacheItems()
                    }
                    .foregroundColor(.red)
                }
            }
        }
        .onAppear {
            refreshCacheItems()
        }
    }
    
    private func refreshCacheItems() {
        cacheItems = cache.getAllCacheItems()
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }
}

#Preview {
    WikipediaCacheManagementView()
} 