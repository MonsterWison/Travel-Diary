import SwiftUI
import MapKit

/// 旅行地圖主視圖 - 符合 HIG 設計規範
struct TravelMapView: View {
    @StateObject private var viewModel = LocationViewModel()
    @State private var showingAddPointAlert = false
    @State private var cameraPosition = MapCameraPosition.automatic
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 主地圖視圖
                mapView
                
                // 頂部信息欄
                VStack {
                    locationInfoCard
                    Spacer()
                }
                .padding()
                
                // 底部控制欄
                VStack {
                    Spacer()
                    controlButtons
                }
                .padding()
            }
            .navigationTitle("旅行地圖")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("清除路徑點", action: viewModel.clearTravelPoints)
                        Button("回到當前位置") {
                            viewModel.centerOnCurrentLocation()
                            if let location = viewModel.currentLocation {
                                cameraPosition = .region(MKCoordinateRegion(
                                    center: location.coordinate,
                                    latitudinalMeters: 1000,
                                    longitudinalMeters: 1000
                                ))
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
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
            // 應用啟動時設置到用戶位置
            if let location = viewModel.currentLocation {
                cameraPosition = .region(MKCoordinateRegion(
                    center: location.coordinate,
                    latitudinalMeters: 1000,
                    longitudinalMeters: 1000
                ))
            }
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
        }
        .mapStyle(.standard(elevation: .realistic))
        .ignoresSafeArea()
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
            // 定期檢查地圖位置變化，檢測用戶手動移動
            viewModel.handleUserMapMovement()
        }
    }
    
    // MARK: - 位置信息卡片
    private var locationInfoCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 標題行
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "location.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.blue)
                    Text("當前位置")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                Spacer()
                
                // 刷新按鈕
                Button(action: {
                    viewModel.requestLocationPermission()
                }) {
                    Image(systemName: "arrow.clockwise.circle")
                        .font(.system(size: 16))
                        .foregroundColor(.blue)
                }
            }
            
            // 地址信息
            Text(viewModel.currentAddress)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            
            // 座標信息 - 更緊湊的顯示
            if let location = viewModel.currentLocation {
                Text("座標: \(String(format: "%.4f", location.coordinate.latitude)), \(String(format: "%.4f", location.coordinate.longitude))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            // 簡化的狀態信息（僅在需要時顯示）
            if viewModel.authorizationStatus != .authorizedWhenInUse || viewModel.currentLocation == nil {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                    Text(statusText)
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
    
    // 簡化的狀態文字
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
    
    // MARK: - 控制按鈕
    private var controlButtons: some View {
        HStack(spacing: 16) {
            // 智能定位按鈕 - 只有當地圖偏離當前位置時才高亮
            Button(action: {
                #if DEBUG
                print("🎯 定位按鈕被點擊")
                #endif
                viewModel.centerOnCurrentLocation()
                
                // 使用新的 MapKit API 移動地圖到當前位置
                if let location = viewModel.currentLocation {
                    cameraPosition = .region(MKCoordinateRegion(
                        center: location.coordinate,
                        latitudinalMeters: 1000,
                        longitudinalMeters: 1000
                    ))
                }
            }) {
                Image(systemName: viewModel.shouldShowActiveLocationButton ? "location.fill" : "location.circle")
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .background(viewModel.shouldShowActiveLocationButton ? .blue : .gray, in: Circle())
                    .shadow(radius: 3)
            }
            .disabled(viewModel.currentLocation == nil)
            
            Spacer()
            
            // 添加路徑點按鈕
            Button(action: { showingAddPointAlert = true }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("添加路徑點")
                        .fontWeight(.medium)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.green, in: Capsule())
                .shadow(radius: 3)
            }
            .disabled(viewModel.currentLocation == nil)
        }
    }
    
    // MARK: - 警告對話框
    private var locationPermissionAlert: some View {
        Group {
            Button("前往設定") {
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
            }
            Button("取消", role: .cancel) { }
        }
    }
    
    private var addPointAlert: some View {
        Group {
            Button("確認添加") {
                viewModel.addTravelPoint()
            }
            Button("取消", role: .cancel) { }
        }
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

// MARK: - Preview
#Preview {
    TravelMapView()
} 