import SwiftUI

/// 新写的哔咔界面的入口：没登录显示登录页，登录了显示三个标签页。
///
/// 这一套界面是照着上游客户端（upstream/Pica）的接口重写的，用 SwiftUI，不依赖上游的界面库。
/// 上游的界面还留着（启动页上的另一本书），两边共用同一个登录状态。
struct BikaRootView: View {
    private let session = BikaSession.shared

    var body: some View {
        Group {
            if session.isSignedIn {
                BikaMainView(session: session)
            } else {
                BikaLoginView(session: session)
            }
        }
        .animation(.default, value: session.isSignedIn)
        .task(id: session.isSignedIn) {
            if session.isSignedIn, session.user == nil {
                await session.refreshProfile()
            }
        }
    }
}

/// 登录之后的主界面：首页、排行、我的。
private struct BikaMainView: View {
    @Bindable var session: BikaSession

    var body: some View {
        TabView(selection: $session.selectedTab) {
            Tab("首页", systemImage: "square.grid.2x2.fill", value: BikaTab.home) {
                NavigationStack(path: $session.homePath) {
                    BikaHomeView()
                        .bikaDestinations()
                }
            }
            Tab("排行", systemImage: "chart.bar.fill", value: BikaTab.rank) {
                NavigationStack(path: $session.rankPath) {
                    BikaRankView()
                        .bikaDestinations()
                }
            }
            Tab("我的", systemImage: "person.fill", value: BikaTab.profile) {
                NavigationStack(path: $session.profilePath) {
                    BikaProfileView()
                        .bikaDestinations()
                }
            }
        }
    }
}

extension View {
    /// 导航栈里各种页面的去处。加在每个标签页的根页面上。
    func bikaDestinations() -> some View {
        navigationDestination(for: BikaRoute.self) { route in
            switch route {
            case .comics(let query):
                BikaComicListView(query: query)
            case .detail(let comic):
                BikaComicDetailView(comic: comic)
            case .reader(let target):
                BikaReaderView(target: target)
            case .comments(let comicID, let title):
                BikaCommentsView(comicID: comicID, title: title)
            case .history:
                BikaHistoryView()
            case .settings:
                BikaSettingsView()
            }
        }
    }
}

/// 登录页。账号和密码只发给哔咔的登录接口，本机不保存；保存的是登录成功后拿到的令牌。
struct BikaLoginView: View {
    let session: BikaSession

    private nonisolated enum Field: Hashable {
        case account
        case password
    }

    @State private var account = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @FocusState private var focus: Field?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.tint)
                    .padding(.top, 56)
                    .accessibilityHidden(true)

                Text("哔咔")
                    .font(.largeTitle.bold())

                if let notice = session.notice {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("bika.login.notice")
                }

                VStack(spacing: 12) {
                    TextField("账号", text: $account)
                        .textContentType(.username)
                        .keyboardType(.asciiCapable)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focus, equals: .account)
                        .onSubmit { focus = .password }
                        .accessibilityIdentifier("bika.login.account")

                    Divider()

                    SecureField("密码", text: $password)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .focused($focus, equals: .password)
                        .onSubmit { signIn() }
                        .accessibilityIdentifier("bika.login.password")
                }
                .padding(14)
                .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 12))

                Button {
                    signIn()
                } label: {
                    Group {
                        if isWorking {
                            ProgressView()
                        } else {
                            Text("登录")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(.borderedProminent)
                .disabled(account.isEmpty || password.isEmpty || isWorking)
                .accessibilityIdentifier("bika.login.submit")

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("bika.login.error")
                }

                Text("这里只能登录。注册新账号请用启动页上那本旧版的 Pica，注册好之后两边都能用。")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(uiColor: .systemBackground))
    }

    private func signIn() {
        guard !account.isEmpty, !password.isEmpty, !isWorking else { return }
        focus = nil
        isWorking = true
        errorMessage = nil
        Task {
            do {
                try await session.signIn(account: account, password: password)
                password = ""
            } catch is CancellationError {
                // 页面离开了，不提示。
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }
}
