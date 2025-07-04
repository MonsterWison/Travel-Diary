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
                    if !viewModel.description.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("景點介紹")
                                .font(.title3.bold())
                                .padding(.bottom, 2)
                            Text(viewModel.description)
                                .font(.body)
                                .foregroundColor(.primary)
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
        .onAppear { viewModel.fetchDetailIfNeeded() }
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
                        Text(error)
                            .font(.title3)
                            .foregroundColor(.red)
                            .padding(32)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
        )
    }
} 