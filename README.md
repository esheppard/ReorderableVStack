# ReorderableVStack

A drag-to-reorder vertical stack for SwiftUI. Works around pitfalls with existing libraries and the `reorderable` API.

## Requirements

- iOS 18+ / macOS 15+
- Swift 6

## Installation

Add the package via Swift Package Manager:

```
https://github.com/esheppard/ReorderableVStack
```

## Basic Usage

Pass a `Binding` to your array and a view builder for each row. The whole row acts as the drag target by default.

```swift
private struct Card: Identifiable {
    let id = UUID()
    var name: String
    var color: Color
}

struct ContentView: View {
    @State private var cards: [Card] = [
        Card(name: "Inbox",    color: .blue),
        Card(name: "Today",    color: .orange),
        Card(name: "Upcoming", color: .green),
        Card(name: "Someday",  color: .purple),
        Card(name: "Archive",  color: .pink),
    ]

    var body: some View {
        ScrollView {
            ReorderableVStack($cards, spacing: 10) { card in
                CardView(card: card)
            }
            .padding()
        }
    }
}
```

## Drag Handle

Mark a single view inside a row with `.dragHandle()` to restrict dragging to that view. The rest of the row is then free for taps, scrolling, or other gestures.

```swift
private struct CardView: View {
    var card: Card

    var body: some View {
        HStack {
            Text(card.name)
                .font(.headline)

            Spacer()

            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .dragHandle()
        }
        .padding()
        .background(card.color, in: .rect(cornerRadius: 16))
    }
}
```

## Customising the Dragging Appearance

`ReorderableVStack` sets two environment values on every row that you can read to adapt its appearance:

| Environment key | Type | Description |
|---|---|---|
| `reorderableIsDragging` | `Bool` | `true` while this row is the one being dragged |
| `reorderableIsDraggable` | `Bool` | `false` when the list has only one item (reordering is meaningless) |

### Lifting effect while dragging

Use `reorderableIsDragging` to give the active row a lifted look — a stronger shadow, a tint change, or any other visual treatment you like.

```swift
private struct CardView: View {
    @Environment(\.reorderableIsDragging) private var isDragging
    var card: Card

    var body: some View {
        HStack { ... }
            .shadow(radius: isDragging ? 12 : 4)
            .opacity(isDragging ? 0.9 : 1)
    }
}
```

### Hiding the drag handle when there is only one item

Use `reorderableIsDraggable` to hide the drag handle when there is nothing to reorder.

```swift
private struct CardView: View {
    @Environment(\.reorderableIsDragging) private var isDragging
    @Environment(\.reorderableIsDraggable) private var isDraggable
    var card: Card

    var body: some View {
        HStack {
            Text(card.name)
                .font(.headline)

            Spacer()

            if isDraggable {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(isDragging ? .primary : .secondary)
                    .dragHandle()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card.color, in: .rect(cornerRadius: 16))
    }
}
```

## Drag Scale

`ReorderableVStack` applies a subtle scale-up to the dragged row`. Override it with `.dragScale(_:)` on the stack:

```swift
ReorderableVStack($cards) { card in
    CardView(card: card)
}
.dragScale(1)
```

## License

MIT
