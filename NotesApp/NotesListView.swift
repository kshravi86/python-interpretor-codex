import SwiftUI

struct NotesListView: View {
    var body: some View {
        HistoryView()
    }
}

#Preview {
    NotesListView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
