import SwiftUI
import MapKit
import WebKit

/// 旅遊日誌主視圖 - 符合 HIG 設計規範
struct TravelMapView: View {
    @StateObject private var viewModel = LocationViewModel()
    @State private var showingAddPointAlert = false
    @State private var cameraPosition = MapCameraPosition.automatic
    @FocusState private var isSearchFocused: Bool
    @State private var selectedAttractionID: UUID? = nil
    @State private var webSearchURL: URL? = nil
    @State private var showingWebSearch = false
    @State private var isRegionInfoLoading: Bool = false
    @State private var selectedAttraction: NearbyAttraction? = nil
    @State private var pendingWebSearchQuery: String? = nil
    // 新增：詳情頁ViewModel cache
    @State private var detailViewModel: AttractionDetailViewModel? = nil
    
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
                .padding(.bottom, calculateBottomPadding())
                .animation(.easeOut(duration: 0.3), value: viewModel.attractionPanelState)
            
            // MARK: - Apple Maps風格拖拽面板
            attractionDraggablePanel
            if isRegionInfoLoading {
                Color.black.opacity(0.2).ignoresSafeArea()
                ProgressView("正在判斷地區，請稍候...")
                    .progressViewStyle(CircularProgressViewStyle())
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemBackground)))
                    .shadow(radius: 8)
            }
        }
        .navigationTitle("旅遊日誌")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: menuButton)
            .alert("需要位置權限", isPresented: $viewModel.showingLocationAlert) {
                locationPermissionAlert
            }
            .alert("添加路徑點", isPresented: $showingAddPointAlert) {
                addPointAlert
            }
        }
        .onAppear {
            #if DEBUG
            print("[DEBUG][View] TravelMapView onAppear: setup initial map position, load cache, auto search attractions")
            #endif
            setupInitialMapPosition()
            viewModel.loadAttractionsFromCache()
            viewModel.autoSearchAttractionsOnAppStart()
            configureMapLocalization()
            NotificationCenter.default.addObserver(forName: NSNotification.Name("AttractionFallbackWebSearch"), object: nil, queue: .main) { notif in
                if let name = notif.object as? String {
                    pendingWebSearchQuery = name
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            #if DEBUG
            print("[DEBUG][View] App will enter foreground: check attractions on resume")
            #endif
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                viewModel.checkAttractionsOnAppResume()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            #if DEBUG
            print("[DEBUG][View] App did enter background: save attractions cache")
            #endif
            viewModel.saveAttractionsToCache()
        }
        .onReceive(viewModel.$region) { newRegion in
            #if DEBUG
            print("[DEBUG][View] Map region changed: \(newRegion)")
            #endif
            updateCameraPosition(newRegion)
        }
        .onChange(of: selectedAttractionID) { _, newID in
            if let id = newID, let attraction = viewModel.nearbyAttractions.first(where: { $0.id == id }) {
                selectedAttraction = attraction
                // 只有id不同才new新的ViewModel
                if detailViewModel?.baseAttraction.id != id {
                    detailViewModel = AttractionDetailViewModel(attraction: attraction, userLocation: viewModel.currentLocation)
                }
            }
        }
        .onChange(of: selectedAttraction) { _, newValue in
            if let id = newValue?.id, let attraction = viewModel.nearbyAttractions.first(where: { $0.id == id }) {
                selectedAttraction = attraction
                // 只有id不同才new新的ViewModel
                if detailViewModel?.baseAttraction.id != id {
                    detailViewModel = AttractionDetailViewModel(attraction: attraction, userLocation: viewModel.currentLocation)
                }
            } else if newValue == nil, let query = pendingWebSearchQuery {
                // 詳情頁已關閉，這時才開 WebSearch（延遲 0.4 秒，確保動畫結束）
                let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
                viewModel.getCachedOrFreshRegionInfo { regionInfo in
                    let urlString: String
                    if regionInfo.isMainlandChina {
                        urlString = "https://www.baidu.com/s?wd=\(encoded)"
                    } else {
                        urlString = "https://www.google.com/search?q=\(encoded)"
                    }
                    if let url = URL(string: urlString) {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            webSearchURL = url
                            showingWebSearch = true
                        }
                    }
                    pendingWebSearchQuery = nil
                }
                // 關閉詳情時清空ViewModel
                detailViewModel = nil
            }
        }
        .sheet(item: $selectedAttraction) { attraction in
            // 僅根據現有的 detailViewModel 渲染，不做任何副作用
            if let vm = detailViewModel, vm.baseAttraction.id == attraction.id {
                AttractionDetailView(viewModel: vm)
            } else {
                // fallback：若 detailViewModel 尚未建立，建立臨時ViewModel（理論上不會發生）
                AttractionDetailView(viewModel: AttractionDetailViewModel(attraction: attraction, userLocation: viewModel.currentLocation))
            }
        }
        .fullScreenCover(isPresented: $showingWebSearch) {
            if let url = webSearchURL {
                WebSearchViewController(url: url) {
                    showingWebSearch = false
                }
            }
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
                    .onChange(of: viewModel.searchText) { _, newValue in
                        // HIG: 搜索文字變化時立即顯示搜索界面
                        viewModel.showingSearchResults = !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                            if !viewModel.isPlaceSearchCoolingDown {
                                viewModel.selectSearchResult(result)
                                viewModel.showingSearchResults = false
                                isSearchFocused = false
                            }
                        }) {
                            HStack(spacing: 16) {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(viewModel.isPlaceSearchCoolingDown ? .gray : .blue)
                                    .frame(width: 24, height: 24)
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
                                if viewModel.isPlaceSearchCoolingDown {
                                    Text("冷卻中: \(viewModel.placeSearchCooldownRemaining)s")
                                        .font(.caption2)
                                        .foregroundColor(.red)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)
                            .background(Color.clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(viewModel.isPlaceSearchCoolingDown)
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
                // 顯示冷卻倒數提示
                if viewModel.isPlaceSearchCoolingDown {
                    Text("地點搜尋冷卻中，請等待 \(viewModel.placeSearchCooldownRemaining) 秒...")
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.top, 4)
                }
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
                viewModel.restoreOriginalNearbyAttractions()
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
            Button(action: {
                viewModel.searchNearbyAttractions()
            }) {
                Label("搜索附近景點", systemImage: "binoculars")
            }
            .disabled(viewModel.currentLocation == nil || viewModel.isLoadingAttractions)
            
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
        Map(position: $cameraPosition, selection: $selectedAttractionID) {
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
            // 新增：選中景點標註
            ForEach(viewModel.nearbyAttractions, id: \.id) { attraction in
                Marker(attraction.name, systemImage: attraction.category.iconName, coordinate: CLLocationCoordinate2D(latitude: attraction.coordinate.latitude, longitude: attraction.coordinate.longitude))
                    .tint(.orange)
                    .tag(attraction.id)
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
            latitudinalMeters: 1000,
            longitudinalMeters: 1000
        ))
    }
    
    private func updateCameraPosition(_ newRegion: MKCoordinateRegion) {
        withAnimation(.easeInOut(duration: 0.8)) {
            cameraPosition = .region(MKCoordinateRegion(
                center: newRegion.center,
                latitudinalMeters: 1000,
                longitudinalMeters: 1000
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
    
    // MARK: - Apple Maps風格可拖拽景點面板
    private var attractionDraggablePanel: some View {
        GeometryReader { geometry in
            let screenHeight = geometry.size.height
            let panelHeight: CGFloat = {
                switch viewModel.attractionPanelState {
                case .hidden: return 80  // 用戶要求：永遠顯示景點搜尋器（縮小狀態）
                case .compact: return 80  // 固定高度，像Apple Maps
                case .expanded: return screenHeight * 0.6
                }
            }()
            
            VStack(spacing: 0) {
                // 用戶要求：永遠顯示景點搜尋器面板
                appleMapsPanelContent
            }
            .frame(height: max(panelHeight, 0))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: -4)
            .offset(y: screenHeight - panelHeight + viewModel.attractionPanelOffset)
            .animation(.interactiveSpring(response: 0.4, dampingFraction: 0.8), value: viewModel.attractionPanelState)
            .animation(.interactiveSpring(response: 0.4, dampingFraction: 0.8), value: viewModel.attractionPanelOffset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        viewModel.updatePanelState(dragValue: value, screenHeight: screenHeight)
                    }
                    .onEnded { value in
                        viewModel.finalizePanelState(dragValue: value)
                    }
            )
        }
        .ignoresSafeArea(.all, edges: .bottom)
    }
    
    // MARK: - Apple Maps風格面板內容
    private var appleMapsPanelContent: some View {
        VStack(spacing: 0) {
            // HIG: 拖拽指示器區域（較大的觸摸區域）
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(Color.primary.opacity(0.3))
                    .frame(width: 40, height: 5)
                    .padding(.top, 8)
            }
            .frame(height: 20)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            // 只在 compact/hidden 狀態渲染 compactModeContent
            if viewModel.attractionPanelState == .compact || viewModel.attractionPanelState == .hidden {
                compactModeContent
            }
            // 只在 expanded 狀態渲染 expandedModeContent
            if viewModel.attractionPanelState == .expanded {
                expandedModeContent
            }
        }
    }
    
    // MARK: - 緊湊模式內容（Apple Maps風格）
    private var compactModeContent: some View {
        HStack {
            // 左側圖標和文字
            HStack(spacing: 8) {
                // 可點擊的手動更新按鈕（含冷卻狀態顯示）
                Button(action: {
                    viewModel.manualRefreshAttractions()
                }) {
                    ZStack {
                        Image(systemName: "location.magnifyingglass")
                            .font(.title3)
                            .foregroundColor(viewModel.canManualRefresh ? .blue : .gray)
                        
                        // 冷卻倒計時顯示
                        if !viewModel.canManualRefresh {
                            Text("\(viewModel.manualRefreshCooldownRemaining)")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .frame(width: 16, height: 16)
                                .background(Circle().fill(Color.red))
                                .offset(x: 8, y: -8)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isLoadingAttractions || !viewModel.canManualRefresh)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("附近景點")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    if viewModel.isLoadingAttractions {
                        HStack(spacing: 4) {
                            if viewModel.isUsingCachedData || viewModel.isManualRefreshing {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }
                            Text((viewModel.isUsingCachedData || viewModel.isManualRefreshing) ? "更新中..." : "搜索20km範圍內...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else if viewModel.isUsingCachedData {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.caption2)
                                .foregroundColor(.orange)
                            Text("\(viewModel.nearbyAttractions.count) 個地點（緩存數據）")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("\(viewModel.nearbyAttractions.count) 個地點（20km內）")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // 右側載入指示器或箭頭
            if viewModel.isLoadingAttractions {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Button(action: {
                    withAnimation(.interactiveSpring()) {
                        viewModel.attractionPanelState = .expanded
                    }
                }) {
                    Image(systemName: "chevron.up")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }
    
    // MARK: - 展開模式內容
    private var expandedModeContent: some View {
        VStack(spacing: 0) {
            // HIG: 展開狀態標題區域，左側手動更新、置中標題、右側下箭頭
            HStack {
                // 左側手動更新按鈕
                Button(action: {
                    viewModel.manualRefreshAttractions()
                }) {
                    ZStack {
                        Image(systemName: "location.magnifyingglass")
                            .font(.title3)
                            .foregroundColor(viewModel.canManualRefresh ? .blue : .gray)
                        if !viewModel.canManualRefresh {
                            Text("\(viewModel.manualRefreshCooldownRemaining)")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .frame(width: 16, height: 16)
                                .background(Circle().fill(Color.red))
                                .offset(x: 8, y: -8)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isLoadingAttractions || !viewModel.canManualRefresh)
                .frame(width: 32, height: 32)
                Spacer()
                Text("附近景點")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                Spacer()
                // 右側下箭頭
                Button(action: {
                    withAnimation(.interactiveSpring()) {
                        viewModel.attractionPanelState = .compact
                    }
                }) {
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 32, height: 32)
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            // 原有展開內容
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 12) {
                    if viewModel.isManualRefreshing {
                        VStack(spacing: 20) {
                            HStack(spacing: 12) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 24, weight: .medium))
                                    .foregroundColor(.orange)
                                Text("更新中...")
                                    .font(.title)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.orange)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 80)
                        VStack(spacing: 16) {
                            Image(systemName: "location.magnifyingglass")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text("附近沒有找到景點")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text("嘗試移動到其他區域搜索")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                    }
                    ForEach(viewModel.nearbyAttractions) { attraction in
                        ExpandedAttractionCard(attraction: attraction)
                            .environmentObject(viewModel)
                            .onTapGesture {
                                viewModel.focusOnAttraction(attraction)
                            }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 34)
            }
            .frame(maxHeight: .infinity)
        }
    }
    
    // MARK: - 底部按鈕位置計算
    private func calculateBottomPadding() -> CGFloat {
        let basePadding: CGFloat = 34 // Home Indicator安全區域
        
        switch viewModel.attractionPanelState {
        case .hidden:
            return basePadding
        case .compact:
            return basePadding + 80 + 16  // 固定80pt + 間距
        case .expanded:
            return basePadding + (UIScreen.main.bounds.height * 0.6) + 16
        }
    }
    
    // MARK: - HIG本地化配置
    private func configureMapLocalization() {
        // HIG: 確保地圖本地化設置符合Apple Maps標準
        // 設置地圖語言偏好為中文（香港），以確保地名顯示為中文
        viewModel.configureLocalization(locale: Locale(identifier: "zh-HK"))
    }
    
    private func openAttractionWebSearch(_ attraction: NearbyAttraction) {
        let query = "\(attraction.name) \(attraction.address ?? "")"
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        isRegionInfoLoading = true
        viewModel.getCachedOrFreshRegionInfo { regionInfo in
            let urlString: String
            if regionInfo.isMainlandChina {
                urlString = "https://www.baidu.com/s?wd=\(encoded)"
            } else {
                urlString = "https://www.google.com/search?q=\(encoded)"
            }
            DispatchQueue.main.async {
                if let url = URL(string: urlString) {
                    webSearchURL = url
                    showingWebSearch = true
                }
                isRegionInfoLoading = false
            }
        }
    }
    
    /// 根據CLLocation取得地區資訊（isoCountryCode與行政區）
    private func getRegionInfo(from location: CLLocation?) -> (isoCountryCode: String?, administrativeArea: String?, isMainlandChina: Bool) {
        guard let location = location else { return (nil, nil, false) }
        var result: (String?, String?, Bool) = (nil, nil, false)
        let semaphore = DispatchSemaphore(value: 0)
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            if let placemark = placemarks?.first {
                let code = placemark.isoCountryCode?.uppercased()
                let admin = placemark.administrativeArea ?? ""
                // 只要是中國大陸（CN），且行政區不是香港、澳門、台灣才算大陸
                let isMainland = (code == "CN") && (!admin.contains("香港") && !admin.contains("澳门") && !admin.contains("台灣") && !admin.contains("台湾"))
                result = (code, admin, isMainland)
            }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 1.0) // 最多等1秒
        return result
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
    
    var body: some View {
        // HIG: Apple Maps標準定位點（永久顯示方向光束）
        // 移除脈動效果，完全匹配Apple Maps的簡潔設計
        AppleMapLocationWithBeam(heading: heading)
            .id("user-location-annotation") // 確保視圖身份穩定
    }
}

// MARK: - Apple Maps真實定位指示器（帶向外擴散漸變光束）
struct AppleMapLocationWithBeam: View {
    let heading: CLHeading?
    @State private var lastAngle: Double = 0
    @State private var displayAngle: Double = 0

    private var targetAngle: Double {
        guard let heading = heading else { return 0 }
        let trueHeading = heading.trueHeading
        let magneticHeading = heading.magneticHeading
        var angle: Double = 0
        if trueHeading >= 0 && trueHeading <= 360 && trueHeading.isFinite && !trueHeading.isNaN {
            angle = trueHeading
        } else if magneticHeading >= 0 && magneticHeading <= 360 && magneticHeading.isFinite && !magneticHeading.isNaN {
            angle = magneticHeading
        } else {
            angle = 0
        }
        return angle.truncatingRemainder(dividingBy: 360)
    }

    private func shortestAngle(from: Double, to: Double) -> Double {
        let diff = (to - from).truncatingRemainder(dividingBy: 360)
        if diff > 180 {
            return diff - 360
        } else if diff < -180 {
            return diff + 360
        } else {
            return diff
        }
    }

    var body: some View {
        ZStack {
            AppleMapDirectionalBeam()
                .fill(
                    RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color(red: 0.0, green: 0.478, blue: 1.0).opacity(0.8), location: 0.0),
                            .init(color: Color(red: 0.0, green: 0.478, blue: 1.0).opacity(0.5), location: 0.2),
                            .init(color: Color(red: 0.0, green: 0.478, blue: 1.0).opacity(0.2), location: 0.6),
                            .init(color: Color(red: 0.0, green: 0.478, blue: 1.0).opacity(0.0), location: 1.0)
                        ]),
                        center: .center,
                        startRadius: 1,
                        endRadius: 50
                    )
                )
                .frame(width: 100, height: 100)
                .rotationEffect(.degrees(displayAngle - 90))
                .animation(.easeInOut(duration: 0.25), value: displayAngle)
            AppleMapLocationDot()
        }
        .onAppear {
            displayAngle = targetAngle
            lastAngle = targetAngle
        }
        .onChange(of: targetAngle) { _, newAngle in
            let shortest = shortestAngle(from: lastAngle, to: newAngle)
            let next = lastAngle + shortest
            lastAngle = next.truncatingRemainder(dividingBy: 360)
            withAnimation(.easeInOut(duration: 0.25)) {
                displayAngle = lastAngle
            }
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

// MARK: - 簡單景點卡片（保留向後兼容）
struct SimpleAttractionCard: View {
    let attraction: NearbyAttraction
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 景點圖標
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(attraction.category.color.opacity(0.15))
                    .frame(width: 80, height: 50)
                
                Image(systemName: attraction.category.iconName)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(attraction.category.color)
            }
            
            // 景點信息
            VStack(alignment: .leading, spacing: 2) {
                Text(attraction.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                Text("\(Int(attraction.distanceFromUser))m")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 80)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.background)
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
    }
}

// MARK: - HIG緊湊模式景點卡片（Apple Maps風格）
struct CompactAttractionCard: View {
    let attraction: NearbyAttraction
    @EnvironmentObject var viewModel: LocationViewModel
    private var distanceText: String {
        let distance = attraction.distanceFromUser
        if distance < 1000 {
            return "\(Int(distance))m"
        } else {
            return String(format: "%.1fkm", distance / 1000)
        }
    }
    
    var body: some View {
        Button(action: {
            viewModel.focusOnAttraction(attraction)
        }) {
            VStack(alignment: .leading, spacing: 8) {
                // HIG: 景點圖標區域
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(attraction.category.color.opacity(0.12))
                        .frame(width: 100, height: 60)
                    
                    Image(systemName: attraction.category.iconName)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(attraction.category.color)
                }
                
                // HIG: 景點信息區域
                VStack(alignment: .leading, spacing: 4) {
                    Text(attraction.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    HStack {
                        Text(attraction.category.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text(distanceText)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.blue)
                    }
                }
            }
        }
        .frame(width: 100)
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
        .buttonStyle(.plain)
    }
}

// MARK: - HIG展開模式景點卡片（Apple Maps風格）
struct ExpandedAttractionCard: View {
    let attraction: NearbyAttraction
    @EnvironmentObject var viewModel: LocationViewModel
    private var distanceText: String {
        let distance = attraction.distanceFromUser
        if distance < 1000 {
            return "\(Int(distance))m"
        } else {
            return String(format: "%.1fkm", distance / 1000)
        }
    }
    
    var body: some View {
        Button(action: {
            viewModel.focusOnAttraction(attraction)
        }) {
            HStack(spacing: 16) {
                // HIG: 景點圖標
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(attraction.category.color.opacity(0.12))
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: attraction.category.iconName)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(attraction.category.color)
                }
                
                // HIG: 景點詳細信息
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(attraction.name)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .lineLimit(2)
                        
                        Spacer()
                        
                        Text(distanceText)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.blue)
                    }
                    
                    HStack {
                        Text(attraction.category.displayName)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                    }
                    
                    if let address = attraction.address, !address.isEmpty {
                        Text(address)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                
                // HIG: 箭頭指示器
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.gray)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 選中景點標註視圖
struct SelectedAttractionAnnotation: View {
    let attraction: NearbyAttraction
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 32, height: 32)
                    .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 2)
                Image(systemName: attraction.category.iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
            }
            Text(attraction.name)
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

import WebKit
struct WebSearchViewController: UIViewControllerRepresentable {
    let url: URL
    let onClose: () -> Void
    func makeUIViewController(context: Context) -> UINavigationController {
        let webVC = UIViewController()
        let webView = WKWebView()
        webView.translatesAutoresizingMaskIntoConstraints = false
        webVC.view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: webVC.view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: webVC.view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: webVC.view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: webVC.view.bottomAnchor)
        ])
        let request = URLRequest(url: url)
        webView.load(request)
        webVC.navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "chevron.left"),
            style: .plain,
            target: context.coordinator,
            action: #selector(Coordinator.closeTapped)
        )
        webVC.navigationItem.title = ""
        let nav = UINavigationController(rootViewController: webVC)
        nav.navigationBar.prefersLargeTitles = false
        return nav
    }
    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
    func makeCoordinator() -> Coordinator {
        Coordinator(onClose: onClose)
    }
    class Coordinator: NSObject {
        let onClose: () -> Void
        init(onClose: @escaping () -> Void) {
            self.onClose = onClose
        }
        @objc func closeTapped() {
            onClose()
        }
    }
} 