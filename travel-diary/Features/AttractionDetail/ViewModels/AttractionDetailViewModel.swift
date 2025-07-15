import Foundation
import Combine
import CoreLocation
import SwiftUI
import MapKit

@MainActor
class AttractionDetailViewModel: ObservableObject {
    @Published var attractionName: String = ""
    @Published var wikipediaTitle: String = ""
    @Published var wikipediaSummary: String = ""
    @Published var wikipediaThumbnailURL: String? = nil
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var attractionCandidates: [AttractionCache] = []
    @Published var attractionsManagementVM = AttractionsManagementViewModel()
    
    private let wikipediaCache = WikipediaCache.shared
    // 全球通用的語言優先級 - 英文優先，適用於國際性應用
    private let supportedLanguages = ["en", "zh", "ja", "ko", "fr", "de", "es", "it", "pt", "ru", "ar", "hi"]
    
    // 新增：景點地址信息用於驗證
    private var attractionAddress: String?
    private var attractionCoordinate: CLLocationCoordinate2D?
    
    init(attractionName: String, attractionAddress: String? = nil, attractionCoordinate: CLLocationCoordinate2D? = nil) {
        self.attractionName = attractionName
        self.attractionAddress = attractionAddress
        self.attractionCoordinate = attractionCoordinate
        // 嚴格：如果已有正確資料，直接 return
        if !self.wikipediaTitle.isEmpty && !self.wikipediaSummary.isEmpty {
            return
        }
        loadWikipediaData()
    }
    
    // MARK: - Wikipedia 資料載入
    
    private func loadWikipediaData() {
        // 首先檢查緩存是否有百分百匹配的資料
        if let cachedItem = findExactMatchInCache() {
            // 對緩存的資料進行嚴格的名稱匹配驗證
            let nameMatchScore = calculateNameMatchScore(
                attractionName: attractionName,
                wikipediaTitle: cachedItem.title
            )
            
            // 嚴格的匹配閾值 - 從0.2提高到0.6，確保高質量匹配
            if nameMatchScore < 0.6 {
                wikipediaCache.removeCachedItem(for: attractionName, language: cachedItem.language)
            } else {
                // 額外檢查：確保有實質的詞語重疊
                if hasSubstantialWordOverlap(attractionName: attractionName, wikipediaTitle: cachedItem.title) {
                    self.wikipediaTitle = cachedItem.title
                    self.wikipediaSummary = cachedItem.summary
                    self.wikipediaThumbnailURL = cachedItem.thumbnailURL
                    return
                } else {
                    wikipediaCache.removeCachedItem(for: attractionName, language: cachedItem.language)
                }
            }
        }
        
        // 沒有找到緩存，從 Wikipedia API 獲取資料
        isLoading = true
        errorMessage = nil
        
        Task {
            await fetchFromWikipediaAPI(attractionName: attractionName)
        }
    }
    
    private func findExactMatchInCache() -> WikipediaCacheItem? {
        // 嘗試所有支持的語言，尋找百分百匹配
        for language in supportedLanguages {
            if let cachedItem = wikipediaCache.getCachedItem(for: attractionName, language: language) {
                return cachedItem
            }
        }
        return nil
    }
    
    // MARK: - Wikipedia API 獲取
    
    /// 從 Wikipedia API 獲取景點資料 - 優化版本（並行搜索）
    private func fetchFromWikipediaAPI(attractionName: String) async {
        
        // 智能語言選擇 - 只選擇最相關的3-4種語言
        let allLanguages = getLanguagePriority(for: attractionName)
        let priorityLanguages = Array(allLanguages.prefix(4)) // 只搜索前4種語言
        
        // 並行搜索多種語言
        await withTaskGroup(of: (String, (title: String, summary: String, thumbnailURL: String?)?).self) { group in
            // 為每種語言創建並行任務
            for language in priorityLanguages {
                group.addTask {
                    let result = await self.searchWikipediaWithTimeout(
                        query: attractionName, 
                        language: language, 
                        timeout: 8.0 // 每個語言最多8秒
                    )
                    return (language, result)
                }
            }
            
            // 收集結果並尋找最佳匹配
            var bestResult: (language: String, data: (title: String, summary: String, thumbnailURL: String?))?
            var bestScore: Double = 0.0
            var fallbackResult: (language: String, data: (title: String, summary: String, thumbnailURL: String?))?
            
            for await (language, result) in group {
                guard let data = result else { continue }
                
                // 計算匹配分數
                let nameScore = calculateNameMatchScore(
                    attractionName: attractionName,
                    wikipediaTitle: data.title
                )
                
                // 檢查是否有實質重疊
                let hasOverlap = hasSubstantialWordOverlap(
                    attractionName: attractionName,
                    wikipediaTitle: data.title
                )
                
                if !hasOverlap {
                    continue
                }
                
                // 如果名稱匹配度很高（>0.8），立即使用並停止其他搜索
                if nameScore > 0.8 {
                    bestResult = (language, data)
                    bestScore = nameScore
                    break // 早期終止
                }
                
                // 記錄最佳結果
                if nameScore > bestScore {
                    bestResult = (language, data)
                    bestScore = nameScore
                }
                
                // 保存備用結果（名稱匹配度 > 0.4）
                if nameScore > 0.4 && fallbackResult == nil {
                    fallbackResult = (language, data)
                }
            }
            
            // 處理搜索結果
            if let best = bestResult {
                await processBestResult(
                    attractionName: attractionName,
                    language: best.language,
                    data: best.data,
                    nameScore: bestScore
                )
            } else if let fallback = fallbackResult {
                await processFallbackResult(
                    attractionName: attractionName,
                    language: fallback.language,
                    data: fallback.data
                )
            } else {
                await MainActor.run {
                    self.errorMessage = "無法找到匹配的 Wikipedia 資料"
                    self.isLoading = false
                }
            }
        }
    }
    
    /// 處理最佳搜索結果
    private func processBestResult(
        attractionName: String,
        language: String,
        data: (title: String, summary: String, thumbnailURL: String?),
        nameScore: Double
    ) async {
        let hasOverlap = hasSubstantialWordOverlap(
            attractionName: attractionName,
            wikipediaTitle: data.title
        )
        let mainQuery = extractMainPlaceName(attractionName)
        let mainWiki = extractMainPlaceName(data.title)
        let queryWords = mainWords(attractionName)
        let wikiWords = mainWords(data.title)
        let intersection = queryWords.intersection(wikiWords)
        if intersection.count >= 2 {
            await MainActor.run {
                self.wikipediaTitle = data.title
                self.wikipediaSummary = data.summary
                self.wikipediaThumbnailURL = data.thumbnailURL
                self.isLoading = false
            }
            wikipediaCache.cacheItem(
                name: attractionName,
                title: data.title,
                summary: data.summary,
                thumbnailURL: data.thumbnailURL,
                language: language
            )
            return
        } else if !mainQuery.isEmpty && !mainWiki.isEmpty && (mainQuery == mainWiki || mainWiki.contains(mainQuery) || mainQuery.contains(mainWiki)) {
            await MainActor.run {
                self.wikipediaTitle = data.title
                self.wikipediaSummary = data.summary
                self.wikipediaThumbnailURL = data.thumbnailURL
                self.isLoading = false
            }
            wikipediaCache.cacheItem(
                name: attractionName,
                title: data.title,
                summary: data.summary,
                thumbnailURL: data.thumbnailURL,
                language: language
            )
            return
        } else if nameScore > 0.7 && hasOverlap {
            await MainActor.run {
                self.wikipediaTitle = data.title
                self.wikipediaSummary = data.summary
                self.wikipediaThumbnailURL = data.thumbnailURL
                self.isLoading = false
            }
            wikipediaCache.cacheItem(
                name: attractionName,
                title: data.title,
                summary: data.summary,
                thumbnailURL: data.thumbnailURL,
                language: language
            )
            return
        } else if nameScore > 0.5 && hasOverlap {
            let isValid = await validateWikipediaMatch(
                wikipediaTitle: data.title,
                wikipediaSummary: data.summary,
                attractionAddress: attractionAddress ?? "",
                attractionCoordinate: attractionCoordinate
            )
            if isValid {
                await MainActor.run {
                    self.wikipediaTitle = data.title
                    self.wikipediaSummary = data.summary
                    self.wikipediaThumbnailURL = data.thumbnailURL
                    self.isLoading = false
                }
                wikipediaCache.cacheItem(
                    name: attractionName,
                    title: data.title,
                    summary: data.summary,
                    thumbnailURL: data.thumbnailURL,
                    language: language
                )
                return
            }
        }
        // 其餘一律失敗
        await MainActor.run {
            self.wikipediaTitle = ""
            self.wikipediaSummary = ""
            self.wikipediaThumbnailURL = nil
            self.isLoading = false
            self.errorMessage = "無法找到匹配的 Wikipedia 資料"
        }
    }
    private func processFallbackResult(
        attractionName: String,
        language: String,
        data: (title: String, summary: String, thumbnailURL: String?)
    ) async {
        // 嚴格：備用結果一律不顯示
        await MainActor.run {
            self.wikipediaTitle = ""
            self.wikipediaSummary = ""
            self.wikipediaThumbnailURL = nil
            self.isLoading = false
            self.errorMessage = "無法找到匹配的 Wikipedia 資料"
        }
    }
    
    /// 帶超時的 Wikipedia 搜索
    private func searchWikipediaWithTimeout(
        query: String,
        language: String,
        timeout: TimeInterval
    ) async -> (title: String, summary: String, thumbnailURL: String?)? {
        
        return await withTimeout(timeout) {
            await self.searchWikipedia(query: query, language: language)
        }
    }
    
    /// 通用超時包裝器
    private func withTimeout<T>(_ timeout: TimeInterval, operation: @escaping () async -> T?) async -> T? {
        return await withTaskGroup(of: T?.self) { group in
            // 添加主要操作
            group.addTask {
                await operation()
            }
            
            // 添加超時任務
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return nil
            }
            
            // 返回第一個完成的結果
            if let result = await group.next() {
                group.cancelAll() // 取消其他任務
                return result
            }
            
            return nil
        }
    }
    
    // MARK: - 智能語言選擇
    
    private func getLanguagePriority(for attractionName: String) -> [String] {
        let name = attractionName.lowercased()
        
        // 根據景點名稱特徵選擇最相關的語言（限制為3-4種）
        if containsChineseCharacters(name) {
            // 中文名稱：中文、英文、日文
            return ["zh", "en", "ja"]
        } else if containsJapaneseCharacters(name) {
            // 日文名稱：日文、英文、中文
            return ["ja", "en", "zh"]
        } else if containsKoreanCharacters(name) {
            // 韓文名稱：韓文、英文、中文
            return ["ko", "en", "zh"]
        } else if containsArabicCharacters(name) {
            // 阿拉伯文名稱：阿拉伯文、英文
            return ["ar", "en"]
        } else if name.contains("château") || name.contains("musée") || name.contains("cathédrale") || name.contains("église") {
            // 法語景點：法語、英文
            return ["fr", "en"]
        } else if name.contains("museo") || name.contains("catedral") || name.contains("plaza") || name.contains("iglesia") {
            // 西班牙語景點：西班牙語、英文
            return ["es", "en"]
        } else if name.contains("museo") || name.contains("cattedrale") || name.contains("piazza") || name.contains("chiesa") {
            // 義大利語景點：義大利語、英文
            return ["it", "en"]
        } else if name.contains("museu") || name.contains("catedral") || name.contains("praça") || name.contains("igreja") {
            // 葡萄牙語景點：葡萄牙語、英文
            return ["pt", "en"]
        } else if name.contains("музей") || name.contains("собор") || name.contains("площадь") || name.contains("церковь") {
            // 俄語景點：俄語、英文
            return ["ru", "en"]
        } else if name.contains("museum") || name.contains("cathedral") || name.contains("church") || name.contains("palace") || 
                  name.contains("castle") || name.contains("tower") || name.contains("bridge") || name.contains("square") ||
                  name.contains("gallery") || name.contains("center") || name.contains("centre") || name.contains("park") ||
                  name.contains("garden") || name.contains("beach") || name.contains("temple") || name.contains("shrine") {
            // 明確的英語景點標識：英文、中文、法文、德文
            return ["en", "zh", "fr", "de"]
        } else {
            // 其他情況：英文、中文、法文
            return ["en", "zh", "fr"]
        }
    }
    
    private func containsChineseCharacters(_ text: String) -> Bool {
        return text.range(of: "\\p{Script=Han}", options: .regularExpression) != nil
    }
    
    private func containsJapaneseCharacters(_ text: String) -> Bool {
        return text.range(of: "\\p{Script=Hiragana}", options: .regularExpression) != nil ||
               text.range(of: "\\p{Script=Katakana}", options: .regularExpression) != nil
    }
    
    private func containsKoreanCharacters(_ text: String) -> Bool {
        return text.range(of: "\\p{Script=Hangul}", options: .regularExpression) != nil
    }
    
    private func containsArabicCharacters(_ text: String) -> Bool {
        return text.range(of: "\\p{Script=Arabic}", options: .regularExpression) != nil
    }
    
    // MARK: - 名稱匹配驗證
    
    /// 計算景點名稱與 Wikipedia 標題的匹配分數
    private func calculateNameMatchScore(attractionName: String, wikipediaTitle: String) -> Double {
        let cleanAttractionName = attractionName.lowercased()
            .replacingOccurrences(of: "[^a-zA-Z0-9\\u{4e00}-\\u{9fff}]", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        let cleanWikipediaTitle = wikipediaTitle.lowercased()
            .replacingOccurrences(of: "[^a-zA-Z0-9\\u{4e00}-\\u{9fff}]", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 完全匹配
        if cleanAttractionName == cleanWikipediaTitle {
            return 1.0
        }
        
        // 檢查是否一個是另一個的子集或超集（如"銀線灣泳灘"包含"銀線灣"）
        if cleanAttractionName.contains(cleanWikipediaTitle) || cleanWikipediaTitle.contains(cleanAttractionName) {
            let shorterLength = min(cleanAttractionName.count, cleanWikipediaTitle.count)
            let longerLength = max(cleanAttractionName.count, cleanWikipediaTitle.count)
            let containmentScore = Double(shorterLength) / Double(longerLength)
            
            // 如果包含關係的相似度超過70%，給予高分
            if containmentScore >= 0.7 {
                return 0.9
            } else if containmentScore >= 0.5 {
                return 0.7
            }
        }
        
        // 分詞匹配
        let attractionWords = Set(cleanAttractionName.components(separatedBy: " ").filter { !$0.isEmpty })
        let wikipediaWords = Set(cleanWikipediaTitle.components(separatedBy: " ").filter { !$0.isEmpty })
        
        guard !attractionWords.isEmpty && !wikipediaWords.isEmpty else {
            return 0.0
        }
        
        // 計算詞語重疊度
        let intersection = attractionWords.intersection(wikipediaWords)
        let union = attractionWords.union(wikipediaWords)
        let jaccardSimilarity = Double(intersection.count) / Double(union.count)
        
        // 檢查是否包含核心詞語
        let hasCore = attractionWords.contains { word in
            word.count >= 2 && wikipediaWords.contains { $0.contains(word) || word.contains($0) }
        }
        
        // 如果有核心詞語匹配，提高分數
        if hasCore {
            return min(jaccardSimilarity * 1.5, 1.0)
        }
        
        return jaccardSimilarity
    }
    
    /// 檢查是否有實質的詞語重疊 - 防止完全不相關的匹配
    private func hasSubstantialWordOverlap(attractionName: String, wikipediaTitle: String) -> Bool {
        let cleanAttractionName = attractionName.lowercased()
            .replacingOccurrences(of: "[^a-zA-Z0-9\\u{4e00}-\\u{9fff}]", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        let cleanWikipediaTitle = wikipediaTitle.lowercased()
            .replacingOccurrences(of: "[^a-zA-Z0-9\\u{4e00}-\\u{9fff}]", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        let attractionWords = Set(cleanAttractionName.components(separatedBy: " ").filter { $0.count >= 2 })
        let wikipediaWords = Set(cleanWikipediaTitle.components(separatedBy: " ").filter { $0.count >= 2 })
        
        // 必須有至少一個有意義的詞語重疊（至少2個字符）
        let meaningfulOverlap = attractionWords.intersection(wikipediaWords)
        
        // 或者有部分匹配的長詞語（至少3個字符）
        let partialMatches = attractionWords.filter { attractionWord in
            attractionWord.count >= 3 && wikipediaWords.contains { wikipediaWord in
                wikipediaWord.count >= 3 && (attractionWord.contains(wikipediaWord) || wikipediaWord.contains(attractionWord))
            }
        }
        
        let hasOverlap = !meaningfulOverlap.isEmpty || !partialMatches.isEmpty
        
        return hasOverlap
    }
    
    /// 檢查Wikipedia內容是否與景點完全不相關
    private func isCompletelyUnrelated(attractionName: String, wikipediaContent: String) -> Bool {
        let attractionLower = attractionName.lowercased()
        let contentLower = wikipediaContent.lowercased()
        
        // 提取景點名稱中的關鍵詞
        let attractionKeywords = attractionLower
            .replacingOccurrences(of: "[^a-zA-Z0-9\\u{4e00}-\\u{9fff}]", with: " ", options: .regularExpression)
            .components(separatedBy: " ")
            .filter { $0.count >= 2 }
        
        // 檢查是否有任何關鍵詞出現在Wikipedia內容中
        let hasAnyKeyword = attractionKeywords.contains { keyword in
            contentLower.contains(keyword)
        }
        
        // 如果景點名稱中沒有任何關鍵詞出現在Wikipedia內容中，則認為完全不相關
        let isUnrelated = !hasAnyKeyword && attractionKeywords.count > 0
        
        return isUnrelated
    }
    
    // MARK: - 地址驗證機制
    
    /// 驗證 Wikipedia 結果是否與景點地址匹配
    private func validateWikipediaMatch(
        wikipediaTitle: String,
        wikipediaSummary: String,
        attractionAddress: String,
        attractionCoordinate: CLLocationCoordinate2D?
    ) async -> Bool {
        
        // 1. 提取景點地址的關鍵地名
        let attractionLocationKeywords = extractLocationKeywords(from: attractionAddress)
        
        // 2. 提取 Wikipedia 內容的地址信息
        let wikipediaLocationKeywords = extractLocationKeywords(from: wikipediaSummary)
        
        // 3. 計算地址匹配度
        let matchScore = calculateLocationMatchScore(
            attractionKeywords: attractionLocationKeywords,
            wikipediaKeywords: wikipediaLocationKeywords
        )
        
        // 4. 判斷是否匹配（匹配分數 > 0.5 認為是有效匹配 - 從0.3提高到0.5）
        let isValid = matchScore > 0.5
        
        return isValid
    }
    
    /// 從地址文本中提取關鍵地名 - 支援全球地名
    private func extractLocationKeywords(from text: String) -> Set<String> {
        var keywords = Set<String>()
        let lowercaseText = text.lowercased()
        
        // 通用地址關鍵詞提取 - 適用於全球所有地區
        // 1. 提取常見的地址組成部分
        let addressPatterns = [
            // 街道和路名
            "street", "road", "avenue", "lane", "drive", "boulevard", "way", "place", "square", "circle",
            "路", "街", "道", "巷", "弄", "大道", "廣場", "區", "市", "縣", "省", "州", "國",
            "rue", "avenue", "boulevard", "place", "cours", "quai", // 法語
            "straße", "strasse", "gasse", "platz", "weg", "allee", // 德語
            "via", "strada", "piazza", "corso", "viale", // 意大利語
            "calle", "avenida", "plaza", "paseo", "carrera", // 西班牙語
            "rua", "avenida", "praça", "largo", "travessa", // 葡萄牙語
            "улица", "проспект", "площадь", "переулок", // 俄語
            "通り", "丁目", "番地", "区", "市", "町", "村", // 日語
            "로", "길", "동", "구", "시", "군", "도", // 韓語
        ]
        
        // 2. 提取數字和特殊標識符
        let numberPattern = #"\d+"#
        if let regex = try? Regex(numberPattern) {
            let matches = text.matches(of: regex)
            for match in matches {
                keywords.insert(String(text[match.range]))
            }
        }
        
        // 3. 提取地址類型關鍵詞
        for pattern in addressPatterns {
            if lowercaseText.contains(pattern.lowercased()) {
                keywords.insert(pattern)
            }
        }
        
        // 4. 使用智能分詞提取地名 - 分割常見分隔符
        let separators = CharacterSet(charactersIn: " ,-./\\()[]{}|;:\"'")
        let components = text.components(separatedBy: separators)
        
        for component in components {
            let cleanComponent = component.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanComponent.count >= 2 { // 至少2個字符的地名
                keywords.insert(cleanComponent)
                keywords.insert(cleanComponent.lowercased())
            }
        }
        
        // 5. 移除常見的無意義詞
        let stopWords = Set([
            "the", "and", "or", "of", "in", "at", "on", "to", "for", "with", "by", "from", "about",
            "是", "的", "在", "和", "或", "與", "及", "等", "有", "無", "不", "也", "都", "很", "非常",
            "le", "la", "les", "de", "du", "des", "et", "ou", "dans", "sur", "pour", "avec", "par",
            "der", "die", "das", "und", "oder", "in", "an", "auf", "für", "mit", "von", "zu",
            "il", "la", "le", "gli", "e", "o", "in", "su", "per", "con", "da", "di",
            "el", "la", "los", "las", "y", "o", "en", "de", "por", "para", "con", "desde",
            "を", "は", "が", "に", "で", "と", "の", "へ", "から", "まで", "も", "や", "か",
            "을", "를", "이", "가", "에", "에서", "와", "과", "의", "로", "으로", "부터", "까지"
        ])
        
        return keywords.subtracting(stopWords)
    }
    
    /// 計算地址匹配分數
    private func calculateLocationMatchScore(
        attractionKeywords: Set<String>,
        wikipediaKeywords: Set<String>
    ) -> Double {
        
        guard !attractionKeywords.isEmpty && !wikipediaKeywords.isEmpty else {
            return 0.0
        }
        
        // 計算交集
        let intersection = attractionKeywords.intersection(wikipediaKeywords)
        let union = attractionKeywords.union(wikipediaKeywords)
        
        // Jaccard 相似度
        let jaccardSimilarity = Double(intersection.count) / Double(union.count)
        
        // 如果有重要地名匹配，給予額外加分 - 支援多種語言
        let importantMatches = intersection.filter { keyword in
            let lowerKeyword = keyword.lowercased()
            // 重要地名：區域名稱、街道名稱等（多語言支援）
            return lowerKeyword.contains("區") || lowerKeyword.contains("路") || lowerKeyword.contains("街") || 
                   lowerKeyword.contains("道") || lowerKeyword.contains("里") || lowerKeyword.contains("市") ||
                   lowerKeyword.contains("縣") || lowerKeyword.contains("省") || lowerKeyword.contains("州") ||
                   lowerKeyword.contains("village") || lowerKeyword.contains("road") || lowerKeyword.contains("street") ||
                   lowerKeyword.contains("avenue") || lowerKeyword.contains("district") || lowerKeyword.contains("area") ||
                   lowerKeyword.contains("city") || lowerKeyword.contains("town") || lowerKeyword.contains("county") ||
                   lowerKeyword.contains("state") || lowerKeyword.contains("province") || lowerKeyword.contains("region") ||
                   lowerKeyword.contains("rue") || lowerKeyword.contains("avenue") || lowerKeyword.contains("boulevard") ||
                   lowerKeyword.contains("place") || lowerKeyword.contains("quartier") || lowerKeyword.contains("ville") ||
                   lowerKeyword.contains("straße") || lowerKeyword.contains("strasse") || lowerKeyword.contains("platz") ||
                   lowerKeyword.contains("stadt") || lowerKeyword.contains("bezirk") || lowerKeyword.contains("gasse") ||
                   lowerKeyword.contains("via") || lowerKeyword.contains("piazza") || lowerKeyword.contains("corso") ||
                   lowerKeyword.contains("città") || lowerKeyword.contains("quartiere") || lowerKeyword.contains("zona") ||
                   lowerKeyword.contains("calle") || lowerKeyword.contains("avenida") || lowerKeyword.contains("plaza") ||
                   lowerKeyword.contains("ciudad") || lowerKeyword.contains("barrio") || lowerKeyword.contains("zona") ||
                   lowerKeyword.contains("通り") || lowerKeyword.contains("丁目") || lowerKeyword.contains("番地") ||
                   lowerKeyword.contains("区") || lowerKeyword.contains("市") || lowerKeyword.contains("町") ||
                   lowerKeyword.contains("로") || lowerKeyword.contains("길") || lowerKeyword.contains("동") ||
                   lowerKeyword.contains("구") || lowerKeyword.contains("시") || lowerKeyword.contains("군")
        }
        
        let importantBonus = Double(importantMatches.count) * 0.2
        
        return min(jaccardSimilarity + importantBonus, 1.0)
    }
    
    // MARK: - Wikipedia API 搜索
    
    private func searchWikipedia(query: String, language: String) async -> (title: String, summary: String, thumbnailURL: String?)? {
        // 首先嘗試直接頁面查詢
        if let directResult = await fetchWikipediaPageDirect(query: query, language: language) {
            return directResult
        }
        
        // 如果直接查詢失敗，使用搜索API查找相似頁面
        return await searchWikipediaPages(query: query, language: language)
    }
    
    /// 直接頁面查詢（原有功能）
    private func fetchWikipediaPageDirect(query: String, language: String) async -> (title: String, summary: String, thumbnailURL: String?)? {
        // 構建搜索 URL - 使用正確的 Wikipedia REST API 格式
        let searchQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        
        // 對於某些語言代碼，需要特殊處理
        let apiLanguage: String
        switch language {
        case "zh-hk", "zh-tw":
            apiLanguage = "zh"  // 中文變體使用 zh 的 API
        case "pt":
            apiLanguage = "pt"  // 葡萄牙語
        case "ru":
            apiLanguage = "ru"  // 俄語
        case "ar":
            apiLanguage = "ar"  // 阿拉伯語
        case "hi":
            apiLanguage = "hi"  // 印地語
        default:
            apiLanguage = language
        }
        
        let urlString = "https://\(apiLanguage).wikipedia.org/api/rest_v1/page/summary/\(searchQuery)"
        
        guard let url = URL(string: urlString) else {
            return nil
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            if let httpResponse = response as? HTTPURLResponse {
                
                if httpResponse.statusCode == 404 {
                    return nil
                }
                
                guard httpResponse.statusCode == 200 else {
                    return nil
                }
            }
            
            let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
            
            guard let title = json?["title"] as? String,
                  let extract = json?["extract"] as? String else {
                return nil
            }
            
            let thumbnailURL = (json?["thumbnail"] as? [String: Any])?["source"] as? String
            
            return (title: title, summary: extract, thumbnailURL: thumbnailURL)
            
        } catch {
            return nil
        }
    }
    
    /// 搜索Wikipedia頁面（整合Google三維搜尋系統）
    private func searchWikipediaPages(query: String, language: String) async -> (title: String, summary: String, thumbnailURL: String?)? {
        // 對於某些語言代碼，需要特殊處理
        let apiLanguage: String
        switch language {
        case "zh-hk", "zh-tw":
            apiLanguage = "zh"
        case "pt":
            apiLanguage = "pt"
        case "ru":
            apiLanguage = "ru"
        case "ar":
            apiLanguage = "ar"
        case "hi":
            apiLanguage = "hi"
        default:
            apiLanguage = language
        }
        
        // 收集所有候選結果用於三維搜尋
        var allCandidates: [AttractionCache] = []
        
        // 生成多個搜索查詢變體
        let searchQueries = generateSearchQueries(for: query)
        
        for searchVariant in searchQueries {
            let encodedQuery = searchVariant.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? searchVariant
            
            // 使用Wikipedia搜索API
            let searchUrlString = "https://\(apiLanguage).wikipedia.org/w/api.php?action=query&format=json&list=search&srsearch=\(encodedQuery)&srlimit=5"
            
            guard let searchUrl = URL(string: searchUrlString) else {
                continue
            }
            
            do {
                let (searchData, searchResponse) = try await URLSession.shared.data(from: searchUrl)
                
                if let httpResponse = searchResponse as? HTTPURLResponse {
                    guard httpResponse.statusCode == 200 else {
                        continue
                    }
                }
                
                let searchJson = try JSONSerialization.jsonObject(with: searchData, options: []) as? [String: Any]
                
                guard let queryData = searchJson?["query"] as? [String: Any],
                      let searchResults = queryData["search"] as? [[String: Any]],
                      !searchResults.isEmpty else {
                    continue
                }
                
                // 收集所有搜索結果作為候選
                for result in searchResults {
                    guard let pageTitle = result["title"] as? String else { continue }
                    
                    // 獲取頁面詳細資料
                    if let pageResult = await fetchWikipediaPageDirect(query: pageTitle, language: language) {
                        // 創建AttractionCache候選
                        let candidate = AttractionCache(
                            names: [language: pageResult.title],
                            addresses: [language: ""], // Wikipedia沒有地址信息
                            latitude: attractionCoordinate?.latitude ?? 0.0,
                            longitude: attractionCoordinate?.longitude ?? 0.0,
                            descriptions: [language: pageResult.summary],
                            source: "wikipedia_\(language)"
                        )
                        
                        allCandidates.append(candidate)
                    }
                }
                
            } catch {
                continue
            }
        }
        
        // 如果沒有候選結果，返回nil
        guard !allCandidates.isEmpty else {
            return nil
        }
        
        // 使用Google三維搜尋系統選擇最佳匹配
        
        // 設置比對模型
        let compareModel = CompareModel(
            name: query,
            address: attractionAddress ?? "",
            latitude: attractionCoordinate?.latitude ?? 0.0,
            longitude: attractionCoordinate?.longitude ?? 0.0
        )
        
        // 執行三維搜尋
        await MainActor.run {
            attractionsManagementVM.setCompareModel(compareModel)
            attractionsManagementVM.setAttractionCandidates(allCandidates)
        }
        
        // 獲取最佳匹配結果
        let bestMatch = await MainActor.run {
            return attractionsManagementVM.bestMatch
        }
        
        if let bestMatch = bestMatch {
            
            // 轉換為返回格式
            let title = bestMatch.names[language] ?? bestMatch.names.values.first ?? ""
            let summary = bestMatch.descriptions?[language] ?? bestMatch.descriptions?.values.first ?? ""
            let thumbnailURL: String? = nil // Wikipedia搜索結果沒有縮圖URL
            
            return (title: title, summary: summary, thumbnailURL: thumbnailURL)
        } else {
            return nil
        }
    }
    
    /// 生成搜索查詢的多個變體
    private func generateSearchQueries(for query: String) -> [String] {
        var queries: [String] = [query]  // 原始查詢
        
        let lowercaseQuery = query.lowercased()
        
        // 常見的景點類型後綴詞，可能需要移除來提高搜索成功率
        let suffixesToRemove = [
            "gallery", "museum", "theatre", "theater", "center", "centre", 
            "building", "tower", "square", "park", "garden", "beach", "bay",
            "church", "cathedral", "temple", "mosque", "synagogue",
            "hotel", "restaurant", "cafe", "bar", "club", "market",
            "station", "airport", "bridge", "street", "road", "avenue"
        ]
        
        // 嘗試移除常見後綴詞
        for suffix in suffixesToRemove {
            if lowercaseQuery.hasSuffix(" \(suffix)") {
                let withoutSuffix = String(query.dropLast(suffix.count + 1))
                if !withoutSuffix.isEmpty {
                    queries.append(withoutSuffix)
                }
            }
        }
        
        // 對於可能的縮寫，嘗試展開
        let abbreviationExpansions = [
            "st": "saint",
            "mt": "mount",
            "dr": "doctor",
            "ave": "avenue",
            "rd": "road",
            "sq": "square"
        ]
        
        for (abbrev, expansion) in abbreviationExpansions {
            if lowercaseQuery.contains(" \(abbrev) ") || lowercaseQuery.hasPrefix("\(abbrev) ") || lowercaseQuery.hasSuffix(" \(abbrev)") {
                let expanded = query.replacingOccurrences(of: " \(abbrev) ", with: " \(expansion) ", options: .caseInsensitive)
                    .replacingOccurrences(of: "^\(abbrev) ", with: "\(expansion) ", options: [.caseInsensitive, .regularExpression])
                    .replacingOccurrences(of: " \(abbrev)$", with: " \(expansion)", options: [.caseInsensitive, .regularExpression])
                if expanded != query {
                    queries.append(expanded)
                }
            }
        }
        
        // 嘗試添加常見的景點類型前綴詞
        let prefixesToAdd = ["the "]
        for prefix in prefixesToAdd {
            if !lowercaseQuery.hasPrefix(prefix) {
                let withPrefix = prefix + query
                queries.append(withPrefix)
            }
        }
        
        return queries
    }
    
    // MARK: - 公共方法
    
    func refresh() {
        loadWikipediaData()
    }
    
    func updateAttraction(name: String, address: String? = nil, coordinate: CLLocationCoordinate2D? = nil) {
        guard name != attractionName else { return }
        
        self.attractionName = name
        self.attractionAddress = address
        self.attractionCoordinate = coordinate
        
        if let address = address {
        }
        if let coord = coordinate {
        }
        
        // 重置狀態
        self.wikipediaTitle = ""
        self.wikipediaSummary = ""
        self.wikipediaThumbnailURL = nil
        self.errorMessage = nil
        
        loadWikipediaData()
    }
    
    // 主體詞提取（中英文常見地理詞尾）
    private func extractMainPlaceName(_ name: String) -> String {
        let suffixes = ["泳灘", "沙灘", "碼頭", "廣場", "車站", "公園", "中心", "海灘", "Beach", "Pier", "Square", "Station", "Park", "Center", "Centre"]
        var main = name
        for suffix in suffixes {
            if main.hasSuffix(suffix) {
                main = String(main.dropLast(suffix.count))
            }
        }
        return main.trimmingCharacters(in: .whitespaces)
    }
    
    // 主體詞分詞交集（忽略常見前綴/類型/連接詞）
    private func mainWords(_ name: String) -> Set<String> {
        let ignoreWords = [
            "congregation", "temple", "church", "mosque", "cathedral", "synagogue", "school", "museum", "gallery", "park", "beach", "pier", "square", "station", "center", "centre", "hall", "library", "mosque", "shrine", "hotel", "restaurant", "palace", "tower", "bridge", "garden", "market", "plaza", "avenue", "road", "street", "of", "the", "at", "in", "on", "and", "de", "la", "le", "el", "saint", "st", "san", "santa"
        ]
        return Set(
            name
                .lowercased()
                .components(separatedBy: CharacterSet(charactersIn: " -_,.()[]{}'\"/\\"))
                .filter { !$0.isEmpty && !ignoreWords.contains($0) }
        )
    }
    
    // MARK: - 分階段景點搜尋功能
    
    /// 分階段搜尋景點 - 從0-2km開始，逐步擴展到20km
    /// - Parameters:
    ///   - userLocation: 用戶當前位置
    ///   - attractionsListVM: 景點列表視圖模型
    ///   - attractionsManagementVM: 景點管理視圖模型
    /// - Returns: 搜尋到的景點列表
    func performStagedAttractionSearch(
        userLocation: CLLocationCoordinate2D,
        attractionsListVM: AttractionsListViewModel,
        attractionsManagementVM: AttractionsManagementViewModel
    ) async -> [TemplateMemoryModel] {
        
        var allAttractions: [TemplateMemoryModel] = []
        let searchStages = [
            (start: 0, end: 2000, label: "0-2km"),
            (start: 2000, end: 4000, label: "2-4km"),
            (start: 4000, end: 6000, label: "4-6km"),
            (start: 6000, end: 8000, label: "6-8km"),
            (start: 8000, end: 10000, label: "8-10km"),
            (start: 10000, end: 12000, label: "10-12km"),
            (start: 12000, end: 14000, label: "12-14km"),
            (start: 14000, end: 16000, label: "14-16km"),
            (start: 16000, end: 18000, label: "16-18km"),
            (start: 18000, end: 20000, label: "18-20km")
        ]
        
        for stage in searchStages {
            // 檢查是否已達到50個景點限制
            if attractionsListVM.hasReachedMaxLimit {
                break
            }
            
            // 1. 搜尋該階段的景點
            let stageAttractions = await searchAttractionsInRange(
                userLocation: userLocation,
                minDistance: stage.start,
                maxDistance: stage.end,
                stageLabel: stage.label
            )
            
            // 2. 過濾出需要的數量
            let remainingCapacity = attractionsListVM.remainingCapacity
            let limitedStageAttractions = Array(stageAttractions.prefix(remainingCapacity))
            
            // 3. 處理Wikipedia匹配
            let processedAttractions = await processWikipediaMatching(
                attractions: limitedStageAttractions,
                attractionsManagementVM: attractionsManagementVM
            )
            
            // 4. 累計到總列表
            allAttractions = attractionsListVM.cumulativeProcess(
                processedAttractions,
                with: allAttractions
            )
            
            // 如果達到限制，停止搜尋
            if attractionsListVM.hasReachedMaxLimit {
                break
            }
        }
        
        return allAttractions
    }
    
    /// 在指定距離範圍內搜尋景點
    private func searchAttractionsInRange(
        userLocation: CLLocationCoordinate2D,
        minDistance: Int,
        maxDistance: Int,
        stageLabel: String
    ) async -> [TemplateMemoryModel] {
        
        // 使用現有的NearbyAttractionsService搜尋邏輯
        let searchRadius = Double(maxDistance)
        let region = MKCoordinateRegion(
            center: userLocation,
            latitudinalMeters: searchRadius * 2,
            longitudinalMeters: searchRadius * 2
        )
        
        var attractions: [TemplateMemoryModel] = []
        
        // 搜尋關鍵詞 - 使用高效率的旅遊景點關鍵詞
        let keywords = [
            "tourist attraction", "landmark", "museum", "park", "temple",
            "historic site", "cultural center", "famous restaurant", "shopping mall",
            "viewpoint", "beach", "botanical garden", "art gallery", "monument"
        ]
        
        // 限制每個關鍵詞的結果數量，避免過多資料
        let maxResultsPerKeyword = 10
        
        for keyword in keywords {
            let keywordResults = await searchSingleKeyword(
                keyword: keyword,
                region: region,
                userLocation: userLocation,
                minDistance: minDistance,
                maxDistance: maxDistance,
                stageLabel: stageLabel
            )
            
            // 限制結果數量
            let limitedResults = Array(keywordResults.prefix(maxResultsPerKeyword))
            attractions.append(contentsOf: limitedResults)
        }
        
        // 去重和按距離排序
        let uniqueAttractions = removeDuplicatesByLocation(attractions)
        let sortedAttractions = uniqueAttractions.sorted { $0.distanceFromUser < $1.distanceFromUser }
        
        return sortedAttractions
    }
    
    /// 搜尋單一關鍵詞
    private func searchSingleKeyword(
        keyword: String,
        region: MKCoordinateRegion,
        userLocation: CLLocationCoordinate2D,
        minDistance: Int,
        maxDistance: Int,
        stageLabel: String
    ) async -> [TemplateMemoryModel] {
        return await withCheckedContinuation { continuation in
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = keyword
            request.region = region
            request.resultTypes = [.pointOfInterest, .address]
            
            let search = MKLocalSearch(request: request)
            search.start { response, error in
                if let error = error {
                    continuation.resume(returning: [])
                    return
                }
                
                guard let response = response else {
                    continuation.resume(returning: [])
                    return
                }
                
                let userLocationCL = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)
                var results: [TemplateMemoryModel] = []
                
                for item in response.mapItems {
                    let itemLocation = CLLocation(
                        latitude: item.placemark.coordinate.latitude,
                        longitude: item.placemark.coordinate.longitude
                    )
                    let distance = userLocationCL.distance(from: itemLocation)
                    
                    // 過濾距離範圍
                    if distance >= Double(minDistance) && distance <= Double(maxDistance) {
                        let templateModel = TemplateMemoryModel(
                            names: ["en": item.name ?? "Unknown"],
                            addresses: ["en": self.formatAddress(item.placemark)],
                            latitude: item.placemark.coordinate.latitude,
                            longitude: item.placemark.coordinate.longitude,
                            descriptions: nil,
                            source: nil,
                            distanceFromUser: distance,
                            searchRadius: stageLabel,
                            processingStage: .extracted,
                            hasWikipediaData: false
                        )
                        results.append(templateModel)
                    }
                }
                
                continuation.resume(returning: results)
            }
        }
    }
    
    /// 處理Wikipedia匹配
    private func processWikipediaMatching(
        attractions: [TemplateMemoryModel],
        attractionsManagementVM: AttractionsManagementViewModel
    ) async -> [TemplateMemoryModel] {
        
        var processedAttractions: [TemplateMemoryModel] = []
        
        for attraction in attractions {
            // 取得景點名稱
            guard let attractionName = attraction.names["en"] else {
                continue
            }
            
            // 使用三維搜尋方式匹配Wikipedia
            let matchResult = await attractionsManagementVM.searchWikipediaWithThreeDimensionalMatching(
                attractionName: attractionName,
                attractionAddress: attraction.addresses?["en"],
                attractionCoordinate: CLLocationCoordinate2D(
                    latitude: attraction.latitude,
                    longitude: attraction.longitude
                )
            )
            
            // 更新景點資料
            if let result = matchResult {
                let updatedAttraction = TemplateMemoryModel(
                    names: ["en": result.title],
                    addresses: attraction.addresses,
                    latitude: attraction.latitude,
                    longitude: attraction.longitude,
                    descriptions: ["en": result.summary],
                    source: result.title,
                    distanceFromUser: attraction.distanceFromUser,
                    searchRadius: attraction.searchRadius,
                    processingStage: .wikipediaMatched,
                    hasWikipediaData: true
                )
                processedAttractions.append(updatedAttraction)
            }
        }
        
        return processedAttractions
    }
    
    /// 格式化地址
    private func formatAddress(_ placemark: MKPlacemark) -> String {
        var addressComponents: [String] = []
        
        if let name = placemark.name {
            addressComponents.append(name)
        }
        if let thoroughfare = placemark.thoroughfare {
            addressComponents.append(thoroughfare)
        }
        if let locality = placemark.locality {
            addressComponents.append(locality)
        }
        if let administrativeArea = placemark.administrativeArea {
            addressComponents.append(administrativeArea)
        }
        if let country = placemark.country {
            addressComponents.append(country)
        }
        
        return addressComponents.joined(separator: ", ")
    }
    
    /// 基於位置去重
    private func removeDuplicatesByLocation(_ attractions: [TemplateMemoryModel]) -> [TemplateMemoryModel] {
        var uniqueAttractions: [TemplateMemoryModel] = []
        
        for attraction in attractions {
            let isDuplicate = uniqueAttractions.contains { existing in
                let distance = CLLocation(latitude: existing.latitude, longitude: existing.longitude)
                    .distance(from: CLLocation(latitude: attraction.latitude, longitude: attraction.longitude))
                return distance < 100 // 100米內視為重複
            }
            
            if !isDuplicate {
                uniqueAttractions.append(attraction)
            }
        }
        
        return uniqueAttractions
    }
} 