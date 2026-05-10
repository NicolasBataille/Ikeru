import Foundation

public enum BadgeRamping {
    public static func rarity(
        for event: MasteryEvent,
        learnerLevel: JLPTLevel
    ) -> LootRarity {
        switch (event, learnerLevel) {
        case (.graduation, .n5), (.graduation, .n4), (.graduation, .n3):     return .common
        case (.graduation, .n2), (.graduation, .n1):                          return .uncommon

        case (.longIntervalRecall, .n5):                                      return .uncommon
        case (.longIntervalRecall, .n4), (.longIntervalRecall, .n3):          return .rare
        case (.longIntervalRecall, .n2), (.longIntervalRecall, .n1):          return .epic

        case (.burned, .n5):                                                  return .rare
        case (.burned, .n4), (.burned, .n3):                                  return .epic
        case (.burned, .n2), (.burned, .n1):                                  return .legendary

        case (.leechRecovered, .n5), (.leechRecovered, .n4):                  return .rare
        case (.leechRecovered, .n3), (.leechRecovered, .n2):                  return .epic
        case (.leechRecovered, .n1):                                          return .legendary
        }
    }
}
