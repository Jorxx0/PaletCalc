import SwiftUI

struct CargaCamionView: View {
    @State private var palets: [String] = ["Blanco", "Negro", "80 Fuerte", "Euro", "Otro"]
    @State private var paletSeleccionado: String = "Blanco"
    @State private var otroPalet: String = ""

    var body: some View {
        Form {
            Section(header: Text("Selecciona Palet")) {
                Picker("Palet", selection: $paletSeleccionado) {
                    ForEach(palets, id: \.self) { Text($0) }
                }
                .pickerStyle(.menu)

                if paletSeleccionado == "Otro" {
                    TextField("Especificar palet", text: $otroPalet)
                        .textFieldStyle(.roundedBorder)
                }
            }
            // Puedes añadir aquí más campos o secciones para la carga
        }
        .navigationTitle("Carga Camión")
    }
}
