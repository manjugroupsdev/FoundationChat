import SwiftUI
import Combine
import ConvexMobile

struct UpdatesFeedView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var posts: [ConvexPost] = []
    @State private var selectedCategory: String? = nil
    @State private var isLoading = true
    @State private var showComposer = false
    @State private var cancellable: AnyCancellable?
    @State private var didSubscribe = false

    private let categories = ["Announcement", "HR", "Engineering", "Social"]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    categoryFilterBar
                        .padding(.horizontal)
                        .padding(.top, 8)

                    if isLoading && posts.isEmpty {
                        loadingView
                    } else if posts.isEmpty {
                        emptyView
                    } else {
                        let pinnedPosts = posts.filter { $0.isPinned }
                        if !pinnedPosts.isEmpty {
                            pinnedSection(pinnedPosts)
                        }

                        let regularPosts = posts.filter { !$0.isPinned }
                        ForEach(regularPosts) { post in
                            NavigationLink(value: post.id) {
                                PostCardView(post: post)
                                    .onAppear {
                                        markAsRead(post)
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .refreshable {
                await loadPosts()
            }
            .navigationTitle("Updates")
            .navigationDestination(for: String.self) { postId in
                PostDetailView(postId: postId)
            }
            .overlay(alignment: .bottomTrailing) {
                if authStore.isAdmin {
                    composeButton
                }
            }
            .sheet(isPresented: $showComposer) {
                PostComposerView()
            }
            .task {
                guard !didSubscribe else { return }
                didSubscribe = true
                await subscribeToPosts()
            }
        }
    }

    private var categoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "All", isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                    Task { await subscribeToPosts() }
                }
                ForEach(categories, id: \.self) { category in
                    FilterChip(title: category, isSelected: selectedCategory == category) {
                        selectedCategory = category
                        Task { await subscribeToPosts() }
                    }
                }
            }
        }
    }

    private func pinnedSection(_ pinnedPosts: [ConvexPost]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Pinned", systemImage: "pin.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 12)

            ForEach(pinnedPosts) { post in
                NavigationLink(value: post.id) {
                    PostCardView(post: post)
                        .background(Color.accentColor.opacity(0.05))
                        .onAppear { markAsRead(post) }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading updates...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    private var emptyView: some View {
        ContentUnavailableView(
            "No Updates Yet",
            systemImage: "newspaper",
            description: Text("Company updates and announcements will appear here.")
        )
        .padding(.top, 60)
    }

    private var composeButton: some View {
        Button {
            showComposer = true
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color.accentColor, in: Circle())
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        }
        .padding(.trailing, 20)
        .padding(.bottom, 20)
    }

    private func subscribeToPosts() async {
        cancellable?.cancel()
        if posts.isEmpty {
            isLoading = true
        }
        do {
            let publisher = try authStore.subscribePosts(category: selectedCategory)
            cancellable = publisher.receive(on: DispatchQueue.main).sink(
                receiveCompletion: { _ in },
                receiveValue: { newPosts in
                    if let newPosts {
                        self.posts = newPosts
                        self.isLoading = false
                    }
                }
            )
        } catch {
            isLoading = false
        }
    }

    private func loadPosts() async {
        do {
            posts = try await authStore.fetchPosts(category: selectedCategory)
        } catch {}
    }

    private func markAsRead(_ post: ConvexPost) {
        guard !post.isRead else { return }
        Task { try? await authStore.markPostRead(postId: post.id) }
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? Color.accentColor : Color(.systemGray5), in: Capsule())
                .foregroundStyle(isSelected ? .white : .primary)
        }
    }
}
