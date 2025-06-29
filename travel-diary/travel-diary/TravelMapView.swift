import SwiftUI
import MapKit

/// 旅遊日誌主視圖 - 符合 HIG 設計規範
struct TravelMapView: View {
    @StateObject private var viewModel = LocationViewModel()
    @State private var showingAddPointAlert = false
    @State private var cameraPosition = MapCameraPosition.automatic
    @FocusState private var isSearchFocused: Bool
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 主地圖視圖
                mapView
                
                // HIG: 頂部搜索區域（搜索框 + 建議列表整合）
                VStack(spacing: 0) {
                    // 搜索框
                    topSearchArea
                    
                    // HIG: GPS信號警告橫幅
                    if viewModel.gpsSignalStrength.shouldShowWarning {
                        gpsWarningBanner
                    }
                    
                    // HIG: 搜索建議下拉列表（緊貼搜索框下方，不覆蓋搜索框）
                    if viewModel.showingSearchResults {
                        searchSuggestionsDropdown
                    }
                    
                    Spacer()
                }
                
                // HIG: 精簡浮動信息卡片（僅在需要時顯示）
                if !isSearchFocused && !viewModel.showingSearchResults {
                    VStack {
                        Spacer()
                            .frame(height: 100) // 為搜索區域留空間（縮小）
                        
                        HStack {
                            locationInfoCard
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Spacer()
                        }
                        
                        Spacer()
                    }
                }
                
                // HIG: 底部浮動操作按鈕
                VStack {
                    Spacer()
                    bottomActionButtons
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 34) // 考慮Home Indicator
            }
            .navigationTitle("旅遊日誌")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    menuButton
                }
            }
            .alert("需要位置權限", isPresented: $viewModel.showingLocationAlert) {
                locationPermissionAlert
            }
            .alert("添加路徑點", isPresented: $showingAddPointAlert) {
                addPointAlert
            }
        }
        .onAppear {
            setupInitialMapPosition()
        }
        .onReceive(viewModel.$region) { newRegion in
            updateCameraPosition(newRegion)
        }
    }
    
    // MARK: - HIG標準搜索區域
    private var topSearchArea: some View {
        VStack(spacing: 8) {
            // HIG規範：搜索欄使用標準設計規格
            HStack(spacing: 8) {
                // HIG規範：搜索圖標使用17pt標準大小
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.body) // iOS標準17pt
                    .fontWeight(.medium)
                
                // HIG規範：輸入框使用標準字體和符合HIG的佔位符
                TextField("搜尋地點", text: $viewModel.searchText)
                    .focused($isSearchFocused)
                    .textFieldStyle(.plain)
                    .font(.body) // iOS標準17pt
                    .foregroundColor(.black) // HIG: 直接使用黑色確保文字清晰可見
                    .tint(.blue) // HIG: 游標顏色使用系統藍色
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit {
                        // HIG: 用戶按執行鍵時立即搜索
                        viewModel.performImmediateSearch()
                        isSearchFocused = false
                    }
                    .onChange(of: viewModel.searchText) {
                        // HIG: 搜索文字變化時立即顯示搜索界面
                        viewModel.showingSearchResults = !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    }
                
                // HIG規範：載入和清除按鈕
                if viewModel.isSearching {
                    ProgressView()
                        .controlSize(.small)
                        .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                } else if !viewModel.searchText.isEmpty {
                    Button(action: {
                        viewModel.clearSearch()
                        isSearchFocused = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                            .font(.body) // iOS標準17pt
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(height: 36) // HIG規範：搜索框標準高度
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.gray.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSearchFocused ? .blue : .clear, lineWidth: 1)
                    )
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .animation(.easeInOut(duration: 0.2), value: isSearchFocused)
    }
    
    // MARK: - HIG標準搜索建議（完全按照iPhone地圖規範）
    private var searchSuggestionsDropdown: some View {
        Group {
            if !viewModel.searchResults.isEmpty {
                // HIG: 簡潔的搜索建議列表（完全模仿iPhone地圖）
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.searchResults.prefix(5)) { result in
                        Button(action: {
                            viewModel.selectSearchResult(result)
                            viewModel.showingSearchResults = false
                            isSearchFocused = false
                        }) {
                            HStack(spacing: 16) {
                                // HIG: 位置圖標（iPhone地圖標準）
                                Image(systemName: "location.fill")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.blue)
                                    .frame(width: 24, height: 24)
                                
                                // HIG: 地點信息（iPhone地圖標準佈局）
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(result.name)
                                        .font(.system(size: 17, weight: .regular))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                    
                                    if let subtitle = result.subtitle, !subtitle.isEmpty {
                                        Text(subtitle)
                                            .font(.system(size: 15))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                    }
                                }
                                
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)
                            .background(Color.clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // HIG: 分隔線（iPhone地圖標準）
                        if result.id != viewModel.searchResults.prefix(5).last?.id {
                            Divider()
                                .padding(.leading, 60)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.regularMaterial)
                        .shadow(color: .black.opacity(0.08), radius: 20, x: 0, y: 4)
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
            } else {
                EmptyView()
            }
        }
    }
    
    // MARK: - HIG GPS信號警告橫幅
    private var gpsWarningBanner: some View {
        HStack(spacing: 12) {
            // HIG規範：使用系統警告圖標
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.orange)
                .frame(width: 20, height: 20)
            
            // HIG規範：警告文字使用15pt字體
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.gpsSignalStrength.description)
                    .font(.subheadline) // iOS標準15pt
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text("正在持續更新GPS信號...")
                    .font(.caption) // iOS標準12pt
                    .fontWeight(.regular)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // HIG規範：可選的操作按鈕
            Button(action: {
                viewModel.requestLocationPermission()
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.blue)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.orange.opacity(0.1))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.orange.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.3), value: viewModel.gpsSignalStrength.shouldShowWarning)
    }
    
    // MARK: - HIG精簡位置信息卡片
    private var locationInfoCard: some View {
        HStack(spacing: 10) {
            // HIG規範：精簡圖標設計
            Image(systemName: "location.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.blue)
                .frame(width: 16, height: 16)
            
            // HIG規範：緊湊信息布局
            VStack(alignment: .leading, spacing: 2) {
                // 標題和地址信息
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("目前位置")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.primary)
                        
                        Text(viewModel.currentAddress)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    
                    Spacer(minLength: 0)
                }
                
                // HIG規範：狀態警告（僅在需要時顯示）
                if viewModel.authorizationStatus != .authorizedWhenInUse || viewModel.currentLocation == nil {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.orange)
                        
                        Text(statusText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.orange)
                    }
                }
            }
            
            // HIG規範：緊湊刷新按鈕
            Button(action: {
                viewModel.requestLocationPermission()
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.blue)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 12) // HIG緊湊邊距
        .padding(.vertical, 8)    // HIG緊湊垂直間距
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            // HIG規範：精簡Material設計
            RoundedRectangle(cornerRadius: 8)
                .fill(.regularMaterial)
        )
        .overlay(
            // HIG規範：精簡邊框
            RoundedRectangle(cornerRadius: 8)
                .stroke(.gray.opacity(0.25), lineWidth: 0.5)
        )
        .shadow(
            // HIG規範：精簡陰影
            color: .black.opacity(0.02),
            radius: 1,
            x: 0,
            y: 0.5
        )
        .padding(.horizontal, 16) // 外部邊距保持
    }
    
    // MARK: - HIG底部操作按鈕
    private var bottomActionButtons: some View {
        HStack(spacing: 16) {
            // 智能定位按鈕
            Button(action: {
                viewModel.centerOnCurrentLocation()
            }) {
                Image(systemName: viewModel.shouldShowActiveLocationButton ? "location.fill" : "location")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .background(
                        viewModel.shouldShowActiveLocationButton ? 
                        Color.blue : Color.gray.opacity(0.8),
                        in: Circle()
                    )
                    .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
            }
            .disabled(viewModel.currentLocation == nil)
            .scaleEffect(viewModel.shouldShowActiveLocationButton ? 1.1 : 1.0)
            .animation(.spring(response: 0.3), value: viewModel.shouldShowActiveLocationButton)
            
            Spacer()
            
            // 添加路徑點按鈕
            Button(action: { showingAddPointAlert = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("添加路徑點")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(.green, in: Capsule())
                .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
            }
            .disabled(viewModel.currentLocation == nil)
        }
    }
    
    // MARK: - 工具欄菜單
    private var menuButton: some View {
        Menu {
            Button(action: viewModel.clearSearch) {
                Label("清除搜索", systemImage: "magnifyingglass.circle")
            }
            
            Button(action: viewModel.clearTravelPoints) {
                Label("清除路徑點", systemImage: "trash.circle")
            }
            
            Button(action: viewModel.centerOnCurrentLocation) {
                Label("回到當前位置", systemImage: "location.circle")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 18, weight: .medium))
        }
    }
    
    // MARK: - 地圖視圖
    private var mapView: some View {
        Map(position: $cameraPosition) {
            // 用戶當前位置標註
            if let location = viewModel.currentLocation {
                Annotation("當前位置", coordinate: location.coordinate) {
                    UserLocationAnnotation()
                }
                .annotationTitles(.hidden)
            }
            
            // 旅行路徑點標註
            ForEach(viewModel.travelPoints, id: \.id) { point in
                Annotation("路徑點", coordinate: point.coordinate) {
                    TravelPointAnnotation(point: point)
                }
                .annotationTitles(.hidden)
            }
            
            // 搜索結果標註
            if let selectedResult = viewModel.selectedSearchResult {
                Annotation(selectedResult.name, coordinate: selectedResult.coordinate) {
                    SearchResultAnnotation(result: selectedResult)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .ignoresSafeArea()
        .onTapGesture {
            // HIG: 點擊地圖時隱藏搜索結果和收起鍵盤
            if viewModel.showingSearchResults || isSearchFocused {
                withAnimation(.easeInOut(duration: 0.3)) {
                    viewModel.showingSearchResults = false
                    isSearchFocused = false
                }
            }
        }
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
            viewModel.handleUserMapMovement()
        }
    }
    
    // MARK: - 輔助方法
    private func setupInitialMapPosition() {
        cameraPosition = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 22.307761, longitude: 114.257263),
            latitudinalMeters: 200,
            longitudinalMeters: 200
        ))
    }
    
    private func updateCameraPosition(_ newRegion: MKCoordinateRegion) {
        withAnimation(.easeInOut(duration: 0.8)) {
            cameraPosition = .region(MKCoordinateRegion(
                center: newRegion.center,
                latitudinalMeters: 200,
                longitudinalMeters: 200
            ))
        }
    }
    
    private var statusText: String {
        switch viewModel.authorizationStatus {
        case .notDetermined:
            return "需要位置權限"
        case .denied, .restricted:
            return "位置權限被拒絕"
        case .authorizedWhenInUse, .authorizedAlways:
            if viewModel.currentLocation == nil {
                return "正在定位..."
            }
            return "位置服務正常"
        @unknown default:
            return "位置狀態未知"
        }
    }
    
    // MARK: - 警告對話框
    @ViewBuilder
    private var locationPermissionAlert: some View {
        Button("設定") {
            if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsUrl)
            }
        }
        Button("取消", role: .cancel) { }
    }
    
    @ViewBuilder  
    private var addPointAlert: some View {
        TextField("路徑點名稱", text: .constant(""))
        Button("添加") {
            viewModel.addTravelPoint()
        }
        Button("取消", role: .cancel) { }
    }
}

// MARK: - 路徑點標註視圖
struct TravelPointAnnotation: View {
    let point: TravelPoint
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "mappin.circle.fill")
                .font(.title2)
                .foregroundColor(.red)
                .background(
                    Circle()
                        .fill(.white)
                        .frame(width: 20, height: 20)
                )
            
            Text(timeString(from: point.timestamp))
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.white)
                .foregroundColor(.primary)
                .cornerRadius(4)
                .shadow(radius: 1)
        }
    }
    
    private func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - 用戶位置標註視圖（符合HIG規範）
struct UserLocationAnnotation: View {
    @State private var pulseScale: CGFloat = 1.0
    @State private var animationStarted = false
    
    var body: some View {
        ZStack {
            // 外圈脈動效果
            Circle()
                .fill(.blue.opacity(0.3))
                .frame(width: 40, height: 40)
                .scaleEffect(pulseScale)
                .animation(
                    animationStarted ? 
                        .easeInOut(duration: 2).repeatForever(autoreverses: true) : 
                        .none, 
                    value: pulseScale
                )
            
            // 內圈固定圓點
            Circle()
                .fill(.blue)
                .frame(width: 16, height: 16)
                .overlay(
                    Circle()
                        .stroke(.white, lineWidth: 3)
                )
                .shadow(radius: 3)
        }
        .onAppear {
            // 只在首次出現時啟動動畫，避免重複觸發
            if !animationStarted {
                animationStarted = true
                pulseScale = 1.4
            }
        }
        .id("user-location-annotation") // 確保視圖身份穩定
    }
}

// MARK: - HIG標準搜索結果行組件
struct SearchResultRow: View {
    let result: SearchResult
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // HIG規範：圖標使用標準大小和顏色
                Image(systemName: "mappin.circle.fill")
                    .font(.body) // iOS標準17pt
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
                    .frame(width: 20, height: 20)
                
                // HIG規範：文字區域使用標準字體規格
                VStack(alignment: .leading, spacing: 2) {
                    // HIG規範：主標題使用17pt medium字體
                    Text(result.name)
                        .font(.body) // iOS標準17pt
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    if let subtitle = result.subtitle {
                        // HIG規範：副標題使用15pt regular字體
                        Text(subtitle)
                            .font(.subheadline) // iOS標準15pt
                            .fontWeight(.regular)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                
                // HIG規範：箭頭使用標準指示器
                Image(systemName: "chevron.right")
                    .font(.caption) // iOS標準13pt
                    .fontWeight(.medium)
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 16) // HIG標準16pt邊距
            .padding(.vertical, 12)   // HIG標準12pt垂直邊距
            .frame(minHeight: 44)     // HIG規範：44pt最小觸摸區域
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - HIG搜索結果地圖標註
struct SearchResultAnnotation: View {
    let result: SearchResult
    
    var body: some View {
        VStack(spacing: 6) {
            // 主要標記
            ZStack {
                Circle()
                    .fill(.red)
                    .frame(width: 32, height: 32)
                    .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 2)
                
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            // 位置名稱標籤
            Text(result.name)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        }
    }
}

// MARK: - Preview
#Preview {
    TravelMapView()
} 