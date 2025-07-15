//
//  travel_diaryApp.swift
//  travel-diary
//
//  Created by Wilson Ho on 24/6/2025.
//

import SwiftUI

@main
struct travel_diaryApp: App {
    init() {
        // 應用程式啟動時初始化 Wikipedia 緩存
        setupWikipediaCache()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
    
    private func setupWikipediaCache() {
        // 清理過期的緩存項目
        WikipediaCache.shared.cleanExpiredItems()
    }
}
