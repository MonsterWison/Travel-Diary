//
//  travel_diaryApp.swift
//  travel-diary
//
//  Created by Wilson Ho on 24/6/2025.
//

import SwiftUI

@main
struct travel_diaryApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    #if DEBUG
                    print("🎯 應用啟動完成")
                    #endif
                }
        }
    }
}
