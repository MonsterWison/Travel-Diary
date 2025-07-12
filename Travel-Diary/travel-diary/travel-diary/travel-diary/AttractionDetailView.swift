import SwiftUI

struct AttractionDetailView: View {
    @ObservedObject var viewModel: AttractionDetailViewModel
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // 照片
                    ZStack {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .frame(height: 220)
                            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
                        if let url = viewModel.photoURL {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .empty:
                                    ProgressView()
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(height: 220)
                                        .clipped()
                                        .cornerRadius(24)
                                case .failure:
                                    Image(systemName: "photo")
                                        .font(.largeTitle)
                                        .foregroundColor(.gray)
                                @unknown default:
                                    EmptyView()
                                }
                            }
                        } else {
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundColor(.gray)
                        }
                    }
                    .frame(height: 220)
                    .padding(.top, 8)

                    // 基本資訊區塊
                    VStack(alignment: .leading, spacing: 16) {
                        // 名稱
                        Text(viewModel.displayTitle.isEmpty ? viewModel.name : viewModel.displayTitle)
                            .font(.largeTitle.bold())
                            .foregroundColor(.primary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                        
                        // 距離與位置
                        HStack(spacing: 16) {
                            if !viewModel.distance.isEmpty {
                                Label(viewModel.distance, systemImage: "location")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            if !viewModel.address.isEmpty {
                                Label(viewModel.address, systemImage: "mappin.and.ellipse")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.bottom, 8)

                    // 詳細介紹
                    if !viewModel.description.isEmpty || viewModel.isWikiSearching {
                        InfoCard(title: "景點介紹", icon: "text.quote") {
                            if viewModel.isWikiSearching {
                                HStack {
                                    Spacer()
                                    ProgressView("搜尋中…")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                        .padding(.vertical, 24)
                                    Spacer()
                                }
                            } else {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(viewModel.descriptionTextOnly)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                        .multilineTextAlignment(.leading)
                                    
                                    if let source = viewModel.descriptionSource, !source.isEmpty {
                                        Divider()
                                        HStack {
                                            Text("資料來源：")
                                                .font(.footnote)
                                                .foregroundColor(.secondary)
                                            Text(source)
                                                .font(.footnote)
                                                .foregroundColor(.blue)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // 維基百科詳細資訊
                    if !viewModel.wikiType.isEmpty {
                        VStack(spacing: 16) {
                            // 頁面資訊
                            InfoCard(title: "頁面資訊", icon: "doc.text") {
                                VStack(alignment: .leading, spacing: 8) {
                                    InfoRow(label: "頁面類型", value: viewModel.wikiType)
                                    InfoRow(label: "頁面ID", value: "\(viewModel.pageid)")
                                    InfoRow(label: "語言", value: viewModel.lang.uppercased())
                                    InfoRow(label: "修訂版本", value: viewModel.revision)
                                    if !viewModel.timestamp.isEmpty {
                                        InfoRow(label: "更新時間", value: formatTimestamp(viewModel.timestamp))
                                    }
                                }
                            }
                            
                            // 標題資訊
                            if !viewModel.titles.isEmpty || !viewModel.normalizedTitle.isEmpty {
                                InfoCard(title: "標題資訊", icon: "tag") {
                                    VStack(alignment: .leading, spacing: 8) {
                                        if let canonical = viewModel.titles["canonical"] as? String {
                                            InfoRow(label: "標準標題", value: canonical)
                                        }
                                        if let normalized = viewModel.titles["normalized"] as? String {
                                            InfoRow(label: "正規化標題", value: normalized)
                                        }
                                        if let display = viewModel.titles["display"] as? String {
                                            InfoRow(label: "顯示標題", value: display)
                                        }
                                        if !viewModel.normalizedTitle.isEmpty {
                                            InfoRow(label: "API正規化標題", value: viewModel.normalizedTitle)
                                        }
                                    }
                                }
                            }
                            
                            // 座標資訊
                            if !viewModel.coordinates.isEmpty {
                                InfoCard(title: "地理位置", icon: "location.circle") {
                                    VStack(alignment: .leading, spacing: 8) {
                                        if let lat = viewModel.coordinates["lat"] as? String {
                                            InfoRow(label: "緯度", value: lat)
                                        } else if let lat = viewModel.coordinates["lat"] as? Double {
                                            InfoRow(label: "緯度", value: String(format: "%.6f", lat))
                                        }
                                        if let lon = viewModel.coordinates["lon"] as? String {
                                            InfoRow(label: "經度", value: lon)
                                        } else if let lon = viewModel.coordinates["lon"] as? Double {
                                            InfoRow(label: "經度", value: String(format: "%.6f", lon))
                                        }
                                    }
                                }
                            }
                            
                            // 連結資訊
                            if !viewModel.contentUrls.isEmpty {
                                InfoCard(title: "相關連結", icon: "link") {
                                    VStack(alignment: .leading, spacing: 8) {
                                        if let desktop = viewModel.contentUrls["desktop"] as? [String: Any],
                                           let page = desktop["page"] as? String {
                                            InfoRow(label: "桌面版", value: page, isLink: true)
                                        }
                                        if let mobile = viewModel.contentUrls["mobile"] as? [String: Any],
                                           let page = mobile["page"] as? String {
                                            InfoRow(label: "行動版", value: page, isLink: true)
                                        }
                                    }
                                }
                            }
                            
                            // 其他資訊
                            if !viewModel.wikibaseItem.isEmpty || !viewModel.pageProps.isEmpty || !viewModel.extractHtml.isEmpty {
                                InfoCard(title: "其他資訊", icon: "info.circle") {
                                    VStack(alignment: .leading, spacing: 8) {
                                        if !viewModel.wikibaseItem.isEmpty {
                                            InfoRow(label: "Wikibase項目", value: viewModel.wikibaseItem)
                                        }
                                        if let wikibaseItem = viewModel.pageProps["wikibase_item"] as? String {
                                            InfoRow(label: "Wikibase ID", value: wikibaseItem)
                                        }
                                        if !viewModel.tid.isEmpty {
                                            InfoRow(label: "TID", value: viewModel.tid)
                                        }
                                        if !viewModel.dir.isEmpty {
                                            InfoRow(label: "文字方向", value: viewModel.dir)
                                        }
                                    }
                                }
                            }
                            
                            // 原始圖片資訊
                            if !viewModel.originalImage.isEmpty {
                                InfoCard(title: "原始圖片", icon: "photo") {
                                    VStack(alignment: .leading, spacing: 8) {
                                        if let source = viewModel.originalImage["source"] as? String {
                                            InfoRow(label: "圖片來源", value: source, isLink: true)
                                        }
                                        if let width = viewModel.originalImage["width"] as? Int {
                                            InfoRow(label: "寬度", value: "\(width)px")
                                        }
                                        if let height = viewModel.originalImage["height"] as? Int {
                                            InfoRow(label: "高度", value: "\(height)px")
                                        }
                                    }
                                }
                            }
                            
                            // HTML 摘要（如果與純文字摘要不同）
                            if !viewModel.extractHtml.isEmpty && viewModel.extractHtml != viewModel.descriptionTextOnly {
                                InfoCard(title: "HTML 摘要", icon: "doc.text.fill") {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(viewModel.extractHtml)
                                            .font(.subheadline)
                                            .foregroundColor(.primary)
                                            .multilineTextAlignment(.leading)
                                            .lineLimit(nil)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(24)
            }

            // 返回按鈕
            Button(action: { presentationMode.wrappedValue.dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.title2.bold())
                    .foregroundColor(.primary)
                    .padding(12)
                    .background(.ultraThinMaterial, in: Circle())
                    .shadow(radius: 2)
            }
            .padding(.top, 32)
            .padding(.leading, 16)
        }
        .background(Color(.systemBackground))
        .onAppear {
            viewModel.fetchDetailIfNeeded()
            viewModel.onFallbackWebSearch = {
                print("[Fallback] View 層收到 fallback，關閉詳情頁並通知主視圖")
                presentationMode.wrappedValue.dismiss()
                NotificationCenter.default.post(name: NSNotification.Name("AttractionFallbackWebSearch"), object: viewModel.name)
            }
        }
        .onDisappear {
            viewModel.onFallbackWebSearch = nil
        }
        .overlay(
            Group {
                if viewModel.isLoading {
                    ZStack {
                        Color.black.opacity(0.08).ignoresSafeArea()
                        ProgressView("正在載入最新資料...")
                            .font(.title3)
                            .padding(32)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                } else if let error = viewModel.error {
                    ZStack {
                        Color.black.opacity(0.08).ignoresSafeArea()
                        VStack(spacing: 16) {
                            Text(error)
                                .font(.title3)
                                .foregroundColor(.red)
                            if viewModel.isLoading == false && viewModel.error != nil {
                                ProgressView("正在自動搜尋其他資料來源...")
                                    .font(.body)
                            }
                        }
                        .padding(32)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
        )
    }
    
    private func formatTimestamp(_ timestamp: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: timestamp) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            displayFormatter.timeStyle = .short
            displayFormatter.locale = Locale(identifier: "zh_TW")
            return displayFormatter.string(from: date)
        }
        return timestamp
    }
}

// MARK: - 輔助元件
struct InfoCard<Content: View>: View {
    let title: String
    let icon: String
    let content: Content
    
    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(.blue)
                Text(title)
                    .font(.title3.bold())
                    .accessibilityAddTraits(.isHeader)
            }
            .padding(.bottom, 4)
            
            content
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    var isLink: Bool = false
    
    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            
            Text(value)
                .font(.subheadline)
                .foregroundColor(isLink ? .blue : .primary)
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
            
            Spacer()
        }
    }
} 