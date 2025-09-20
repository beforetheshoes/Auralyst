import SwiftUI

struct IntakeActionsModifier: ViewModifier {
    let onEdit: () -> Void
    let onDelete: () -> Void

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button("Edit", systemImage: "pencil", action: onEdit)
                Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }

                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(.blue)
            }
    }
}

extension View {
    func intakeActions(onEdit: @escaping () -> Void, onDelete: @escaping () -> Void) -> some View {
        modifier(IntakeActionsModifier(onEdit: onEdit, onDelete: onDelete))
    }
}
