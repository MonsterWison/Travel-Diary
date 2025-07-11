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

                    // 名稱
                    Text(viewModel.name)
                        .font(.largeTitle.bold())
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .padding(.bottom, 2)

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

                    // 詳細介紹
                    if !viewModel.description.isEmpty || viewModel.isWikiSearching {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("景點介紹")
                                .font(.title3.bold())
                                .accessibilityAddTraits(.isHeader)
                                .padding(.bottom, 2)
                            ZStack(alignment: .bottomTrailing) {
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
                                    Text(viewModel.descriptionTextOnly)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                        .multilineTextAlignment(.leading)
                                        .padding(16)
                                        .background(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .fill(Color(.secondarySystemBackground))
                                        )
                                    if let source = viewModel.descriptionSource, !source.isEmpty {
                                        VStack(alignment: .trailing, spacing: 0) {
                                            Divider()
                                            Text(source)
                                                .font(.footnote)
                                                .foregroundColor(.secondary)
                                                .padding(.top, 4)
                                                .padding(.trailing, 8)
                                                .accessibilityLabel("資料來源：" + source)
                                        }
                                        .padding(.bottom, 4)
                                    }
                                }
                            }
                        }
                        .padding(.top, 8)
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
                // 關閉詳情頁並通知主視圖開啟 WebSearch
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
} 