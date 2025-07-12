# Stage 3.6.2 Restore Point

- 修正 fallback WebView（Google/Baidu）初次顯示空白問題，加入 0.1 秒 async delay，符合 Apple HIG/MVVM/MapKit/SwiftUI 實踐。
- WebView 載入失敗時顯示明確錯誤訊息，避免全白畫面。
- 防止多次 fallback，確保 UI 穩定。
- 經測試，移動手機後 WebView 可正常顯示。
- 已同步所有程式碼與說明文件。 