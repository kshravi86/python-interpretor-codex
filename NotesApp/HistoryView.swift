import SwiftUI
import CoreData

struct HistoryView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \HydrationEntry.timestamp, ascending: false)],
        animation: .default)
    private var entries: FetchedResults<HydrationEntry>

    var body: some View {
        List {
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("\(entry.amountMl) ml")
                                .font(.headline)
                            Spacer()
                            Text(entry.timestamp ?? Date(), style: .time)
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                        HStack(spacing: 8) {
                            Text((entry.drinkType ?? "water").capitalized)
                                .foregroundColor(.secondary)
                            let caffeine = Int(entry.caffeineMg)
                            if caffeine > 0 {
                                Text("Caffeine: \(caffeine) mg")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .font(.caption)
                    }
                    .padding(.vertical, 4)
                }
                .onDelete(perform: delete)
        }
        .toolbar { EditButton() }
    }

    private func delete(at offsets: IndexSet) {
        withAnimation {
            offsets.map { entries[$0] }.forEach(viewContext.delete)
            try? viewContext.save()
        }
    }
}

#Preview {
    HistoryView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
