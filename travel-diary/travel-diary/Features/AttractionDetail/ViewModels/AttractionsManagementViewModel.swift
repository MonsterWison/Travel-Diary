import Foundation

class AttractionsManagementViewModel: ObservableObject {
    @Published var compareModel: CompareModel?
    @Published var attractionCandidates: [AttractionCache] = []
    @Published var bestMatch: AttractionCache?
    
    // MARK: - Google Search 三維搜尋系統核心
    
    // 設定比對依據
    func setCompareModel(_ model: CompareModel) {
        self.compareModel = model
    }

    // 載入所有候選景點
    func setAttractionCandidates(_ candidates: [AttractionCache]) {
        self.attractionCandidates = candidates
        self.bestMatch = findBestMatchWithAdvanced3DSearch()
    }
    
    // MARK: - Google Search 三維搜尋系統已整合到正常流程中

    // MARK: - 語意維度 (Semantic Dimension) - 50% 權重
    
    // 進階語意分析：多語言同義詞擴展
    private func expandQueryWithSynonyms(_ query: String) -> Set<String> {
        let synonyms: [String: [String]] = [
            "temple": ["shrine", "monastery", "pagoda", "sanctuary", "cathedral", "church"],
            "museum": ["gallery", "exhibition", "collection", "center", "centre"],
            "beach": ["shore", "coast", "bay", "waterfront", "seaside"],
            "square": ["plaza", "piazza", "place", "courtyard", "park"],
            "station": ["terminal", "depot", "stop", "hub"],
            "market": ["bazaar", "marketplace", "mart", "fair"],
            "tower": ["spire", "minaret", "campanile", "steeple"],
            "bridge": ["span", "crossing", "viaduct", "overpass"],
            "garden": ["park", "botanical", "arboretum", "conservatory"],
            "palace": ["castle", "mansion", "residence", "manor"],
            "library": ["archive", "repository", "collection", "center"],
            "hospital": ["clinic", "medical", "health", "care"],
            "university": ["college", "school", "academy", "institute"],
            "restaurant": ["cafe", "bistro", "eatery", "dining", "kitchen"],
            "hotel": ["inn", "lodge", "resort", "accommodation", "guest"],
            "synagogue": ["temple", "shul", "congregation", "beth"],
            "mosque": ["masjid", "islamic", "muslim", "prayer"],
            "church": ["cathedral", "chapel", "basilica", "abbey"],
            "island": ["isle", "archipelago", "atoll", "key"],
            "mountain": ["peak", "summit", "hill", "mount", "ridge"],
            "lake": ["pond", "reservoir", "lagoon", "loch"],
            "river": ["stream", "creek", "waterway", "channel"],
            "forest": ["woods", "woodland", "jungle", "grove"],
            "desert": ["dunes", "sahara", "wilderness", "badlands"]
        ]
        
        var expanded = Set([query.lowercased()])
        let words = query.lowercased().components(separatedBy: CharacterSet(charactersIn: " -_,.()[]{}'\"/\\"))
        
        for word in words {
            if let syns = synonyms[word] {
                expanded.formUnion(syns)
            }
        }
        
        return expanded
    }
    
    // 進階主體詞提取（支援多語言）
    private func extractMainWords(_ name: String) -> Set<String> {
        let ignoreWords = [
            // 英文停用詞
            "congregation", "temple", "church", "mosque", "cathedral", "synagogue", 
            "school", "museum", "gallery", "park", "beach", "pier", "square", "station", 
            "center", "centre", "hall", "library", "shrine", "hotel", "restaurant", 
            "palace", "tower", "bridge", "garden", "market", "plaza", "avenue", "road", 
            "street", "of", "the", "at", "in", "on", "and", "de", "la", "le", "el", 
            "saint", "st", "san", "santa", "new", "old", "big", "small", "great", "grand",
            "north", "south", "east", "west", "upper", "lower", "first", "second", "third",
            "memorial", "national", "international", "public", "private", "main", "central",
            "historic", "historical", "ancient", "modern", "royal", "imperial",
            // 中文停用詞
            "的", "了", "在", "是", "我", "有", "和", "就", "不", "人", "都", "一", "個",
            "上", "也", "很", "到", "說", "要", "去", "你", "會", "着", "沒有", "看", "好",
            "自己", "這樣", "那個", "什麼", "可以", "他們", "但是", "還是", "只是", "這個",
            "寺廟", "博物館", "公園", "海灘", "廣場", "車站", "中心", "圖書館", "酒店",
            "餐廳", "宮殿", "塔", "橋", "花園", "市場", "大街", "道路", "街道", "紀念",
            "國家", "國際", "公共", "私人", "主要", "中央", "歷史", "古代", "現代", "皇家",
            // 其他語言常見詞
            "casa", "iglesia", "museo", "parque", "plaza", "estacion", "centro", "biblioteca",
            "maison", "eglise", "musee", "parc", "place", "gare", "centre", "bibliotheque"
        ]
        
        return Set(
            name
                .lowercased()
                .components(separatedBy: CharacterSet(charactersIn: " -_,.()[]{}'\"/\\"))
                .filter { !$0.isEmpty && $0.count > 2 && !ignoreWords.contains($0) }
        )
    }
    
    // 進階語意相似度計算（模擬 BERT 向量匹配）
    private func calculateSemanticSimilarity(_ query: String, _ candidate: String) -> Double {
        let queryExpanded = expandQueryWithSynonyms(query)
        let candidateExpanded = expandQueryWithSynonyms(candidate)
        
        let queryWords = extractMainWords(query)
        let candidateWords = extractMainWords(candidate)
        
        // 1. 主詞交集匹配（≥2 個交集直接通過）
        let intersection = queryWords.intersection(candidateWords)
        if intersection.count >= 2 {
            return 0.95 // 高度相似
        }
        
        // 2. 同義詞擴展匹配
        let synonymIntersection = queryExpanded.intersection(candidateExpanded)
        let synonymScore = Double(synonymIntersection.count) / Double(queryExpanded.union(candidateExpanded).count)
        
        // 3. Jaccard 相似度
        let jaccard = Double(intersection.count) / Double(queryWords.union(candidateWords).count)
        
        // 4. 改進的 Levenshtein 距離
        let levDistance = levenshteinDistance(query.lowercased(), candidate.lowercased())
        let maxLen = max(query.count, candidate.count)
        let levScore = maxLen > 0 ? 1.0 - Double(levDistance) / Double(maxLen) : 0.0
        
        // 5. 字符 N-gram 相似度
        let ngramScore = calculateNGramSimilarity(query, candidate)
        
        // 6. 語言檢測和多語言匹配
        let multilingualScore = calculateMultilingualSimilarity(query, candidate)
        
        // 綜合語意分數
        return max(
            synonymScore * 0.3 + 
            jaccard * 0.25 + 
            levScore * 0.2 + 
            ngramScore * 0.15 + 
            multilingualScore * 0.1,
            intersection.count > 0 ? 0.6 : 0.0
        )
    }
    
    // N-gram 相似度計算
    private func calculateNGramSimilarity(_ str1: String, _ str2: String, n: Int = 3) -> Double {
        func getNGrams(_ str: String, _ n: Int) -> Set<String> {
            let chars = Array(str.lowercased())
            guard chars.count >= n else { return Set([str.lowercased()]) }
            var ngrams = Set<String>()
            for i in 0...(chars.count - n) {
                let ngram = String(chars[i..<i+n])
                ngrams.insert(ngram)
            }
            return ngrams
        }
        
        let ngrams1 = getNGrams(str1, n)
        let ngrams2 = getNGrams(str2, n)
        let intersection = ngrams1.intersection(ngrams2)
        let union = ngrams1.union(ngrams2)
        
        return union.isEmpty ? 0.0 : Double(intersection.count) / Double(union.count)
    }
    
    // 多語言相似度計算
    private func calculateMultilingualSimilarity(_ query: String, _ candidate: String) -> Double {
        // 檢查是否包含中文字符
        let chineseRegex = try? NSRegularExpression(pattern: "[\\u4e00-\\u9fff]", options: [])
        let queryHasChinese = chineseRegex?.firstMatch(in: query, options: [], range: NSRange(location: 0, length: query.count)) != nil
        let candidateHasChinese = chineseRegex?.firstMatch(in: candidate, options: [], range: NSRange(location: 0, length: candidate.count)) != nil
        
        if queryHasChinese && candidateHasChinese {
            // 中文匹配邏輯
            return calculateChineseSemanticSimilarity(query, candidate)
        }
        
        return 0.0
    }
    
    // 中文語意相似度
    private func calculateChineseSemanticSimilarity(_ query: String, _ candidate: String) -> Double {
        let chineseCommonWords = [
            "寺": ["寺廟", "廟", "庵", "觀", "院"],
            "博物館": ["展覽館", "美術館", "文物館", "紀念館"],
            "公園": ["花園", "園林", "綠地", "廣場"],
            "海灘": ["沙灘", "海岸", "海邊", "濱海"],
            "廣場": ["plaza", "square", "中心", "地帶"],
            "車站": ["站", "terminal", "depot", "交通"],
            "中心": ["center", "centre", "hub", "核心"],
            "圖書館": ["書館", "閱覽室", "文獻館", "典藏"],
            "酒店": ["飯店", "旅館", "賓館", "住宿"],
            "餐廳": ["飯店", "食堂", "茶樓", "酒樓"]
        ]
        
        for (key, synonyms) in chineseCommonWords {
            if query.contains(key) || synonyms.contains(where: { query.contains($0) }) {
                if candidate.contains(key) || synonyms.contains(where: { candidate.contains($0) }) {
                    return 0.8
                }
            }
        }
        
        return 0.0
    }
    
    // MARK: - 地理維度 (Geographic Dimension) - 40% 權重
    
    // 進階地理相似度計算
    private func calculateGeographicSimilarity(_ compareModel: CompareModel, _ candidate: AttractionCache) -> Double {
        let distance = calculateDistance(
            lat1: compareModel.latitude, lon1: compareModel.longitude,
            lat2: candidate.latitude, lon2: candidate.longitude
        )
        
        // 1. 基礎距離評分（非線性）
        let baseScore: Double
        if distance < 0.1 {
            baseScore = 1.0 // 100m 內完美匹配
        } else if distance < 0.5 {
            baseScore = 0.95 // 500m 內高度匹配
        } else if distance < 1.0 {
            baseScore = 0.85 // 1km 內良好匹配
        } else if distance < 2.0 {
            baseScore = 0.7 // 2km 內可接受
        } else if distance < 5.0 {
            baseScore = 0.5 // 5km 內邊緣匹配
        } else if distance < 10.0 {
            baseScore = 0.3 // 10km 內低匹配
        } else {
            baseScore = max(0.0, 0.2 - distance / 100.0) // 遠距離衰減
        }
        
        // 2. 城市/區域匹配加成
        let regionBonus = calculateRegionSimilarity(compareModel, candidate)
        
        // 3. 景點類型距離容忍度調整
        let typeDistanceTolerance = getDistanceToleranceForType(candidate)
        
        // 4. 人口密度調整（市中心 vs 郊區）
        let densityAdjustment = calculateDensityAdjustment(compareModel, candidate)
        
        return min(1.0, baseScore + regionBonus + typeDistanceTolerance + densityAdjustment)
    }
    
    // 區域相似度計算
    private func calculateRegionSimilarity(_ compareModel: CompareModel, _ candidate: AttractionCache) -> Double {
        // 這裡可以加入城市、區域、國家的匹配邏輯
        // 例如：同一個城市 +0.1，同一個區域 +0.05
        return 0.0 // 暫時返回 0，可根據需要實現
    }
    
    // 根據景點類型調整距離容忍度
    private func getDistanceToleranceForType(_ candidate: AttractionCache) -> Double {
        let name = candidate.names["en"]?.lowercased() ?? ""
        
        // 不同類型景點的距離容忍度
        if name.contains("airport") || name.contains("station") {
            return 0.05 // 交通樞紐允許更大距離
        } else if name.contains("museum") || name.contains("gallery") {
            return 0.03 // 博物館通常位置精確
        } else if name.contains("park") || name.contains("beach") {
            return 0.02 // 公園海灘可能範圍較大
        } else if name.contains("restaurant") || name.contains("shop") {
            return 0.01 // 商店餐廳位置精確
        }
        
        return 0.0
    }
    
    // 人口密度調整
    private func calculateDensityAdjustment(_ compareModel: CompareModel, _ candidate: AttractionCache) -> Double {
        // 在市中心，距離容忍度較低
        // 在郊區，距離容忍度較高
        // 這裡可以根據座標判斷是否在市中心
        return 0.0 // 暫時返回 0，可根據需要實現
    }
    
    // MARK: - 類型/屬性維度 (Type/Attribute Dimension) - 10% 權重
    
    // 景點類型相似度計算
    private func calculateTypeSimilarity(_ compareModel: CompareModel, _ candidate: AttractionCache) -> Double {
        let queryName = compareModel.names["en"]?.lowercased() ?? compareModel.names.values.first?.lowercased() ?? ""
        let candidateName = candidate.names["en"]?.lowercased() ?? candidate.names.values.first?.lowercased() ?? ""
        
        // 景點類型分類
        let categories: [String: [String]] = [
            "religious": ["temple", "church", "mosque", "synagogue", "cathedral", "shrine", "monastery", "abbey", "basilica", "chapel"],
            "cultural": ["museum", "gallery", "theater", "opera", "concert", "cultural", "art", "exhibition"],
            "recreational": ["park", "garden", "zoo", "aquarium", "amusement", "playground", "recreation"],
            "natural": ["beach", "lake", "mountain", "forest", "river", "waterfall", "cave", "island", "bay"],
            "transportation": ["station", "airport", "port", "terminal", "depot", "hub"],
            "commercial": ["market", "mall", "shopping", "store", "restaurant", "hotel", "cafe"],
            "historical": ["castle", "palace", "fort", "monument", "memorial", "historic", "ancient", "heritage"],
            "educational": ["university", "college", "school", "library", "institute", "academy"],
            "medical": ["hospital", "clinic", "medical", "health", "pharmacy"],
            "government": ["city hall", "courthouse", "embassy", "consulate", "government", "municipal"],
            "sports": ["stadium", "arena", "gym", "sports", "field", "court", "track"],
            "entertainment": ["cinema", "theater", "club", "bar", "entertainment", "nightlife"]
        ]
        
        var queryCategory = "unknown"
        var candidateCategory = "unknown"
        
        // 找出查詢的類型
        for (category, keywords) in categories {
            if keywords.contains(where: { queryName.contains($0) }) {
                queryCategory = category
                break
            }
        }
        
        // 找出候選的類型
        for (category, keywords) in categories {
            if keywords.contains(where: { candidateName.contains($0) }) {
                candidateCategory = category
                break
            }
        }
        
        // 計算類型相似度
        if queryCategory == candidateCategory && queryCategory != "unknown" {
            return 1.0 // 完全匹配
        } else if queryCategory != "unknown" && candidateCategory != "unknown" {
            // 相關類型的部分匹配
            let relatedCategories: [String: [String]] = [
                "religious": ["historical", "cultural"],
                "cultural": ["historical", "educational"],
                "recreational": ["natural", "entertainment"],
                "natural": ["recreational"],
                "historical": ["cultural", "religious"],
                "educational": ["cultural"]
            ]
            
            if let related = relatedCategories[queryCategory], related.contains(candidateCategory) {
                return 0.6 // 相關類型
            }
        }
        
        return 0.0 // 無匹配
    }
    
    // MARK: - 進階三維搜尋主算法
    
    // Google Search 風格的三維搜尋匹配
    private func findBestMatchWithAdvanced3DSearch() -> AttractionCache? {
        guard let compareModel = compareModel else { return nil }
        
        var bestScore: Double = 0.0
        var bestCandidate: AttractionCache? = nil
        var scoringResults: [(AttractionCache, Double, String)] = []
        
        for candidate in attractionCandidates {
            // 1. 語意維度分析 (50% 權重)
            let queryText = compareModel.names["en"] ?? compareModel.names.values.first ?? ""
            let candidateText = candidate.names["en"] ?? candidate.names.values.first ?? ""
            let semanticScore = calculateSemanticSimilarity(queryText, candidateText)
            
            // 2. 地理維度分析 (40% 權重)
            let geographicScore = calculateGeographicSimilarity(compareModel, candidate)
            
            // 3. 類型/屬性維度分析 (10% 權重)
            let typeScore = calculateTypeSimilarity(compareModel, candidate)
            
            // 4. 動態權重調整（根據查詢類型）
            let weights = calculateDynamicWeights(queryText, candidateText)
            
            // 5. 綜合評分
            let totalScore = weights.semantic * semanticScore + 
                           weights.geographic * geographicScore + 
                           weights.type * typeScore
            
            // 6. 置信度過濾
            let confidenceThreshold = calculateConfidenceThreshold(queryText)
            
            // 記錄評分結果
            let scoreBreakdown = "S:\(String(format: "%.2f", semanticScore)) G:\(String(format: "%.2f", geographicScore)) T:\(String(format: "%.2f", typeScore)) = \(String(format: "%.2f", totalScore))"
            scoringResults.append((candidate, totalScore, scoreBreakdown))
            
            if totalScore > bestScore && totalScore > confidenceThreshold {
                bestScore = totalScore
                bestCandidate = candidate
            }
        }
        
        // 7. 調試輸出（可選）
        printScoringResults(scoringResults, bestScore: bestScore)
        
        return bestCandidate
    }
    
    // 動態權重計算
    private func calculateDynamicWeights(_ query: String, _ candidate: String) -> (semantic: Double, geographic: Double, type: Double) {
        let queryLower = query.lowercased()
        
        // 根據查詢特徵調整權重
        if queryLower.contains("near") || queryLower.contains("nearby") {
            return (0.3, 0.6, 0.1) // 地理權重增加
        } else if queryLower.contains("type") || queryLower.contains("kind") {
            return (0.4, 0.3, 0.3) // 類型權重增加
        } else if queryLower.count > 30 {
            return (0.6, 0.3, 0.1) // 長查詢增加語意權重
        }
        
        return (0.5, 0.4, 0.1) // 預設權重
    }
    
    // 置信度門檻計算
    private func calculateConfidenceThreshold(_ query: String) -> Double {
        let queryLower = query.lowercased()
        
        // 根據查詢特徵調整門檻
        if queryLower.contains("exact") || queryLower.contains("specific") {
            return 0.85 // 精確查詢需要更高置信度
        } else if queryLower.count < 10 {
            return 0.6 // 短查詢降低門檻
        }
        
        return 0.7 // 預設門檻
    }
    
    // 調試輸出
    private func printScoringResults(_ results: [(AttractionCache, Double, String)], bestScore: Double) {
        print("=== 三維搜尋評分結果 ===")
        let sortedResults = results.sorted { $0.1 > $1.1 }
        for (index, (candidate, score, breakdown)) in sortedResults.prefix(5).enumerated() {
            let marker = score == bestScore ? "🏆" : "📍"
            print("\(marker) \(index + 1). \(candidate.names["en"] ?? "Unknown") - \(breakdown)")
        }
        print("========================")
    }
    
    // MARK: - 輔助方法
    
    // 改進的 Levenshtein 距離計算
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1Array = Array(s1)
        let s2Array = Array(s2)
        let s1Count = s1Array.count
        let s2Count = s2Array.count
        
        var matrix = Array(repeating: Array(repeating: 0, count: s2Count + 1), count: s1Count + 1)
        
        for i in 0...s1Count {
            matrix[i][0] = i
        }
        
        for j in 0...s2Count {
            matrix[0][j] = j
        }
        
        for i in 1...s1Count {
            for j in 1...s2Count {
                let cost = s1Array[i-1] == s2Array[j-1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i-1][j] + 1,      // deletion
                    matrix[i][j-1] + 1,      // insertion
                    matrix[i-1][j-1] + cost  // substitution
                )
            }
        }
        
        return matrix[s1Count][s2Count]
    }
    
    // 計算兩點間距離（Haversine 公式）
    private func calculateDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let R = 6371.0 // 地球半徑（公里）
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat/2) * sin(dLat/2) + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon/2) * sin(dLon/2)
        let c = 2 * atan2(sqrt(a), sqrt(1-a))
        return R * c
    }
    
    // MARK: - 公開方法
    
    // 比對分數門檻
    private let maxDistanceThreshold: Double = 0.5 // 公里
    
    // 回傳最佳比對結果及其距離
    func bestMatchWithScore() -> (AttractionCache, Double)? {
        guard let compare = compareModel else { return nil }
        let sortedByDistance = attractionCandidates.map { candidate in
            (candidate, calculateDistance(lat1: compare.latitude, lon1: compare.longitude, lat2: candidate.latitude, lon2: candidate.longitude))
        }.sorted { $0.1 < $1.1 }
        if let best = sortedByDistance.first {
            return best
        }
        return nil
    }
    
    // 是否有通過門檻的比對
    func hasValidMatch() -> Bool {
        if let (_, score) = bestMatchWithScore() {
            return score < maxDistanceThreshold
        }
        return false
    }
} 