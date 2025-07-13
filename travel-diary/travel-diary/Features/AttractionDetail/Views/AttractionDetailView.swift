import SwiftUI

struct AttractionDetailView: View {
    @ObservedObject var viewModel: AttractionDetailViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Hero Image Section
                    heroImageSection
                    
                    // Content Section
                    VStack(spacing: 0) {
                        // Description Card
                        if !viewModel.wikipediaSummary.isEmpty || viewModel.isLoading {
                            descriptionCard
                        }
                        
                        // Error Message
                        if let error = viewModel.errorMessage {
                            errorCard(error: error)
                        }
                    }
                    .padding(.top, 16)
                }
            }
            .navigationTitle(viewModel.attractionName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                    .fontWeight(.medium)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(16)
        .onAppear {
            // ViewModel 已經在初始化時自動載入資料
        }
        .onDisappear {
            // 清理邏輯
        }
    }
    
    // MARK: - Hero Image Section
    @ViewBuilder
    private var heroImageSection: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.blue.opacity(0.3),
                    Color.blue.opacity(0.1)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(height: 200)
            
            // Wikipedia thumbnail if available
            if let thumbnailURL = viewModel.wikipediaThumbnailURL,
               let url = URL(string: thumbnailURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 200)
                        .clipped()
                } placeholder: {
                    ProgressView()
                        .frame(height: 200)
                }
            }
            
            // Overlay with title
            VStack {
                Spacer()
                HStack {
                    VStack(alignment: .leading) {
                        Text(viewModel.attractionName)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .shadow(radius: 2)
                        
                        if !viewModel.wikipediaTitle.isEmpty && viewModel.wikipediaTitle != viewModel.attractionName {
                            Text(viewModel.wikipediaTitle)
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.9))
                                .shadow(radius: 1)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
    }
    
    // MARK: - Description Card
    @ViewBuilder
    private var descriptionCard: some View {
        VStack(spacing: 0) {
            // Card Header
            HStack {
                Image(systemName: "doc.text")
                    .foregroundColor(.blue)
                    .font(.system(size: 16, weight: .medium))
                
                Text("景點介紹")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(UIColor.systemBackground))
            
            Divider()
                .padding(.horizontal, 20)
            
            // Card Content
            VStack(alignment: .leading, spacing: 12) {
                if viewModel.isLoading {
                    // Loading placeholder
                    VStack(spacing: 8) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 16)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                } else if !viewModel.wikipediaSummary.isEmpty {
                    // Wikipedia content
                    Text(viewModel.wikipediaSummary)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .lineLimit(nil)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    
                    // Source attribution
                    HStack {
                        Spacer()
                        Text("資料來源：Wikipedia")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
            }
            .background(Color(UIColor.systemBackground))
        }
        .background(Color(UIColor.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
    
    // MARK: - Error Card
    @ViewBuilder
    private func errorCard(error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 24))
                .foregroundColor(.orange)
            
            Text("載入失敗")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text(error)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("重試") {
                viewModel.refresh()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .background(Color(UIColor.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
}

// MARK: - Preview
#Preview {
    AttractionDetailView(viewModel: AttractionDetailViewModel(attractionName: "測試景點"))
} 