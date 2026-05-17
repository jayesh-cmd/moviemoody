import SwiftUI
import Combine

// ── Config ───────────────────────────────────────────────
private let SERVER_URL = "http://172.20.10.3:8000"


// ── API model (matches backend) ───────────────────────────
struct APIMovie: Decodable {
    let title      : String
    let year       : String?
    let poster     : String?
    let genres     : [String]
    let overview   : String?
    let imdb_rating: String?
    let why        : String?
}

// ── UI model ──────────────────────────────────────────────
struct MovieItem: Identifiable {
    let id    = UUID()
    let name  : String
    let cat   : String
    let imdb  : String
    let poster: String?
    let why   : String?

    static func from(_ a: APIMovie) -> MovieItem {
        MovieItem(
            name  : a.title,
            cat   : a.genres.prefix(2).joined(separator: " · "),
            imdb  : a.imdb_rating ?? "—",
            poster: a.poster,
            why   : a.why
        )
    }
}

// ── ViewModel ─────────────────────────────────────────────
@MainActor
class OracleVM: ObservableObject {
    @Published var movies  : [MovieItem] = []
    @Published var loading : Bool        = false
    @Published var errorMsg: String?     = nil

    func search(mood: String, contentType: String) async {
        guard !mood.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        loading  = true
        errorMsg = nil
        movies   = []
        do {
            let url     = URL(string: "\(SERVER_URL)/recommend")!
            var req     = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: String] = [
                "mood"        : mood,
                "content_type": contentType == "Movies" ? "movie" : "show"
            ]
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw URLError(.badServerResponse,
                    userInfo: [NSLocalizedDescriptionKey:
                        String(data: data, encoding: .utf8) ?? "Server error"])
            }
            movies  = try JSONDecoder().decode([APIMovie].self, from: data).map { .from($0) }
            loading = false
        } catch {
            errorMsg = error.localizedDescription
            loading  = false
        }
    }
}

// ── Root View ─────────────────────────────────────────────
struct ContentView: View {
    @StateObject private var vm              = OracleVM()
    @State private var selectedTab  : Int    = 0
    @State private var centerIndex  : Int    = 0
    @State private var moodText     : String = ""
    @State private var hasSearched  : Bool   = false

    var label     : String { selectedTab == 0 ? "Movies" : "Shows" }
    var hasResults: Bool   { !vm.movies.isEmpty }

    var body: some View {
        ZStack {
            Color(hex: "#0d0d0d").ignoresSafeArea()

            GeometryReader { _ in
                ZStack {
                    RadialGradient(colors:[Color(red:0.82,green:0.10,blue:0.10).opacity(0.75),.clear],
                                   center:.init(x:0.20,y:1.0), startRadius:0, endRadius:260)
                    RadialGradient(colors:[Color(red:0.67,green:0.06,blue:0.55).opacity(0.70),.clear],
                                   center:.init(x:0.78,y:1.0), startRadius:0, endRadius:220)
                    RadialGradient(colors:[Color(red:0.90,green:0.22,blue:0.00).opacity(0.40),.clear],
                                   center:.init(x:0.55,y:0.95), startRadius:0, endRadius:180)
                }
            }
            .ignoresSafeArea()

            if !hasSearched {
                // ── INITIAL: centered input ──────────────────────────
                VStack(spacing: 36) {
                    Spacer()
                    VStack(spacing: 10) {
                        Text("🎬").font(.system(size: 52))
                        Text("Film Oracle")
                            .font(.system(size: 30, weight: .bold)).foregroundColor(.white)
                        Text("Tell us your mood.\nWe'll find your film.")
                            .font(.system(size: 14, weight: .light))
                            .foregroundColor(.white.opacity(0.35))
                            .multilineTextAlignment(.center)
                    }
                    MoodInputBar(text: $moodText, onSubmit: submitSearch)
                        .padding(.horizontal, 18)
                    Spacer()
                }
                .transition(.opacity)

            } else {
                // ── RESULTS: tabs + carousel + bottom input ──────────
                VStack(spacing: 0) {

                    HStack(spacing: 10) {
                        TabPill(label: "Movies", active: selectedTab == 0) {
                            selectedTab = 0; centerIndex = 0
                            Task { await vm.search(mood: moodText, contentType: "Movies") }
                        }
                        TabPill(label: "Shows", active: selectedTab == 1) {
                            selectedTab = 1; centerIndex = 0
                            Task { await vm.search(mood: moodText, contentType: "Shows") }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 22).padding(.top, 16).padding(.bottom, 20)

                    Spacer()

                    if vm.loading {
                        LoadingStack().transition(.opacity)
                    } else if let err = vm.errorMsg {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 28)).foregroundColor(.white.opacity(0.3))
                            Text(err).font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.4))
                                .multilineTextAlignment(.center).padding(.horizontal, 40)
                        }
                        .transition(.opacity)
                    } else if hasResults {
                        CarouselView(movies: vm.movies, centerIndex: $centerIndex)
                            .frame(height: 300)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))

                        VStack(spacing: 4) {
                            Text(vm.movies[centerIndex].name)
                                .font(.system(size: 20, weight: .bold)).foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .animation(.easeInOut(duration: 0.3), value: centerIndex)

                            Text(vm.movies[centerIndex].cat.uppercased())
                                .font(.system(size: 11)).foregroundColor(.white.opacity(0.4)).kerning(1.2)

                            HStack(spacing: 6) {
                                Text("IMDb").font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.black).padding(.horizontal, 5).padding(.vertical, 2)
                                    .background(Color(hex: "#f5c518")).cornerRadius(3)
                                Text(vm.movies[centerIndex].imdb)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white.opacity(0.75))
                                    .animation(.easeInOut(duration: 0.3), value: centerIndex)
                            }

                            if let why = vm.movies[centerIndex].why {
                                Text(why).font(.system(size: 12, weight: .light))
                                    .foregroundColor(.white.opacity(0.4)).italic()
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 30).padding(.top, 2)
                                    .animation(.easeInOut(duration: 0.3), value: centerIndex)
                            }
                        }
                        .padding(.top, 16).padding(.horizontal, 22).transition(.opacity)

                        DotsView(total: vm.movies.count, active: centerIndex)
                            .padding(.top, 14).transition(.opacity)
                    }

                    Spacer()

                    MoodInputBar(text: $moodText, onSubmit: submitSearch)
                        .padding(.horizontal, 18).padding(.bottom, 34)
                }
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: hasResults)
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: vm.loading)
                .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: hasSearched)
    }

    private func submitSearch() {
        guard !moodText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        hasSearched = true
        centerIndex = 0
        Task { await vm.search(mood: moodText, contentType: label) }
    }
}

// ── Carousel ──────────────────────────────────────────────
struct CarouselView: View {
    let movies: [MovieItem]
    @Binding var centerIndex: Int

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack {
                ForEach(Array(movies.enumerated()), id: \.offset) { i, movie in
                    let pos = calcPos(i)
                    if abs(pos) <= 2 {
                        CardView(movie: movie, pos: pos)
                            .offset(x: xOff(pos: pos, w: w))
                            .zIndex(Double(10 - abs(pos)))
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: centerIndex)
                    }
                }
            }
            .frame(width: w, height: 300)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 20).onEnded { val in
                if val.translation.width < -40 {
                    centerIndex = (centerIndex + 1) % movies.count
                } else if val.translation.width > 40 {
                    centerIndex = (centerIndex - 1 + movies.count) % movies.count
                }
            })
        }
    }

    func calcPos(_ i: Int) -> Int {
        let n = movies.count; var d = i - centerIndex
        if d >  n/2 { d -= n }; if d < -n/2 { d += n }; return d
    }
    func xOff(pos: Int, w: CGFloat) -> CGFloat {
        let m = w / 2
        switch pos {
        case  0: return 0
        case -1: return m - w/2 - 205 + m
        case  1: return m - w/2 + 40  + m
        case -2: return m - w/2 - 280 + m
        case  2: return m - w/2 + 150 + m
        default: return CGFloat(pos) * w
        }
    }
}

// ── Card with AsyncImage poster ───────────────────────────
struct CardView: View {
    let movie: MovieItem
    let pos  : Int

    var cw: CGFloat  { pos == 0 ? 220 : (abs(pos) == 1 ? 165 : 130) }
    var ch: CGFloat  { pos == 0 ? 280 : (abs(pos) == 1 ? 225 : 185) }
    var op: Double   { pos == 0 ? 1.0 : (abs(pos) == 1 ? 0.55 : 0.20) }
    var rot: Double  { pos == 0 ? 0   : (pos < 0 ? -Double(abs(pos))*6 : Double(abs(pos))*6) }

    var body: some View {
        ZStack {
            if let str = movie.poster, let url = URL(string: str) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: fallback
                    }
                }
            } else { fallback }

            LinearGradient(colors: [.clear, .black.opacity(0.55)],
                           startPoint: .top, endPoint: .bottom)

            Text(movie.name.replacingOccurrences(of: " ", with: "\n"))
                .font(.system(size: pos == 0 ? 44 : 36, weight: .black))
                .textCase(.uppercase).multilineTextAlignment(.center)
                .foregroundColor(.white.opacity(0.06)).tracking(-2)
                .allowsHitTesting(false)
        }
        .frame(width: cw, height: ch)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
            .stroke(Color.white.opacity(0.13), lineWidth: 1))
        .rotationEffect(.degrees(rot))
        .opacity(op)
    }

    var fallback: some View {
        LinearGradient(colors: [Color(hex: "#1a1208"), Color(hex: "#0a0a0a")],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// ── Loading skeleton ──────────────────────────────────────
struct LoadingStack: View {
    @State private var pulse = false
    var body: some View {
        ZStack {
            ForEach([-2, -1, 0, 1, 2], id: \.self) { p in
                let w: CGFloat = p == 0 ? 220 : (abs(p) == 1 ? 165 : 130)
                let h: CGFloat = p == 0 ? 280 : (abs(p) == 1 ? 225 : 185)
                let x: CGFloat = p == 0 ? 0   : (p == -1 ? -80 : p == 1 ? 80 : p < 0 ? -155 : 155)
                RoundedRectangle(cornerRadius: 26)
                    .fill(Color.white.opacity(p == 0 ? (pulse ? 0.09 : 0.04) : 0.04))
                    .frame(width: w, height: h)
                    .rotationEffect(.degrees(Double(p) * 6))
                    .offset(x: x)
            }
        }
        .frame(height: 300)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

// ── Dots ──────────────────────────────────────────────────
struct DotsView: View {
    let total: Int; let active: Int
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(Color.white.opacity(i == active ? 0.85 : 0.18))
                    .frame(width: i == active ? 18 : 5, height: 5)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: active)
            }
        }
    }
}

// ── Tab pill ──────────────────────────────────────────────
struct TabPill: View {
    let label: String; let active: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label).font(.system(size: 13, weight: .medium))
                .foregroundColor(active ? .white : .white.opacity(0.4))
                .padding(.horizontal, 22).padding(.vertical, 8)
                .background(Capsule().fill(Color.white.opacity(active ? 0.14 : 0.07))
                    .overlay(Capsule().stroke(Color.white.opacity(active ? 0.28 : 0.12), lineWidth: 1)))
        }
        .buttonStyle(.plain)
    }
}

// ── Mood input bar ────────────────────────────────────────
struct MoodInputBar: View {
    @Binding var text: String
    let onSubmit: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Color(red:0.78,green:0.16,blue:0.16).opacity(0.20))
                    .overlay(Circle().stroke(Color(red:0.86,green:0.24,blue:0.24).opacity(0.30), lineWidth:1))
                    .frame(width:32, height:32)
                Image(systemName:"face.smiling").font(.system(size:14))
                    .foregroundColor(Color(red:1,green:0.43,blue:0.31).opacity(0.9))
            }
            TextField("", text: $text, prompt: Text("What's in your mood?…").foregroundColor(.white.opacity(0.30)))
                .font(.system(size:13, weight:.light))
                .foregroundColor(.white.opacity(0.85))
                .frame(maxWidth:.infinity, alignment:.leading)
                .submitLabel(.send)
                .onSubmit(onSubmit)
            Button(action: onSubmit) {
                ZStack {
                    Circle().fill(LinearGradient(colors:[Color(hex:"#cc2200"),Color(hex:"#991166")],
                                                startPoint:.topLeading, endPoint:.bottomTrailing))
                        .frame(width:30, height:30)
                    Image(systemName:"paperplane.fill").font(.system(size:11, weight:.medium))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal,16).padding(.vertical,13)
        .background(Color.white.opacity(0.06))
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius:20, style:.continuous))
        .overlay(RoundedRectangle(cornerRadius:20, style:.continuous)
            .stroke(Color.white.opacity(0.10), lineWidth:1))
    }
}


// ── Hex helper ────────────────────────────────────────────
extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        self.init(red:   Double((int >> 16) & 0xFF) / 255,
                  green: Double((int >>  8) & 0xFF) / 255,
                  blue:  Double( int        & 0xFF) / 255)
    }
}

// ── Preview ───────────────────────────────────────────────
#Preview { ContentView() }
