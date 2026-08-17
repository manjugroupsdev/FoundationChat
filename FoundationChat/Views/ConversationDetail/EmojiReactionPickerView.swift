import SwiftUI

/// Catalog of emoji grouped into categories, with a keyword search index and a
/// small persisted "recents / favorites" list. Ported from the Android app's
/// `CustomEmojiData` so the iOS reaction picker offers the same set of emoji,
/// the same searchable keywords, and the same most-recently-used behaviour.
enum ChatEmojiCatalog {

  /// Ordered categories shown as tabs (after the leading "Recents" tab).
  static let categories: [(name: String, emojis: [String])] = [
    ("Smileys", [
      "😀", "😃", "😄", "😁", "😆", "😅", "😂", "🤣", "😊", "😇",
      "🙂", "🙃", "😉", "😌", "😍", "🥰", "😘", "😗", "😙", "😚",
      "😋", "😛", "😝", "😜", "🤪", "🤨", "🧐", "🤓", "😎", "🥸",
      "🥳", "😏", "😒", "😞", "😔", "😟", "😕", "🙁", "☹️", "😣",
      "😖", "😫", "😩", "🥺", "😢", "😭", "😤", "😠", "😡", "🤬",
      "🤯", "😳", "🥵", "🥶", "😱", "😨", "😰", "😥", "😓", "🤗",
      "🤔", "🫣", "🤭", "🥱", "🤫", "🤥", "😶", "😐", "😑", "😬",
      "🙄", "😯", "😦", "😧", "😮", "😲", "😴", "🤤", "😪", "😵",
      "😵‍💫", "🤐", "🥴", "🤢", "🤮", "🤧", "😷", "🤒", "🤕",
      "😈", "👿", "👹", "👺", "💀", "☠️", "👽", "👾", "🤖", "💩",
    ]),
    ("Gestures", [
      "👍", "👎", "👌", "🤌", "🤏", "✌️", "🤞", "🫰", "🤟", "🤘",
      "🤙", "👈", "👉", "👆", "🖕", "👇", "☝️", "✊",
      "👊", "🤛", "🤜", "👏", "🙌", "👐", "🤲", "🤝", "🙏", "✍️",
      "💅", "🤳", "💪", "🦾", "🦿", "🦵", "🦶", "👂", "🦻", "👃",
      "🧠", "🫀", "🫁", "🦷", "🦴", "👀", "👁️", "👅", "👄", "💋",
    ]),
    ("Hearts", [
      "❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "🤎", "❤️‍🔥",
      "❤️‍🩹", "💔", "❣️", "💕", "💞", "💓", "💗", "💖", "💘", "💝",
    ]),
    ("Food", [
      "🍏", "🍎", "🍐", "🍊", "🍋", "🍌", "🍉", "🍇", "🍓", "🫐",
      "🍈", "🍒", "🍑", "🥭", "🍍", "🥥", "🥝", "🍅", "🍆", "🥑",
      "🥦", "🥬", "🥒", "🌶️", "🫑", "🌽", "🥕", "🥔", "🍠", "🥐",
      "🍞", "🥖", "🥨", "🥯", "🥞", "🧇", "🧀", "🍖", "🍗", "🥩",
      "🥓", "🍔", "🍟", "🍕", "🌭", "🥪", "🌮", "🌯", "🥚", "🍳",
      "🥘", "🍲", "🍿", "🍣", "🍱", "🍦", "🍧", "🍩", "🍪", "🎂",
      "🍰", "🧁", "🥧", "🍫", "🍬", "🍭", "☕", "🍵", "🍺", "🍷",
    ]),
    ("Activities", [
      "🎉", "🥳", "🎈", "🎁", "🎂", "🎊", "🧧", "🏮", "🎇", "🎆",
      "🏆", "🥇", "🥈", "🥉", "🏅", "🎖️", "🎗️", "🎫", "🎟️", "⚽",
      "🏀", "🏈", "⚾", "🥎", "🎾", "🏐", "🏉", "🎱", "🪀", "🏓",
      "🏸", "🏒", "🥍", "🏹", "🎣", "🪁", "🎯", "🎮", "🕹️", "🎰",
      "🎲", "🧩", "🎳", "🛹", "⛸️", "🎿", "🏂", "🎬", "🎤", "🎧",
    ]),
    ("Travel", [
      "🚗", "🚕", "🚙", "🚌", "🚎", "🏎️", "🚓", "🚑", "🚒", "🚐",
      "🛻", "🚚", "🚛", "🚜", "🛵", "🏍️", "🚲", "🛴", "🚏", "🚂",
      "🚄", "🚅", "🚇", "🚈", "🚞", "🚆", "🚢", "✈️", "🚀", "🛸",
      "🏠", "🏡", "🏢", "🏣", "🏥", "🏦", "🏨", "🏫", "🏪", "🌆",
      "🏖️", "⛰️", "🌋", "🏕️", "⛺", "🌅", "🌌", "🌍",
    ]),
    ("Symbols", [
      "🔥", "✨", "💯", "🌟", "⭐", "💥", "🌈", "⚡", "☀️", "❄️",
      "💧", "💤", "❌", "✅", "⚠️", "ℹ️", "➕", "➖", "❓", "❗️",
      "🔔", "💡", "🔑", "🔒", "🔓", "📢", "💬", "💭", "🎯", "🚩",
      "🏁", "🎵", "🎶", "🚫", "🔄", "🔁", "🔀", "🔇", "🔈",
    ]),
  ]

  // MARK: - Keyword search

  /// One entry per emoji with a bag of lowercase keywords (ported verbatim from
  /// the Android keyword groups). Swift iterates `String` by grapheme cluster,
  /// so multi-scalar emoji (ZWJ sequences, variation selectors) stay intact.
  private static let keywordIndex: [(emoji: String, keywords: String)] = {
    var index: [(emoji: String, keywords: String)] = []
    func add(_ emojis: String, _ keywords: String) {
      for character in emojis where !character.isWhitespace {
        index.append((emoji: String(character), keywords: keywords))
      }
    }
    add("😀😃😄😁😆😅😂🤣😊😇", "smile smiley happy face grin laugh joy grinning")
    add("🙂🙃😉😌", "smile soft happy wink relax upside down")
    add("😍🥰😘😗😙😚", "love heart eyes blow kiss smiling blush romance sweet romantic")
    add("😋😛😝😜🤪", "tongue crazy silly play delicious yum food tasty wink")
    add("🤨🧐🤓😎🥸", "think curious look glasses spectacles sunglasses cool smart spy")
    add("🥳😏😒😞😔😟😕🙁☹️", "party celebrate birthday sad sigh unhappy down depressed worry sorry")
    add("😣😖😫😩🥺", "cry weep begging please plead pain hurt struggle stress")
    add("😢😭😤😠😡🤬🤯", "cry weep tears sob sad angry mad furious red scream head explode shock surprise")
    add("😳🥵🥶😱😨😰😥😓🤗", "blush hot sweat cold freeze fear shock scary surprise hug open hands")
    add("🤔🫣🤭🥱🤫🤥😶😐😑😬🙄", "think hide eye giggle laugh whisper silence quiet yawn sleepy roll eyes nervous awkward")
    add("😯😦😧😮😲😴🤤😪😵🤐🥴🤢🤮🤧😷🤒🤕", "shock surprise sleep sleepy tired snore zzz dizzy sick throw up vomit mask ill hurt pain green")
    add("😈👿👹👺💀☠️👽👾🤖💩", "devil demon red evil skull dead bones death alien martian robot poop shit brown smile")
    add("👍👌✌️🤞🤝🙏👏🙌", "yes like good agree ok okay peace two fingers luck crossed deal greet handshake thank you thanks pray praise please wave hello bye clap applaud congratulations")
    add("👎🖕👊🤛🤜✊👈👉👆👇☝️✍️💅🤳💪", "no dislike bad punch fight flex strong arm power write note draw hand point finger nail polish selfie phone")
    add("👀👁️👄👅👂👃🧠💋", "eyes look watch see hear listen smell brain think head kiss lips red mouth tongue")
    add("❤️🧡💛💚💙💜🖤🤍🤎❤️‍🔥❤️‍🩹💔❣️💕💞💓💗💖💘💝", "love heart like red orange yellow green blue purple black white pink sparkle beat pulse grow arrow gift present romance")
    add("🍏🍎🍇🍓🍒🍉🍕🍔🍟🌭🥪🌮🌯🥚🍳🍿🍣☕🍵🍺🍷", "apple fruit food eat drink hungry pizza cheese burger meat fries hotdog sandwich taco egg cook pop corn sushi coffee tea beer alcohol wine cup glass")
    add("🎉🥳🎈🎁🎂🏆🥇🏅🎫🎮🕹️🎲🎯🎬🎤🎧🎸", "party celebrate birthday balloon gift present win cup first place gold award ticket play game controller play station video game music mic sing song guitar instrument")
    add("🚗🚕🚙🚌🏎️🚓🚑🚒🚚🚜🏍️🚲🚇✈️🚀🛸🏠🏖️☀️❄️🌍", "car auto drive vehicle police ambulance fire bike cycle flight plane space rocket house home beach summer hot weather cold winter snow earth world")
    add("🔥✨💯🌟⭐💥🌈⚡💤❌✅⚠️ℹ️❓❗️🔔💡🔑🔒💬", "fire hot burn flame trend sparkles shine star gold score hundred perfect explosion blast flash storm lightning rain sleeping cross delete done correct sign warn caution info question mark help exclamation call message speak lock key light bulb idea")
    return index
  }()

  static func search(_ query: String) -> [String] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !trimmed.isEmpty else { return [] }
    var seen = Set<String>()
    var results: [String] = []
    for entry in keywordIndex where entry.keywords.contains(trimmed) || entry.emoji == trimmed {
      if seen.insert(entry.emoji).inserted { results.append(entry.emoji) }
    }
    return results
  }

  // MARK: - Recents / favorites

  private static let favoritesKey = "chat.emoji.favorites"
  private static let maxFavorites = 35

  static func favorites() -> [String] {
    guard let stored = UserDefaults.standard.array(forKey: favoritesKey) as? [String] else {
      return defaultFavorites
    }
    let cleaned = stored.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    return cleaned.isEmpty ? defaultFavorites : cleaned
  }

  static func addFavorite(_ emoji: String) {
    let trimmed = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    var current = favorites()
    current.removeAll { $0 == trimmed }
    current.insert(trimmed, at: 0)
    if current.count > maxFavorites { current = Array(current.prefix(maxFavorites)) }
    UserDefaults.standard.set(current, forKey: favoritesKey)
  }

  static let defaultFavorites: [String] = [
    "❤️", "👍", "😂", "🔥", "✨", "😊", "😍", "🎉", "🙏", "👏",
    "🙌", "🤣", "🥰", "😘", "😜", "🤔", "😭", "😢", "😎", "💯",
    "🤩", "🤷", "🤦", "👀", "👌", "💪", "💡", "✔️", "❌", "⚠️",
  ]
}

/// Full emoji reaction picker — categorized + searchable + recents — presented
/// from the message reaction menu so a message can be reacted to with any emoji,
/// not just the six quick reactions.
struct EmojiReactionPickerSheet: View {
  let onSelect: (String) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var query: String = ""
  @State private var activeCategory: String = "Recents"
  @State private var favorites: [String] = ChatEmojiCatalog.favorites()

  private let columns = [GridItem(.adaptive(minimum: 44), spacing: 6)]
  private let accent = Color(hex: 0x0B61CA)
  private let mutedText = Color(hex: 0x475467)

  private var categoryNames: [String] {
    ["Recents"] + ChatEmojiCatalog.categories.map(\.name)
  }

  private var visibleEmojis: [String] {
    let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedQuery.isEmpty {
      return ChatEmojiCatalog.search(trimmedQuery)
    }
    if activeCategory == "Recents" {
      return favorites
    }
    return ChatEmojiCatalog.categories.first { $0.name == activeCategory }?.emojis ?? []
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 12) {
        searchField

        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          categoryTabs
        }

        emojiGrid
      }
      .padding(.top, 8)
      .navigationTitle("React")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Close") { dismiss() }
        }
      }
    }
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
  }

  private var searchField: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 15, weight: .regular))
        .foregroundStyle(mutedText)
      TextField("Search emoji", text: $query)
        .font(.system(size: 16))
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
      if !query.isEmpty {
        Button {
          query = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(mutedText)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(Color.primary.opacity(0.06), in: Capsule())
    .padding(.horizontal, 16)
  }

  private var categoryTabs: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(categoryNames, id: \.self) { name in
          let isActive = name == activeCategory
          Button {
            activeCategory = name
          } label: {
            Text(name)
              .font(.system(size: 14, weight: isActive ? .semibold : .regular))
              .foregroundStyle(isActive ? accent : mutedText)
              .padding(.horizontal, 14)
              .padding(.vertical, 7)
              .background(
                isActive ? accent.opacity(0.12) : Color.primary.opacity(0.05),
                in: Capsule()
              )
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 16)
    }
  }

  private var emojiGrid: some View {
    ScrollView {
      if visibleEmojis.isEmpty {
        Text(query.isEmpty ? "No emoji here yet" : "No matching emoji")
          .font(.system(size: 15))
          .foregroundStyle(mutedText)
          .frame(maxWidth: .infinity)
          .padding(.top, 40)
      } else {
        LazyVGrid(columns: columns, spacing: 6) {
          ForEach(visibleEmojis, id: \.self) { emoji in
            Button {
              select(emoji)
            } label: {
              Text(emoji)
                .font(.system(size: 28))
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
      }
    }
  }

  private func select(_ emoji: String) {
    ChatEmojiCatalog.addFavorite(emoji)
    favorites = ChatEmojiCatalog.favorites()
    onSelect(emoji)
    dismiss()
  }
}
