import SwiftUI

struct Precio: Identifiable, Codable {
    let id: UUID
    let cliente: String
    let palet: String
    let precio: Double

    private enum CodingKeys: String, CodingKey {
        case cliente, palet, precio
    }

    init(cliente: String, palet: String, precio: Double) {
        self.id = UUID()
        self.cliente = cliente
        self.palet = palet
        self.precio = precio
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.cliente = try container.decode(String.self, forKey: .cliente)
        self.palet = try container.decode(String.self, forKey: .palet)
        self.precio = try container.decode(Double.self, forKey: .precio)
        self.id = UUID()
    }
}

struct LineaAlbaran: Identifiable {
    let id = UUID()
    let palet: String
    let precioUnitario: Double
    var cantidad: Int? = nil
    var subtotal: Double { Double(cantidad ?? 0) * precioUnitario }
}

struct AlbaranGuardado: Codable {
    let fecha: Date
    let cliente: String
    let lineas: [LineaAlbaranGuardada]
    let total: Double
}

struct LineaAlbaranGuardada: Codable {
    let palet: String
    let precioUnitario: Double
    let cantidad: Int
    let subtotal: Double
}

struct AlbaranResumen: Identifiable {
    let id = UUID()
    let fecha: Date
    let cliente: String
    let total: Double
    let fileURL: URL
}

struct DetalleAlbaranView: View {
    let fileURL: URL
    @State private var albaran: AlbaranGuardado?
    
    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }()
    
    var body: some View {
        Group {
            if let albaran = albaran {
                VStack(alignment: .leading) {
                    Text("Cliente: \(albaran.cliente)").font(.headline)
                    Text("Fecha: \(dateFormatter.string(from: albaran.fecha))").font(.subheadline).foregroundColor(.secondary)
                    List(albaran.lineas, id: \.palet) { linea in
                        VStack(alignment: .leading) {
                            Text(linea.palet).font(.headline)
                            HStack {
                                Text("Cantidad: \(linea.cantidad)")
                                Spacer()
                                Text("Precio unitario: \(linea.precioUnitario, specifier: "%.2f") €")
                                Spacer()
                                Text("Subtotal: \(linea.subtotal, specifier: "%.2f") €").bold()
                            }
                            .font(.subheadline)
                        }
                        .padding(.vertical, 4)
                    }
                    HStack {
                        Spacer()
                        Text("Total: \(albaran.total, specifier: "%.2f") €").bold().font(.title2)
                        Spacer()
                    }
                    .padding()
                }
                .padding()
                .navigationTitle("Detalle Albarán")
            } else {
                ProgressView("Cargando...")
                    .onAppear(perform: cargarAlbaran)
            }
        }
    }
    
    func cargarAlbaran() {
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode(AlbaranGuardado.self, from: data)
            albaran = decoded
        } catch {
            print("Error cargando albarán: \(error)")
        }
    }
}

struct ListadoAlbaranesView: View {
    @State private var albaranes: [AlbaranResumen] = []
    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }()
    
    var body: some View {
        List {
            ForEach(albaranes) { albaran in
                NavigationLink(destination: DetalleAlbaranView(fileURL: albaran.fileURL)) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(albaran.cliente).font(.headline)
                            Text(dateFormatter.string(from: albaran.fecha)).font(.subheadline).foregroundColor(.secondary)
                        }
                        Spacer()
                        Text("\(albaran.total, specifier: "%.2f") €").bold()
                    }
                    .padding(.vertical, 4)
                }
            }
            .onDelete(perform: eliminarAlbaran)
        }
        .navigationTitle("Listado de Albaranes")
        .onAppear(perform: cargarAlbaranes)
    }
    
    func cargarAlbaranes() {
        albaranes.removeAll()
        let fm = FileManager.default
        let docsURL = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        do {
            let files = try fm.contentsOfDirectory(at: docsURL, includingPropertiesForKeys: nil)
            let albaranFiles = files.filter { $0.lastPathComponent.hasPrefix("albaran_") && $0.pathExtension == "json" }
            for file in albaranFiles {
                do {
                    let data = try Data(contentsOf: file)
                    let decoded = try JSONDecoder().decode(AlbaranGuardado.self, from: data)
                    let resumen = AlbaranResumen(fecha: decoded.fecha, cliente: decoded.cliente, total: decoded.total, fileURL: file)
                    albaranes.append(resumen)
                } catch {
                    print("Error decoding albaran file \(file): \(error)")
                }
            }
            albaranes.sort { $0.fecha > $1.fecha }
        } catch {
            print("Error loading albaran files: \(error)")
        }
    }
    
    func eliminarAlbaran(at offsets: IndexSet) {
        let fm = FileManager.default
        for index in offsets {
            let fileURL = albaranes[index].fileURL
            do {
                try fm.removeItem(at: fileURL)
                albaranes.remove(at: index)
            } catch {
                print("Error deleting albaran file \(fileURL): \(error)")
            }
        }
    }
}

struct ListadoClientesView: View {
    @Binding var tablaPrecios: [Precio]
    @Binding var clienteSeleccionado: String
    
    private var clientesUnicos: [String] {
        Array(Set(tablaPrecios.map { $0.cliente })).sorted()
    }
    
    private func paletsOrdenados(cliente: String) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for precio in tablaPrecios where precio.cliente == cliente {
            if !seen.contains(precio.palet) {
                ordered.append(precio.palet)
                seen.insert(precio.palet)
            }
        }
        return ordered
    }
    
    var body: some View {
        List {
            ForEach(clientesUnicos, id: \.self) { cliente in
                NavigationLink(destination: EditarClienteView(tablaPrecios: $tablaPrecios, clienteSeleccionado: $clienteSeleccionado, cliente: cliente, paletsUnicos: paletsOrdenados(cliente: cliente))) {
                    Text(cliente)
                }
            }
            .onDelete(perform: eliminarCliente)
        }
        .navigationTitle("Listado de Clientes")
    }
    
    // Elimina todas las entradas de tablaPrecios para el cliente seleccionado en la lista
    func eliminarCliente(at offsets: IndexSet) {
        let clientesAEliminar = offsets.map { clientesUnicos[$0] }
        for cliente in clientesAEliminar {
            tablaPrecios.removeAll(where: { $0.cliente == cliente })
            // Si el cliente eliminado estaba seleccionado, limpiar selección
            if clienteSeleccionado == cliente {
                clienteSeleccionado = tablaPrecios.map { $0.cliente }.first ?? ""
            }
        }
    }
}

struct ContentView: View {
    
    @State private var tablaPrecios: [Precio] = []
    @State private var clienteSeleccionado = ""
    @State private var lineas: [LineaAlbaran] = []
    @State private var mostrarConfirmacion = false
    @State private var mostrarCrearCliente = false
    @State private var mostrarListadoClientes = false
    
    private var clientesUnicos: [String] {
        Array(Set(tablaPrecios.map { $0.cliente })).sorted()
    }
    
    private var paletsOrdenados: [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for precio in tablaPrecios where precio.cliente == clienteSeleccionado {
            if !seen.contains(precio.palet) {
                ordered.append(precio.palet)
                seen.insert(precio.palet)
            }
        }
        return ordered
    }
    
    private var preciosPorPalet: [String: Double] {
        var dict: [String: Double] = [:]
        for palet in paletsOrdenados {
            dict[palet] = tablaPrecios.first(where: { $0.cliente == clienteSeleccionado && $0.palet == palet })?.precio ?? 0
        }
        return dict
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Selecciona Cliente")) {
                    Picker("Cliente", selection: $clienteSeleccionado) {
                        ForEach(clientesUnicos, id: \.self) { Text($0) }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .onChange(of: clienteSeleccionado) { _, _ in
                        inicializarLineas()
                    }
                    Button("Crear Cliente") {
                        mostrarCrearCliente = true
                    }
                    Button("Editar Cliente") {
                        mostrarListadoClientes = true
                    }
                }
                
                ForEach(paletsOrdenados, id: \.self) { palet in
                    Section(header: Text(palet)) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(preciosPorPalet[palet] ?? 0, specifier: "%.2f") €")
                                .frame(width: 70, alignment: .leading)
                            Spacer()
                            TextField("Cantidad", text: bindingLineaText(palet: palet))
                                .frame(width: 80)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.center)
                            Spacer()
                            Text("\(subtotalLinea(palet: palet), specifier: "%.2f") €")
                                .frame(width: 90, alignment: .trailing)
                        }
                    }
                }
                
                Section {
                    HStack {
                        Text("Total general").bold()
                        Spacer()
                        Text("\(totalGeneral, specifier: "%.2f") €").bold()
                    }
                    
                    Button("Guardar albarán") {
                        guardarAlbaran()
                    }
                    NavigationLink("Ver albaranes guardados") {
                        ListadoAlbaranesView()
                    }
                }
            }
            .navigationTitle("Albarán Palets")
            .alert("Albarán guardado", isPresented: $mostrarConfirmacion) {
                Button("OK", role: .cancel) {}
            }
            .onAppear { cargarPrecios() }
            .sheet(isPresented: $mostrarCrearCliente) {
                CrearClienteView(tablaPrecios: $tablaPrecios, clienteSeleccionado: $clienteSeleccionado, paletsUnicos: paletsOrdenados)
            }
            .sheet(isPresented: $mostrarListadoClientes) {
                NavigationView {
                    ListadoClientesView(tablaPrecios: $tablaPrecios, clienteSeleccionado: $clienteSeleccionado)
                }
            }
        }
    }
    
    private var totalGeneral: Double {
        lineas.map { $0.subtotal }.reduce(0, +)
    }
    
    func inicializarLineas() {
        lineas = paletsOrdenados.map { palet in
            LineaAlbaran(palet: palet, precioUnitario: preciosPorPalet[palet] ?? 0)
        }
    }
    
    func bindingLineaText(palet: String) -> Binding<String> {
        guard let index = lineas.firstIndex(where: { $0.palet == palet }) else {
            return .constant("")
        }
        return Binding<String>(
            get: { lineas[index].cantidad.map(String.init) ?? "" },
            set: { newValue in
                if let v = Int(newValue) { lineas[index].cantidad = v }
                else { lineas[index].cantidad = nil }
            }
        )
    }
    
    func subtotalLinea(palet: String) -> Double {
        lineas.first(where: { $0.palet == palet })?.subtotal ?? 0
    }
    
    func guardarAlbaran() {
        let guardadas = lineas.compactMap { linea -> LineaAlbaranGuardada? in
            guard let cantidad = linea.cantidad, cantidad > 0 else { return nil }
            return LineaAlbaranGuardada(
                palet: linea.palet,
                precioUnitario: linea.precioUnitario,
                cantidad: cantidad,
                subtotal: linea.subtotal
            )
        }
        
        let albaran = AlbaranGuardado(
            fecha: Date(),
            cliente: clienteSeleccionado,
            lineas: guardadas,
            total: totalGeneral
        )
        
        do {
            let data = try JSONEncoder().encode(albaran)
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("albaran_\(Int(Date().timeIntervalSince1970)).json")
            try data.write(to: url)
            mostrarConfirmacion = true
            print("Albarán guardado en: \(url)")
        } catch {
            print("Error guardando albarán: \(error)")
        }
    }
    
    func cargarPrecios() {
        guard let url = Bundle.main.url(forResource: "precios", withExtension: "json") else { return }
        do {
            let data = try Data(contentsOf: url)
            tablaPrecios = try JSONDecoder().decode([Precio].self, from: data)
            clienteSeleccionado = clientesUnicos.first ?? ""
            inicializarLineas()
        } catch {
            print("Error cargando precios: \(error)")
        }
    }
}

struct CrearClienteView: View {
    @Binding var tablaPrecios: [Precio]
    @Binding var clienteSeleccionado: String
    let paletsUnicos: [String]
    @Environment(\.presentationMode) private var presentationMode
    
    @State private var nuevoCliente: String = ""
    @State private var preciosPalets: [String: String] = [:]
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Nuevo Cliente")) {
                    TextField("Nombre del cliente", text: $nuevoCliente)
                }
                if !paletsUnicos.isEmpty {
                    Section(header: Text("Precios por Palet")) {
                        ForEach(paletsUnicos, id: \.self) { palet in
                            HStack {
                                Text(palet)
                                Spacer()
                                TextField("Precio", text: Binding(
                                    get: { preciosPalets[palet] ?? "" },
                                    set: { preciosPalets[palet] = $0 }
                                ))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                            }
                        }
                    }
                }
                Section {
                    Button("Agregar Cliente") {
                        agregarCliente()
                    }
                    .disabled(nuevoCliente.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("Crear Cliente")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
    
    func agregarCliente() {
        let clienteTrimmed = nuevoCliente.trimmingCharacters(in: .whitespaces)
        guard !clienteTrimmed.isEmpty else { return }
        
        // Por cada palet, obtener el precio introducido o usar 0
        for palet in paletsUnicos {
            let precioString = preciosPalets[palet]?.replacingOccurrences(of: ",", with: ".") ?? ""
            let precio = Double(precioString) ?? 0
            let nuevoPrecio = Precio(cliente: clienteTrimmed, palet: palet, precio: precio)
            tablaPrecios.append(nuevoPrecio)
        }
        clienteSeleccionado = clienteTrimmed
        presentationMode.wrappedValue.dismiss()
    }
}

struct EditarClienteView: View {
    @Binding var tablaPrecios: [Precio]
    @Binding var clienteSeleccionado: String
    let cliente: String
    let paletsUnicos: [String]
    @Environment(\.presentationMode) private var presentationMode
    
    @State private var nombreCliente: String = ""
    @State private var preciosPalets: [String: String] = [:]
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Editar Cliente")) {
                    TextField("Nombre del cliente", text: $nombreCliente)
                }
                
                Section(header: Text("Precios por Palet")) {
                    ForEach(paletsUnicos, id: \.self) { palet in
                        HStack {
                            Text(palet)
                            Spacer()
                            TextField("Precio", text: Binding(
                                get: { preciosPalets[palet] ?? "" },
                                set: { preciosPalets[palet] = $0 }
                            ))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                        }
                    }
                }
                
                Section {
                    Button("Guardar Cambios") {
                        guardarCambios()
                    }
                    .disabled(nombreCliente.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("Editar Cliente")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { presentationMode.wrappedValue.dismiss() }
                }
            }
            .onAppear {
                nombreCliente = cliente
                for palet in paletsUnicos {
                    if let precio = tablaPrecios.first(where: { $0.cliente == cliente && $0.palet == palet })?.precio {
                        preciosPalets[palet] = String(format: "%.2f", precio)
                    } else {
                        preciosPalets[palet] = ""
                    }
                }
            }
        }
    }
    
    func guardarCambios() {
        let clienteTrimmed = nombreCliente.trimmingCharacters(in: .whitespaces)
        guard !clienteTrimmed.isEmpty else { return }
        
        // Eliminar precios antiguos del cliente
        tablaPrecios.removeAll(where: { $0.cliente == cliente })
        
        // Guardar precios nuevos
        for palet in paletsUnicos {
            let precioString = preciosPalets[palet]?.replacingOccurrences(of: ",", with: ".") ?? ""
            let precio = Double(precioString) ?? 0
            let nuevoPrecio = Precio(cliente: clienteTrimmed, palet: palet, precio: precio)
            tablaPrecios.append(nuevoPrecio)
        }
        
        clienteSeleccionado = clienteTrimmed
        presentationMode.wrappedValue.dismiss()
    }
}
