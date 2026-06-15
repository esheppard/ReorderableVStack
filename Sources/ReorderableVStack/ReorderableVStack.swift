//
// ReorderableVStack
//

import SwiftUI

/// A vertical stack whose children can be reordered by dragging.
///
/// By default the whole row is the drag target. A row can instead expose a single
/// view as its handle by marking it `.dragHandle()`; when it does, only that view
/// initiates a reorder and the rest of the row is left free (to scroll, tap, etc.).
///
/// Rows are only draggable when there is more than one item in the collection.
struct ReorderableVStack<Item: Identifiable, Content: View>: View {
  @Environment(\.dragScale) private var dragScale

  @Binding var items: [Item]
  var spacing: CGFloat
  var content: (Item) -> Content

  /// The id of the row currently being dragged, if any. Its array index stays
  /// fixed for the duration of the drag.
  @State private var draggingID: Item.ID?

  /// Raw vertical translation of the active drag, applied directly to the dragged row.
  @State private var dragTranslation: CGFloat = 0

  /// The index the dragged row would land on if released now. Drives the gap.
  @State private var targetIndex: Int?

  /// The id of a row that has been dropped and is animating back into place. It
  /// keeps the elevated zIndex during that settle so neighbors can't clip it.
  @State private var settlingID: Item.ID?

  /// Measured row heights, used to size the gap and to hit-test the drop slot.
  @State private var heights: [Item.ID: CGFloat] = [:]

  /// Indices of rows that published a custom `.dragHandle()`. For these rows the
  /// default whole-row gesture is switched off so only the handle reorders.
  @State private var rowsWithHandle: Set<Int> = []

  init(
    _ items: Binding<[Item]>,
    spacing: CGFloat = 8,
    @ViewBuilder content: @escaping (Item) -> Content
  ) {
    self._items = items
    self.spacing = spacing
    self.content = content
  }
  
  var body: some View {
    VStack(spacing: spacing) {
      ForEach(items) { item in
        let isDragging = item.id == draggingID
        let index = items.firstIndex { $0.id == item.id } ?? 0
        content(item)
          .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { newHeight in
            heights[item.id] = newHeight
          }
          .scaleEffect(isDragging ? dragScale : 1)
          .animation(.snappy(duration: 0.2), value: isDragging)
          // Stay above neighbors while dragging *and* while settling home after a
          // drop, so the row is never clipped by adjacent views mid-animation.
          .zIndex((isDragging || item.id == settlingID) ? 1 : 0)
          .offset(y: offsetY(for: item))
          // Hand any `.dragHandle()` inside this row the hooks to drive the drag
          // for *this* item, plus the index it should report itself under.
          .environment(\.dragHandleContext, DragHandleContext(
            index: index,
            onChanged: { handleDragChanged($0, for: item) },
            onEnded: { handleDragEnded(for: item) }
          ))
          .environment(\.reorderableIsDragging, isDragging)
          .environment(\.reorderableIsDraggable, canReorder)
          // The default whole-row gesture. If the row published a handle, mask this
          // gesture to `.subviews` so it no longer recognizes — only the handle
          // reorders, and the rest of the row stays free for scrolling / taps.
          // Also masked when there is only one item and reordering is meaningless.
          .gesture(
            dragGesture(for: item),
            including: (!canReorder || rowsWithHandle.contains(index)) ? .subviews : .all
          )
      }
    }
    .onPreferenceChange(DragHandlePresenceKey.self) { value in
      rowsWithHandle = value
    }
    // Stable reference space for the handle drag. A dragged row gets visual
    // `.offset`/`.scaleEffect`; a `.dragHandle()` lives *inside* those transforms, so
    // measuring its translation against the moving row feeds back into itself and
    // jitters. Measuring against the (static) stack instead breaks that loop.
    .coordinateSpace(.named(ReorderableCoordinateSpace.name))
  }

  /// Rows are only draggable when there is more than one item.
  private var canReorder: Bool {
    items.count > 1
  }
  
  // MARK: - Gesture

  private func dragGesture(for item: Item) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in handleDragChanged(value.translation.height, for: item) }
      .onEnded { _ in handleDragEnded(for: item) }
  }

  /// Shared drag handling, called by both the whole-row gesture and a `.dragHandle()`.
  /// `translationHeight` is the raw vertical translation since the drag began.
  private func handleDragChanged(_ translationHeight: CGFloat, for item: Item) {
    guard canReorder else { return }
    if draggingID == nil {
      draggingID = item.id
    }
    guard draggingID == item.id else { return }
    dragTranslation = translationHeight
    updateTarget()
  }

  private func handleDragEnded(for item: Item) {
    guard draggingID == item.id else { return }
    commitDrop()
  }

  // MARK: - Drag state

  /// Recomputes the drop slot from the dragged row's current center. The `items`
  /// order is static during the drag, so these centers are stable references.
  private func updateTarget() {
    guard let draggingID,
          let from = items.firstIndex(where: { $0.id == draggingID }) else { return }

    let draggedCenter = center(at: from) + dragTranslation
    let draggedHalfHeight = (heights[draggingID] ?? 44) / 2
    var target = from

    if draggedCenter < center(at: from) {
      // Dragging up: swap when the top edge of the dragged view crosses a target's midpoint.
      while target > 0 && (draggedCenter - draggedHalfHeight) < center(at: target - 1) {
        target -= 1
      }
    } else {
      // Dragging down: swap when the bottom edge of the dragged view crosses a target's midpoint.
      while target < items.count - 1 && (draggedCenter + draggedHalfHeight) > center(at: target + 1) {
        target += 1
      }
    }
    // Animate only the gap. `dragTranslation` was set outside any animation just
    // before this call, so the dragged row keeps tracking the finger instantly,
    // while the other rows slide as the target slot changes.
    if target != targetIndex {
      withAnimation(.snappy(duration: 0.25)) {
        targetIndex = target
      }
    }
  }

  /// Commits the reorder on release. This `withAnimation` owns the settle, so its
  /// completion is a reliable signal for when the row has finished animating home —
  /// at which point it's safe to drop the elevated zIndex.
  private func commitDrop() {
    guard let draggingID,
          let from = items.firstIndex(where: { $0.id == draggingID }) else {
      resetDrag()
      return
    }
    let dropped = draggingID
    let dest = targetIndex ?? from

    settlingID = dropped
    withAnimation(.snappy(duration: 0.25), completionCriteria: .removed) {
      if dest != from {
        items.move(fromOffsets: [from], toOffset: dest > from ? dest + 1 : dest)
      }
      resetDrag()
    } completion: {
      if settlingID == dropped { settlingID = nil }
    }
  }

  private func resetDrag() {
    draggingID = nil
    dragTranslation = 0
    targetIndex = nil
  }

  // MARK: - Offsets

  /// The dragged row floats by the raw translation; the rows between its origin and
  /// the drop slot shift by one gap (its height + spacing) to make room.
  private func offsetY(for item: Item) -> CGFloat {
    if item.id == draggingID { return dragTranslation }

    guard let draggingID,
          let from = items.firstIndex(where: { $0.id == draggingID }),
          let target = targetIndex,
          let index = items.firstIndex(where: { $0.id == item.id }) else { return 0 }

    let gap = (heights[draggingID] ?? 44) + spacing
    if target > from, index > from, index <= target { return -gap }  // dragging down
    if target < from, index >= target, index < from { return gap }   // dragging up
    return 0
  }

  // MARK: - Layout math

  /// Vertical center of the row at `index`, in stack-local space.
  private func center(at index: Int) -> CGFloat {
    var top: CGFloat = 0
    for i in 0..<index {
      top += height(at: i) + spacing
    }
    return top + height(at: index) / 2
  }

  private func height(at index: Int) -> CGFloat {
    guard items.indices.contains(index) else { return 0 }
    return heights[items[index].id] ?? 44
  }
}

// MARK: - Drag handle

extension View {
  /// Marks this view as *the* drag handle for its row in a `ReorderableVStack`.
  ///
  /// Only the marked view initiates a reorder; the rest of the row is left free
  /// (so it can scroll, tap, host other gestures, etc.). If no view in a row is
  /// marked, the whole row acts as the handle. Outside a `ReorderableVStack` this
  /// is a no-op.
  func dragHandle() -> some View {
    modifier(DragHandleModifier())
  }
}

private struct DragHandleModifier: ViewModifier {
  @Environment(\.dragHandleContext) private var context

  @ViewBuilder
  func body(content: Content) -> some View {
    if let context {
      content
        .gesture(
          DragGesture(minimumDistance: 0, coordinateSpace: .named(ReorderableCoordinateSpace.name))
            .onChanged { context.onChanged($0.translation.height) }
            .onEnded { _ in context.onEnded() }
        )
        // Tell the enclosing stack this row owns a custom handle, so it can switch
        // off the default whole-row drag for this row's index.
        .preference(key: DragHandlePresenceKey.self, value: [context.index])
    } else {
      content
    }
  }
}

/// Named coordinate space shared by the stack and its `.dragHandle()` gestures, so
/// drag translation is measured against the (stable) stack rather than the moving row.
private enum ReorderableCoordinateSpace {
  static let name = "ReorderableVStack.drag"
}

/// Everything a `.dragHandle()` needs to drive the drag for the row it lives in.
/// Injected per row by `ReorderableVStack`.
private struct DragHandleContext {
  let index: Int
  let onChanged: (CGFloat) -> Void
  let onEnded: () -> Void
}

/// The set of row indices that exposed a `.dragHandle()`.
private struct DragHandlePresenceKey: PreferenceKey {
  static var defaultValue: Set<Int> { [] }
  static func reduce(value: inout Set<Int>, nextValue: () -> Set<Int>) {
    value.formUnion(nextValue())
  }
}


// MARK: -

private struct DragHandleContextKey: EnvironmentKey {
  static let defaultValue: DragHandleContext? = nil
}

private struct DragScaleKey: EnvironmentKey {
  static let defaultValue: CGFloat = 1.02
}

private struct ReorderableIsDraggingKey: EnvironmentKey {
  static let defaultValue: Bool = false
}

private struct ReorderableIsDraggableKey: EnvironmentKey {
  static let defaultValue: Bool = true
}

extension EnvironmentValues {
  fileprivate var dragHandleContext: DragHandleContext? {
    get { self[DragHandleContextKey.self] }
    set { self[DragHandleContextKey.self] = newValue }
  }

  /// `true` while this view's row is the one being reordered in a `ReorderableVStack`.
  var reorderableIsDragging: Bool {
    get { self[ReorderableIsDraggingKey.self] }
    set { self[ReorderableIsDraggingKey.self] = newValue }
  }

  /// `true` when this view's row can be reordered (i.e. the collection has more than one item).
  var reorderableIsDraggable: Bool {
    get { self[ReorderableIsDraggableKey.self] }
    set { self[ReorderableIsDraggableKey.self] = newValue }
  }

  /// Scale applied to the dragged row in a `ReorderableVStack`. Defaults to `1.02`.
  var dragScale: CGFloat {
    get { self[DragScaleKey.self] }
    set { self[DragScaleKey.self] = newValue }
  }
}

extension View {
  /// Overrides the scale applied to the dragged row in a `ReorderableVStack`.
  func dragScale(_ scale: CGFloat) -> some View {
    environment(\.dragScale, scale)
  }
}
