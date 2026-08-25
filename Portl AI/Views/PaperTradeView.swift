import SwiftUI

/// AI assistant tab — chat interface with live market context
struct AIView: View {

    @State private var viewModel = ChatViewModel()
    @State private var scrollProxy: ScrollViewProxy?
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                chatContent
                inputBar
            }
            .background(Color(.systemBackground))
            .navigationTitle("Portl")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            viewModel.clearChat()
                        } label: {
                            Label("New Chat", systemImage: "plus.message")
                        }

                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(.primary.opacity(0.7))
                    }
                }
            }
            .task {
                await viewModel.prepare()
            }
        }
    }

    // MARK: - Chat Content

    private var chatContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    if viewModel.messages.isEmpty && viewModel.streamedResponse.isEmpty {
                        welcomeSection
                    }

                    ForEach(viewModel.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }

                    // Streaming response
                    if !viewModel.streamedResponse.isEmpty {
                        MessageBubble(
                            message: ChatMessage(role: .assistant, content: viewModel.streamedResponse)
                        )
                        .id("streaming")
                    }

                    // Live activity: what the assistant is actually doing.
                    if viewModel.isLoading && viewModel.streamedResponse.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView()
                                .tint(.primary.opacity(0.5))
                            Text(viewModel.activity ?? "Thinking")
                                .font(.publicaPlay(size: 13))
                                .foregroundStyle(.secondary)
                                .contentTransition(.opacity)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .animation(.easeInOut(duration: 0.2), value: viewModel.activity)
                        .id("loading")
                    }

                    // Non-fatal notices (truncated answer, stale data).
                    if let notice = viewModel.notice {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.secondary)
                            Text(notice)
                                .font(.publicaPlay(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 20)
                    }

                    // Error
                    if let error = viewModel.errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(error)
                                .font(.publicaPlay(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 20)
                    }

                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
            .onAppear { scrollProxy = proxy }
            .onChange(of: viewModel.messages.count) {
                withAnimation(.smooth(duration: 0.3)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: viewModel.streamedResponse) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    // MARK: - Welcome Section

    private var welcomeSection: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text("Live prices, charts and news on demand")
                        .font(.publicaPlay(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 20)

            Text("What would you like to know?")
                .font(.publicaPlay(size: 18))
                .foregroundStyle(.primary.opacity(0.8))

            // Quick prompts
            VStack(spacing: 10) {
                quickPromptRow(
                    icon: "chart.line.uptrend.xyaxis",
                    text: "What's the market looking like right now?",
                    color: .green
                )
                quickPromptRow(
                    icon: "newspaper",
                    text: "Summarize today's crypto news",
                    color: .blue
                )
                quickPromptRow(
                    icon: "lightbulb",
                    text: "Which coins have the strongest momentum right now?",
                    color: .orange
                )
                quickPromptRow(
                    icon: "wallet.pass",
                    text: "How is my portfolio doing?",
                    color: .red
                )
            }
            .padding(.horizontal, 20)
        }
    }

    private func quickPromptRow(icon: String, text: String, color: Color) -> some View {
        Button {
            viewModel.currentInput = text
            Task { await viewModel.sendMessage() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(color)
                    .frame(width: 28)

                Text(text)
                    .font(.publicaPlay(size: 13))
                    .foregroundStyle(.primary.opacity(0.8))
                    .multilineTextAlignment(.leading)

                Spacer()

                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.primary.opacity(0.15))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.haptic)
        .disabled(viewModel.isLoading)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask about the market...", text: $viewModel.currentInput, axis: .vertical)
                .font(.publicaPlay(size: 15))
                .lineLimit(1...5)
                .focused($inputFocused)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
                .onSubmit {
                    Task { await viewModel.sendMessage() }
                }

            Button {
                Task { await viewModel.sendMessage() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(
                        viewModel.currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading
                            ? Color.primary.opacity(0.15)
                            : Color.brandNavy
                    )
            }
            .disabled(viewModel.currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }
}

// MARK: - Message Bubble

private struct MessageBubble: View {

    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .user {
                Spacer(minLength: 60)
            } else {
                // AI avatar
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.55, green: 0.45, blue: 0.75),
                                    Color(red: 0.40, green: 0.55, blue: 0.75)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 28, height: 28)
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                }
                .padding(.top, 2)
            }

            Text(message.content)
                .font(.publicaPlay(size: 14))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    message.role == .user
                        ? Color.primary.opacity(0.12)
                        : Color.primary.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 16)
                )

            if message.role == .assistant {
                Spacer(minLength: 40)
            }
        }
        .padding(.horizontal, 16)
    }
}

#Preview {
    AIView()
}
