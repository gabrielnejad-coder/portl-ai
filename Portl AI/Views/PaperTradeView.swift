import SwiftUI

/// AI assistant tab — chat interface with live market context
struct AIView: View {

    @State private var viewModel = ChatViewModel()
    @State private var scrollProxy: ScrollViewProxy?
    @State private var showAPIKeySheet = false
    @FocusState private var inputFocused: Bool

    /// Stored API key in UserDefaults (simple for now)
    @AppStorage("openai_api_key") private var storedAPIKey = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !viewModel.isConfigured {
                    apiKeyPrompt
                } else {
                    chatContent
                    inputBar
                }
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

                        Button {
                            Task { await viewModel.loadMarketContext() }
                        } label: {
                            Label("Refresh Market Data", systemImage: "arrow.clockwise")
                        }

                        Button {
                            showAPIKeySheet = true
                        } label: {
                            Label("API Key", systemImage: "key")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(.primary.opacity(0.7))
                    }
                }
            }
            .sheet(isPresented: $showAPIKeySheet) {
                APIKeySheet(apiKey: $storedAPIKey) {
                    viewModel.configure(apiKey: storedAPIKey)
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
            .task {
                viewModel.configure(apiKey: storedAPIKey)
                if viewModel.isConfigured {
                    await viewModel.loadMarketContext()
                }
            }
        }
    }

    // MARK: - API Key Prompt

    private var apiKeyPrompt: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "bolt.fill")
                .font(.system(size: 48))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.55, green: 0.45, blue: 0.75),
                            Color(red: 0.40, green: 0.55, blue: 0.75)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: 8) {
                Text("Portl")
                    .font(.publicaPlay(size: 24))

                Text("AI-powered market analysis using live data and news")
                    .font(.publicaPlay(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button {
                showAPIKeySheet = true
            } label: {
                Text("Set Up API Key")
                    .font(.publicaPlay(size: 16))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(Color.brandNavy, in: Capsule())
            }
            .buttonStyle(.haptic)

            Text("Requires an OpenAI API key")
                .font(.publicaPlay(size: 11))
                .foregroundStyle(.secondary.opacity(0.6))

            Spacer()
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

                    // Loading indicator
                    if viewModel.isLoading && viewModel.streamedResponse.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView()
                                .tint(.primary.opacity(0.5))
                            Text("Analyzing market data...")
                                .font(.publicaPlay(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .id("loading")
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
                if viewModel.contextLoaded {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(.green)
                            .frame(width: 6, height: 6)
                        Text("Live market data loaded")
                            .font(.publicaPlay(size: 12))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Loading market data...")
                            .font(.publicaPlay(size: 12))
                            .foregroundStyle(.secondary)
                    }
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
                    text: "Which coins have the most momentum?",
                    color: .orange
                )
                quickPromptRow(
                    icon: "exclamationmark.triangle",
                    text: "Any high-impact news I should know about?",
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

// MARK: - API Key Sheet

struct APIKeySheet: View {

    @Binding var apiKey: String
    var onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var tempKey = ""

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: "key.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)

                Text("OpenAI API Key")
                    .font(.publicaPlay(size: 18))

                Text("Your key is stored locally on your device and never shared.")
                    .font(.publicaPlay(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            .padding(.top, 20)

            SecureField("sk-...", text: $tempKey)
                .font(.system(size: 14, design: .monospaced))
                .textFieldStyle(.plain)
                .padding(14)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.horizontal, 20)

            Button {
                apiKey = tempKey.trimmingCharacters(in: .whitespacesAndNewlines)
                onSave()
                dismiss()
            } label: {
                Text("Save")
                    .font(.publicaPlay(size: 16))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.brandNavy, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.haptic)
            .padding(.horizontal, 20)
            .disabled(tempKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if !apiKey.isEmpty {
                Button(role: .destructive) {
                    apiKey = ""
                    tempKey = ""
                    onSave()
                    dismiss()
                } label: {
                    Text("Remove Key")
                        .font(.publicaPlay(size: 14))
                        .foregroundStyle(.red)
                }
            }

            Spacer()
        }
        .onAppear {
            tempKey = apiKey
        }
    }
}

#Preview {
    AIView()
}
