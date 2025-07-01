import SwiftUI
import MapKit

/// 旅遊日誌主視圖 - 符合 HIG 設計規範
struct TravelMapView: View {
    @StateObject private var viewModel = LocationViewModel()
    @State private var showingAddPointAlert = false
    @State private var cameraPosition = MapCameraPosition.automatic
    @FocusState private var isSearchFocused: Bool
    
    // MARK: - HIG動態布局計算（確保警告橫幅不覆蓋主要交互元素）
    private var topContentOffset: CGFloat {
        var offset: CGFloat = 8 // 基礎間距
        
        // HIG: 根據警告橫幅狀態動態調整間距
        if viewModel.authorizationStatus == .denied || viewModel.authorizationStatus == .restricted {
            offset += 80 // 位置權限警告橫幅高度 + 間距
        } else if viewModel.gpsSignalStrength.shouldShowWarning {
            offset += 72 // GPS信號警告橫幅高度 + 間距
        }
        
        return offset
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 主地圖視圖（符合HIG本地化標準）
                mapView
                
                // HIG: 搜索和建議區域（永遠保持可見和可交互）
                VStack(spacing: 0) {
                    // 動態頂部間距，根據警告橫幅的存在自動調整
                    Spacer()
                        .frame(height: topContentOffset)
                        .animation(.easeInOut(duration: 0.3), value: topContentOffset)
                    
                    // 搜索框（始終可見和可交互）
                    topSearchArea
                    
                    // HIG: 搜索建議下拉列表（緊貼搜索框下方）
                    if viewModel.showingSearchResults {
                        searchSuggestionsDropdown
                    }
                    
                    Spacer()
                }
                .animation(.easeInOut(duration: 0.3), value: topContentOffset)
                
                // HIG: 警告橫幅（不干擾主要交互元素的獨立層級）
                VStack(spacing: 8) {
                    // HIG: 位置權限警告（最高優先級）
                    if viewModel.authorizationStatus == .denied || viewModel.authorizationStatus == .restricted {
                        locationPermissionWarningBanner
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    // HIG: GPS信號警告（次優先級）
                    else if viewModel.gpsSignalStrength.shouldShowWarning {
                        gpsSignalWarningBanner
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    Spacer()
                }
                .animation(.easeInOut(duration: 0.3), value: viewModel.authorizationStatus)
                .animation(.easeInOut(duration: 0.3), value: viewModel.gpsSignalStrength)
                
                // HIG: 精簡浮動信息卡片（僅在需要時顯示）
                if !isSearchFocused && !viewModel.showingSearchResults {
                    VStack {
                        Spacer()
                            .frame(height: 120) // 為警告和搜索區域留空間
                        
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
            // HIG: 確保應用本地化設置正確
            configureMapLocalization()
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
    
    // MARK: - HIG 位置權限警告橫幅（最高優先級）
    private var locationPermissionWarningBanner: some View {
        HStack(spacing: 12) {
            // HIG規範：使用系統關鍵警告圖標
            Image(systemName: "location.slash.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.red)
                .frame(width: 24, height: 24)
            
            // HIG規範：警告文字使用清晰的層次結構
            VStack(alignment: .leading, spacing: 3) {
                Text("位置服務已關閉")
                    .font(.subheadline) // iOS標準15pt
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text("需要開啟位置權限才能使用地圖功能")
                    .font(.caption) // iOS標準12pt
                    .fontWeight(.regular)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            // HIG規範：主要操作按鈕
            Button(action: {
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
            }) {
                Text("設定")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.red, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.red.opacity(0.1))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.red.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.3), value: viewModel.authorizationStatus)
    }
    
    // MARK: - HIG GPS信號警告橫幅（次優先級）
    private var gpsSignalWarningBanner: some View {
        HStack(spacing: 12) {
            // HIG規範：使用系統警告圖標，區分不同嚴重程度
            Image(systemName: viewModel.gpsSignalStrength == .invalid ? "antenna.radiowaves.left.and.right.slash" : "exclamationmark.triangle.fill")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(viewModel.gpsSignalStrength == .invalid ? .red : .orange)
                .frame(width: 22, height: 22)
            
            // HIG規範：根據GPS狀態提供不同的訊息
            VStack(alignment: .leading, spacing: 2) {
                Text(gpsWarningTitle)
                    .font(.subheadline) // iOS標準15pt
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text(gpsWarningMessage)
                    .font(.caption) // iOS標準12pt
                    .fontWeight(.regular)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            // HIG規範：次要操作按鈕
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
        .background(warningBackgroundColor.opacity(0.1))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(warningBackgroundColor.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.3), value: viewModel.gpsSignalStrength.shouldShowWarning)
    }
    
    // MARK: - GPS警告輔助計算屬性
    private var gpsWarningTitle: String {
        switch viewModel.gpsSignalStrength {
        case .invalid:
            return "GPS信號無效"
        case .veryPoor:
            return "GPS信號很弱"
        case .poor:
            return "GPS信號較弱"
        default:
            return viewModel.gpsSignalStrength.description
        }
    }
    
    private var gpsWarningMessage: String {
        switch viewModel.gpsSignalStrength {
        case .invalid:
            return "無法取得有效的GPS信號，請移至空曠地區"
        case .veryPoor:
            return "位置精度很低，建議移至空曠地區以改善信號"
        case .poor:
            return "位置精度較低，正在努力改善GPS信號品質"
        default:
            return "正在持續改善GPS信號品質..."
        }
    }
    
    private var warningBackgroundColor: Color {
        switch viewModel.gpsSignalStrength {
        case .invalid:
            return .red
        default:
            return .orange
        }
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
    
    // MARK: - HIG標準地圖視圖（符合Apple Maps本地化規範）
    private var mapView: some View {
        Map(position: $cameraPosition) {
            // 用戶當前位置標註
            if let location = viewModel.currentLocation {
                Annotation("當前位置", coordinate: location.coordinate) {
                    UserLocationAnnotation(heading: viewModel.currentHeading)
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
        // HIG: 使用標準地圖樣式，符合Apple Maps的顯示標準，顯示所有興趣點包含大廈名稱
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .all))
        // HIG: 確保地圖使用系統語言設置，優先顯示中文地名
        .environment(\.locale, Locale(identifier: "zh-HK"))
        .preferredColorScheme(.light) // HIG: 確保在光線下的可讀性
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
    
    // MARK: - HIG本地化配置
    private func configureMapLocalization() {
        // HIG: 確保地圖本地化設置符合Apple Maps標準
        // 設置地圖語言偏好為中文（香港），以確保地名顯示為中文
        viewModel.configureLocalization(locale: Locale(identifier: "zh-HK"))
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

// MARK: - 用戶位置標註視圖（完全符合Apple Maps真實外觀）
struct UserLocationAnnotation: View {
    let heading: CLHeading?
    
    @State private var pulseScale: CGFloat = 1.0
    @State private var animationStarted = false
    
    var body: some View {
        ZStack {
            // Apple Maps真實脈動效果（更大更明顯）
            Circle()
                .fill(Color(red: 0.0, green: 0.478, blue: 1.0).opacity(0.15)) // Apple Maps淺藍色脈動
                .frame(width: 50, height: 50) // 更大的脈動圓圈，匹配Apple Maps
                .scaleEffect(pulseScale)
                .animation(
                    animationStarted ? 
                        .easeInOut(duration: 2).repeatForever(autoreverses: true) : 
                        .none, 
                    value: pulseScale
                )
            
            // HIG: Apple Maps標準定位點（永久顯示方向光束）
            // 永遠顯示方向指示器，即使沒有精確的heading數據也要顯示默認方向
            AppleMapLocationWithBeam(heading: heading)
        }
        .onAppear {
            // 只在首次出現時啟動動畫，避免重複觸發
            if !animationStarted {
                animationStarted = true
                pulseScale = 1.4 // Apple Maps真實脈動比例
            }
        }
        .id("user-location-annotation") // 確保視圖身份穩定
    }
}

// MARK: - Apple Maps真實定位指示器（帶向外擴散漸變光束）
struct AppleMapLocationWithBeam: View {
    let heading: CLHeading?
    
    // 安全的角度計算，永遠返回有效角度
    private var safeRotationAngle: Double {
        guard let heading = heading else {
            return 0 // 沒有heading數據時指向北方
        }
        
        let trueHeading = heading.trueHeading
        let magneticHeading = heading.magneticHeading
        
        var angle: Double = 0
        
        // 嚴格的數值安全檢查
        if trueHeading >= 0 && trueHeading <= 360 && trueHeading.isFinite && !trueHeading.isNaN {
            angle = trueHeading
        } else if magneticHeading >= 0 && magneticHeading <= 360 && magneticHeading.isFinite && !magneticHeading.isNaN {
            angle = magneticHeading
        } else {
            angle = 0 // 安全默認值：指向北方
        }
        
        // 確保角度在有效範圍內
        return angle.truncatingRemainder(dividingBy: 360)
    }
    
    var body: some View {
        ZStack {
            // Apple Maps向外擴散漸變光束（從深色到透明）
            AppleMapDirectionalBeam()
                .fill(
                    RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color(red: 0.0, green: 0.478, blue: 1.0).opacity(0.7), location: 0.0), // 中心深色
                            .init(color: Color(red: 0.0, green: 0.478, blue: 1.0).opacity(0.4), location: 0.3), // 中間過渡
                            .init(color: Color(red: 0.0, green: 0.478, blue: 1.0).opacity(0.1), location: 0.7), // 邊緣漸淡
                            .init(color: Color(red: 0.0, green: 0.478, blue: 1.0).opacity(0.0), location: 1.0)  // 完全透明
                        ]),
                        center: .center,
                        startRadius: 2,
                        endRadius: 30
                    )
                )
                .frame(width: 60, height: 60) // 光束擴散範圍
                .rotationEffect(.degrees(safeRotationAngle - 90)) // 向上為0度基準
                .animation(.easeInOut(duration: 0.25), value: safeRotationAngle)
            
            // Apple Maps標準定位點
            AppleMapLocationDot()
        }
    }
}

// MARK: - Apple Maps標準藍點配白圈
struct AppleMapLocationDot: View {
    var body: some View {
        ZStack {
            // 外圍白色細圈（Apple Maps標準）
            Circle()
                .stroke(Color.white, lineWidth: 2.0) // 幼白圈
                .frame(width: 20, height: 20)
                .shadow(color: .black.opacity(0.15), radius: 1, x: 0, y: 1)
            
            // 中心藍色圓點（Apple Maps標準）
            Circle()
                .fill(Color(red: 0.0, green: 0.478, blue: 1.0)) // Apple Maps藍色 #007AFF
                .frame(width: 16, height: 16) // 中心藍點，比白圈小
                .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
        }
    }
}

// MARK: - Apple Maps向外擴散光束形狀（真實扇形）
struct AppleMapDirectionalBeam: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        
        // Apple Maps真實光束角度：約45度扇形，從中心向外擴散
        let beamAngle: Double = 45 // 光束角度
        let halfAngle = beamAngle / 2
        
        let startAngle = Angle.degrees(-halfAngle) // 從-22.5度開始
        let endAngle = Angle.degrees(halfAngle)    // 到22.5度結束
        
        // 創建從中心向外擴散的扇形光束
        path.move(to: center) // 從中心點開始
        path.addArc(center: center, 
                   radius: radius, 
                   startAngle: startAngle, 
                   endAngle: endAngle, 
                   clockwise: false)
        path.closeSubpath() // 封閉路徑形成扇形
        
        return path
    }
}

// MARK: - Apple Maps真實三角形箭頭形狀（保留向後兼容）
struct AppleMapTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // Apple Maps真實三角形：標準箭頭比例
        let topPoint = CGPoint(x: rect.midX, y: rect.minY) // 頂點
        let leftPoint = CGPoint(x: rect.midX - rect.width * 0.4, y: rect.maxY) // 左下角（標準寬度）
        let rightPoint = CGPoint(x: rect.midX + rect.width * 0.4, y: rect.maxY) // 右下角（標準寬度）
        
        path.move(to: topPoint)
        path.addLine(to: leftPoint)
        path.addLine(to: rightPoint)
        path.closeSubpath()
        
        return path
    }
}

// MARK: - 通用三角形箭頭形狀（保留向後兼容）
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // HIG: 創建向上指向的三角形，符合Apple Maps設計
        path.move(to: CGPoint(x: rect.midX, y: rect.minY)) // 頂點
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY)) // 左下角  
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY)) // 右下角
        path.closeSubpath()
        
        return path
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