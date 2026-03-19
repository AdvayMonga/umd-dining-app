import SwiftUI

struct FilterOverlay: View {
    @Binding var selectedHallIds: Set<String>
    let hallNames: [String: String]
    let allHallIds: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Dining Halls") {
                    ForEach(allHallIds, id: \.self) { hallId in
                        let name = hallNames[hallId] ?? hallId
                        Toggle(name, isOn: Binding(
                            get: { selectedHallIds.contains(hallId) },
                            set: { isOn in
                                if isOn {
                                    selectedHallIds.insert(hallId)
                                } else if selectedHallIds.count > 1 {
                                    selectedHallIds.remove(hallId)
                                }
                            }
                        ))
                    }
                }

                Section {
                    Button("Select All") {
                        selectedHallIds = Set(allHallIds)
                    }
                }
            }
            .navigationTitle("Filter by Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    FilterOverlay(
        selectedHallIds: .constant(Set(["19", "51", "16"])),
        hallNames: ["19": "Yahentamitsi", "51": "251 North", "16": "South Campus Diner"],
        allHallIds: ["19", "51", "16"]
    )
}
