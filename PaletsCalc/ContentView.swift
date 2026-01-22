import SwiftUI

// Simple reusable debug logger
func debugLog(_ message: String, file: String = #fileID, function: String = #function, line: Int = #line) {
    print("[DEBUG] \(file):\(line) \(function) — \(message)")
}

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

// Reusable row view for palet/linea
struct FilaPaletView<Content: View>: View {
    let activa: Bool
    let content: Content

    init(activa: Bool, @ViewBuilder content: () -> Content) {
        self.activa = activa
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            content
        }
        .padding(6)
        .background(
            Capsule()
                .stroke(activa ? Color.green : Color.clear, lineWidth: 2)
        )
    }
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
    @State private var lineas: [EditableLineaAlbaran] = []
    @State private var isSaving = false
    @Environment(\.dismiss) private var dismiss

    @FocusState private var focusedIndex: Int?

    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }()

    struct EditableLineaAlbaran: Identifiable {
        let id = UUID()
        let palet: String
        let precioUnitario: Double
        var cantidad: String // as text for binding
        var subtotal: Double {
            let cantidadInt = Int(cantidad) ?? 0
            return Double(cantidadInt) * precioUnitario
        }
    }

    var totalGeneral: Double {
        lineas.map { $0.subtotal }.reduce(0, +)
    }

    var body: some View {
        Group {
            if let albaran = albaran {
                Form {
                    Section(header: Text("Cliente y Fecha")) {
                        Text("Cliente: \(albaran.cliente)").font(.headline)
                        Text("Fecha: \(dateFormatter.string(from: albaran.fecha))").font(.subheadline).foregroundColor(.secondary)
                    }
                    ForEach(lineas.indices, id: \.self) { i in
                        let lineaActual = lineas[i]
                        let cantidadInt = Int(lineaActual.cantidad) ?? 0
                        let subtotal = Double(cantidadInt) * lineaActual.precioUnitario
                        let activa = cantidadInt > 0
                        let bindingCantidad = bindingLineaText(index: i)
                        Section(header: Text(lineaActual.palet)) {
                            FilaPaletView(activa: activa) {
                                Text(String(format: "%.2f €", lineaActual.precioUnitario))
                                    .frame(width: 70, alignment: .leading)
                                Spacer()
                                TextField("Cantidad", text: bindingCantidad)
                                    .frame(width: 80)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.center)
                                    .focused($focusedIndex, equals: i)
                                    .onChange(of: lineaActual.cantidad) { oldValue, newValue in
                                        debugLog("Cantidad cambiada para palet=\(lineaActual.palet) a=\(lineaActual.cantidad)")
                                        lineas = lineas.map { $0 }
                                    }
                                Spacer()
                                Text(String(format: "%.2f €", subtotal))
                                    .frame(width: 90, alignment: .trailing)
                            }
                        }
                    }
                    .onTapGesture {
                        debugLog("Tap para ocultar teclado en DetalleAlbaranView")
                        focusedIndex = nil
                    }
                    Section {
                        HStack {
                            Text("Total general").bold()
                            Spacer()
                            Text("\(totalGeneral, specifier: "%.2f") €").bold()
                        }
                        Button("Guardar cambios") {
                            debugLog("Tap en 'Guardar cambios'")
                            guardarCambios()
                        }
                        .disabled(isSaving)
                    }
                }
                .navigationTitle("Detalle Albarán")
            } else {
                ProgressView("Cargando...")
                    .onAppear(perform: cargarAlbaran)
            }
        }
    }

    func bindingLineaText(index: Int) -> Binding<String> {
        Binding<String>(
            get: { lineas[index].cantidad },
            set: { newValue in
                lineas[index].cantidad = newValue
            }
        )
    }

    func cargarAlbaran() {
        debugLog("Cargando albarán desde URL=\(fileURL.path)")
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode(AlbaranGuardado.self, from: data)
            albaran = decoded
            debugLog("Albarán decodificado — cliente=\(decoded.cliente), fecha=\(decoded.fecha), lineas=\(decoded.lineas.count)")

            // Cargar precios.json del bundle
            guard let preciosURL = Bundle.main.url(forResource: "precios", withExtension: "json") else {
                // Si no hay precios, solo precarga lineas del albarán
                lineas = decoded.lineas.map { linea in
                    EditableLineaAlbaran(
                        palet: linea.palet,
                        precioUnitario: linea.precioUnitario,
                        cantidad: String(linea.cantidad)
                    )
                }
                debugLog("precios.json no encontrado. Cargando solo líneas del albarán guardado (\(lineas.count) líneas)")
                return
            }
            let preciosData = try Data(contentsOf: preciosURL)
            let tablaPrecios = try JSONDecoder().decode([Precio].self, from: preciosData)

            // Obtener todos los palets disponibles para el cliente del albarán, respetando el orden de precios.json
            let cliente = decoded.cliente
            var paletsVistos: Set<String> = []
            var paletsOrdenados: [String] = []
            var preciosPorPalet: [String: Double] = [:]
            for precio in tablaPrecios where precio.cliente == cliente {
                if !paletsVistos.contains(precio.palet) {
                    paletsOrdenados.append(precio.palet)
                    paletsVistos.insert(precio.palet)
                }
                preciosPorPalet[precio.palet] = precio.precio
            }

            // Diccionario de lineas guardadas por palet
            let lineasGuardadasPorPalet = Dictionary(uniqueKeysWithValues: decoded.lineas.map { ($0.palet, $0) })

            // Construir lineas: para cada palet del cliente en precios.json, si está en el albarán, usar la línea guardada; si no, crear nueva con cantidad "0"
            var nuevasLineas: [EditableLineaAlbaran] = []
            for palet in paletsOrdenados {
                if let guardada = lineasGuardadasPorPalet[palet] {
                    nuevasLineas.append(
                        EditableLineaAlbaran(
                            palet: guardada.palet,
                            precioUnitario: guardada.precioUnitario,
                            cantidad: String(guardada.cantidad)
                        )
                    )
                } else {
                    let precioUnitario = preciosPorPalet[palet] ?? 0
                    nuevasLineas.append(
                        EditableLineaAlbaran(
                            palet: palet,
                            precioUnitario: precioUnitario,
                            cantidad: "0"
                        )
                    )
                }
            }
            // Si había lineas en el albarán para palets que ya no están en precios.json, las ignoramos (solo se muestran los palets disponibles para el cliente en precios.json)
            lineas = nuevasLineas
            debugLog("Lineas preparadas desde precios.json — total=\(lineas.count)")
        } catch {
            debugLog("Error cargando albarán: \(error)")
        }
    }

    func guardarCambios() {
        guard let albaran = albaran else { return }
        debugLog("Guardando cambios en albarán de cliente=\(albaran.cliente) a URL=\(fileURL.lastPathComponent)")
        isSaving = true
        // Construir nuevas líneas
        let nuevasLineas: [LineaAlbaranGuardada] = lineas.map { linea in
            let cantidadInt = Int(linea.cantidad) ?? 0
            let subtotal = Double(cantidadInt) * linea.precioUnitario
            return LineaAlbaranGuardada(
                palet: linea.palet,
                precioUnitario: linea.precioUnitario,
                cantidad: cantidadInt,
                subtotal: subtotal
            )
        }
        let nuevoTotal = nuevasLineas.map { $0.subtotal }.reduce(0, +)
        let albaranActualizado = AlbaranGuardado(
            fecha: albaran.fecha,
            cliente: albaran.cliente,
            lineas: nuevasLineas,
            total: nuevoTotal
        )
        do {
            let data = try JSONEncoder().encode(albaranActualizado)
            try data.write(to: fileURL, options: .atomic)
            debugLog("Albarán actualizado guardado. Total=\(nuevoTotal), líneas=\(nuevasLineas.count)")
            self.albaran = albaranActualizado
            // Recargar lineas para reflejar los posibles cambios
            self.lineas = nuevasLineas.map { linea in
                EditableLineaAlbaran(
                    palet: linea.palet,
                    precioUnitario: linea.precioUnitario,
                    cantidad: String(linea.cantidad)
                )
            }
        } catch {
            debugLog("Error guardando cambios: \(error)")
        }
        isSaving = false
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
        debugLog("Cargando listado de albaranes")
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
                    debugLog("Albarán cargado: \(resumen.fileURL.lastPathComponent) — cliente=\(resumen.cliente), total=\(resumen.total)")
                } catch {
                    debugLog("Error decodificando albarán \(file.lastPathComponent): \(error)")
                }
            }
            albaranes.sort { $0.fecha > $1.fecha }
        } catch {
            debugLog("Error listando ficheros de albaranes: \(error)")
        }
    }
    
    func eliminarAlbaran(at offsets: IndexSet) {
        let fm = FileManager.default
        for index in offsets {
            let fileURL = albaranes[index].fileURL
            debugLog("Eliminando albarán: \(fileURL.lastPathComponent)")
            do {
                try fm.removeItem(at: fileURL)
                albaranes.remove(at: index)
            } catch {
                debugLog("Error eliminando albarán \(fileURL.lastPathComponent): \(error)")
            }
        }
    }
}

struct ListadoClientesView: View {
    @Binding var tablaPrecios: [Precio]
    @Binding var clienteSeleccionado: String
    
    @AppStorage("clientePorDefecto") private var clientePorDefecto: String = ""
    
    private var clientesUnicos: [String] {
        // Orden deseado por almacén
        let ordenPrefijos = ["ME-", "BA-", "DB-"]

        // Obtener clientes únicos respetando orden de aparición
        var vistos: Set<String> = []
        let clientes = tablaPrecios.compactMap { precio -> String? in
            guard !vistos.contains(precio.cliente) else { return nil }
            vistos.insert(precio.cliente)
            return precio.cliente
        }

        return clientes.sorted { a, b in
            // "Otro" siempre al final
            if a == "Otro" { return false }
            if b == "Otro" { return true }

            let prefijoA = ordenPrefijos.firstIndex { a.hasPrefix($0) } ?? Int.max
            let prefijoB = ordenPrefijos.firstIndex { b.hasPrefix($0) } ?? Int.max

            if prefijoA != prefijoB {
                return prefijoA < prefijoB
            }

            // Mismo prefijo → orden alfabético dentro del grupo
            return a < b
        }
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
            Section(header: Text("Cliente predeterminado")) {
                Picker("Predeterminado", selection: $clientePorDefecto) {
                    ForEach(clientesUnicos, id: \.self) { cliente in
                        Text(cliente)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: clientePorDefecto) { oldValue, newValue in
                    debugLog("Cliente predeterminado actualizado: \(clientePorDefecto)")
                }
                if !clientePorDefecto.isEmpty {
                    Text("Actual: \(clientePorDefecto)").font(.footnote).foregroundColor(.secondary)
                }
            }
            
            ForEach(clientesUnicos, id: \.self) { cliente in
                NavigationLink(destination: EditarClienteView(tablaPrecios: $tablaPrecios, clienteSeleccionado: $clienteSeleccionado, cliente: cliente, paletsUnicos: paletsOrdenados(cliente: cliente))) {
                    if cliente == clientePorDefecto {
                        Label(cliente, systemImage: "star.fill")
                    } else {
                        Text(cliente)
                    }
                }
            }
            .onDelete(perform: eliminarCliente)
        }
        .navigationTitle("Listado de Clientes")
    }
    
    // Elimina todas las entradas de tablaPrecios para el cliente seleccionado en la lista
    func eliminarCliente(at offsets: IndexSet) {
        debugLog("Eliminar clientes en índices: \(offsets.map { $0 })")
        let clientesAEliminar = offsets.map { clientesUnicos[$0] }
        for cliente in clientesAEliminar {
            debugLog("Eliminando cliente: \(cliente)")
            tablaPrecios.removeAll(where: { $0.cliente == cliente })
            // Si el cliente eliminado estaba seleccionado, limpiar selección
            if clienteSeleccionado == cliente {
                clienteSeleccionado = tablaPrecios.map { $0.cliente }.first ?? ""
                debugLog("Cliente seleccionado eliminado. Nueva selección=\(clienteSeleccionado)")
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
    @FocusState private var focusedIndex: Int?
    // NUEVO: Estado para mostrar alert con el total del albarán
    @State private var mostrarTotalAlbaran = false
    @State private var totalAlbaranMostrado: Double = 0

    @AppStorage("clientePorDefecto") private var clientePorDefecto: String = ""
    
    private var clientesUnicos: [String] {
        // Orden deseado por almacén
        let ordenPrefijos = ["ME-", "BA-", "DB-"]

        // Obtener clientes únicos respetando orden de aparición
        var vistos: Set<String> = []
        let clientes = tablaPrecios.compactMap { precio -> String? in
            guard !vistos.contains(precio.cliente) else { return nil }
            vistos.insert(precio.cliente)
            return precio.cliente
        }

        return clientes.sorted { a, b in
            // "Otro" siempre al final
            if a == "Otro" { return false }
            if b == "Otro" { return true }

            let prefijoA = ordenPrefijos.firstIndex { a.hasPrefix($0) } ?? Int.max
            let prefijoB = ordenPrefijos.firstIndex { b.hasPrefix($0) } ?? Int.max

            if prefijoA != prefijoB {
                return prefijoA < prefijoB
            }

            // Mismo prefijo → orden alfabético dentro del grupo
            return a < b
        }
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
                    HStack {
                        Picker("Cliente", selection: $clienteSeleccionado) {
                            ForEach(clientesUnicos, id: \.self) { Text($0) }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .onChange(of: clienteSeleccionado) { _, _ in
                            debugLog("Cliente seleccionado cambiado a: \(clienteSeleccionado)")
                            inicializarLineas()
                        }
                        
                        Spacer()
                        
                        // Se ha eliminado el botón y label de marcar cliente como predeterminado de aquí según instrucciones
                    }
                }

                ForEach(lineas.indices, id: \.self) { i in
                    let lineaActual = lineas[i]
                    let cantidadInt = lineaActual.cantidad ?? 0
                    let subtotal = Double(cantidadInt) * lineaActual.precioUnitario
                    let activa = cantidadInt > 0
                    let bindingCantidad = bindingLineaText(index: i)
                    Section(header: Text(lineaActual.palet)) {
                        FilaPaletView(activa: activa) {
                            Text(String(format: "%.2f €", lineaActual.precioUnitario))
                                .frame(width: 70, alignment: .leading)
                            Spacer()
                            TextField("Cantidad", text: bindingCantidad)
                                .frame(width: 80)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.center)
                                .focused($focusedIndex, equals: i)
                                .onChange(of: lineaActual.cantidad) { oldValue, newValue in
                                    debugLog("Cantidad cambiada para palet=\(lineaActual.palet) a=\(String(describing: newValue))")
                                }
                            Spacer()
                            Text(String(format: "%.2f €", subtotal))
                                .frame(width: 90, alignment: .trailing)
                        }
                    }
                }
                .onTapGesture {
                    debugLog("Tap para ocultar teclado en ContentView")
                    focusedIndex = nil
                }

                Section {
                    Button("Albaranar") {
                        debugLog("Tap en 'Albaranar' — cliente=\(clienteSeleccionado), total=\(totalGeneral)")

                        let guardadas = lineas.compactMap { linea -> LineaAlbaranGuardada? in
                            guard let cantidad = linea.cantidad, cantidad > 0 else { return nil }
                            return LineaAlbaranGuardada(
                                palet: linea.palet,
                                precioUnitario: linea.precioUnitario,
                                cantidad: cantidad,
                                subtotal: linea.subtotal
                            )
                        }

                        let total = totalGeneral
                        let albaran = AlbaranGuardado(
                            fecha: Date(),
                            cliente: clienteSeleccionado,
                            lineas: guardadas,
                            total: total
                        )

                        do {
                            let data = try JSONEncoder().encode(albaran)
                            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                                .appendingPathComponent("albaran_\(Int(Date().timeIntervalSince1970)).json")
                            try data.write(to: url)
                            // Guardar el total mostrado y mostrar el alert
                            totalAlbaranMostrado = total
                            mostrarTotalAlbaran = true
                            debugLog("Albarán guardado en: \(url.lastPathComponent)")
                        } catch {
                            debugLog("Error guardando albarán: \(error)")
                        }
                    }
                    Button("Borrar albarán actual") {
                        debugLog("Tap en 'Borrar albarán actual'")
                        borrarAlbaranActual()
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }

                // Nueva sección con los botones de acción, al final del Form
                Section {
                    Button("Crear cliente") {
                        debugLog("Tap en 'Crear cliente'")
                        mostrarCrearCliente = true
                    }
                    Button("Editar cliente") {
                        debugLog("Tap en 'Editar cliente'")
                        mostrarListadoClientes = true
                    }
                    NavigationLink("Ver albaranes guardados") {
                        ListadoAlbaranesView()
                    }
                    .simultaneousGesture(TapGesture().onEnded { debugLog("Navegar a ListadoAlbaranesView") })

                    NavigationLink("Cargar Camión") {
                        CargarCamionView()
                    }
                    .simultaneousGesture(TapGesture().onEnded { debugLog("Navegar a CargarCamionView") })
                    
                    NavigationLink("Inventario") {
                        InventarioView()
                    }
                    .simultaneousGesture(TapGesture().onEnded { debugLog("Navegar a InventarioView") })
                    
                    NavigationLink("Bolso") {
                        BolsoView()
                    }
                    .simultaneousGesture(TapGesture().onEnded { debugLog("Navegar a BolsoView") })
                    
                }
            }
            .navigationTitle("Albarán Palets")
            // .toolbar eliminado
            .alert("Total del albarán: \(totalAlbaranMostrado, specifier: "%.2f") €", isPresented: $mostrarTotalAlbaran) {
                Button("OK", role: .cancel) { }
            }
            .onAppear {
                cargarPrecios()
                // Seleccionar clientePorDefecto si está disponible y válido
                if !clientePorDefecto.isEmpty && clientesUnicos.contains(clientePorDefecto) {
                    clienteSeleccionado = clientePorDefecto
                    inicializarLineas()
                    debugLog("Cliente por defecto seleccionado al aparecer: \(clientePorDefecto)")
                }
            }
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
        debugLog("Inicializando líneas para cliente=\(clienteSeleccionado) con \(paletsOrdenados.count) palets")
        lineas = paletsOrdenados.map { palet in
            LineaAlbaran(palet: palet, precioUnitario: preciosPorPalet[palet] ?? 0)
        }
        debugLog("Líneas inicializadas: \(lineas.count)")
    }
    
    func bindingLineaText(index: Int) -> Binding<String> {
        Binding<String>(
            get: { lineas[index].cantidad.map(String.init) ?? "" },
            set: { newValue in
                debugLog("Edición cantidad index=\(index) palet=\(lineas[index].palet) valor=\(newValue)")
                if let v = Int(newValue) { lineas[index].cantidad = v }
                else { lineas[index].cantidad = nil }
            }
        )
    }
    
    func subtotalLinea(palet: String) -> Double {
        lineas.first(where: { $0.palet == palet })?.subtotal ?? 0
    }
    
    func guardarAlbaran() {
        // Ahora todo se maneja directamente en el botón "Albaranar"
        debugLog("Función guardarAlbaran llamada, pero gestionada por 'Albaranar' button")
    }

    func borrarAlbaranActual() {
        debugLog("Borrando albarán actual (reseteando cantidades)")
        for i in lineas.indices {
            lineas[i].cantidad = nil
        }
        debugLog("Cantidades reseteadas a vacío")
        focusedIndex = nil
    }
    
    func cargarPrecios() {
        debugLog("Cargando precios desde bundle")
        guard let url = Bundle.main.url(forResource: "precios", withExtension: "json") else { return }
        do {
            let data = try Data(contentsOf: url)
            tablaPrecios = try JSONDecoder().decode([Precio].self, from: data)
            if !clientePorDefecto.isEmpty && clientesUnicos.contains(clientePorDefecto) {
                clienteSeleccionado = clientePorDefecto
            } else if let baAlmacen = clientesUnicos.first(where: { $0 == "BA-Almacén" }) {
                clienteSeleccionado = baAlmacen
            } else {
                clienteSeleccionado = clientesUnicos.first ?? ""
            }
            debugLog("Precios cargados: \(tablaPrecios.count) entradas. Cliente por defecto=\(clienteSeleccionado)")
            inicializarLineas()
        } catch {
            debugLog("Error cargando precios: \(error)")
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
        debugLog("Agregando cliente nuevo: \(nuevoCliente)")
        let clienteTrimmed = nuevoCliente.trimmingCharacters(in: .whitespaces)
        guard !clienteTrimmed.isEmpty else { return }
        
        // Por cada palet, obtener el precio introducido o usar 0
        for palet in paletsUnicos {
            let precioString = preciosPalets[palet]?.replacingOccurrences(of: ",", with: ".") ?? ""
            let precio = Double(precioString) ?? 0
            debugLog("Asignando precio palet=\(palet) precio=\(precio)")
            let nuevoPrecio = Precio(cliente: clienteTrimmed, palet: palet, precio: precio)
            tablaPrecios.append(nuevoPrecio)
        }
        clienteSeleccionado = clienteTrimmed
        debugLog("Cliente creado y seleccionado: \(clienteSeleccionado)")
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
    
    @AppStorage("clientePorDefecto") private var clientePorDefecto: String = ""

    private var clientesUnicos: [String] {
        Set(tablaPrecios.map { $0.cliente }).sorted()
    }
    
    var body: some View {
        NavigationView {
            Form {
                // Sección superior: nombre cliente editable
                Section(header: Text("Editar Cliente")) {
                    TextField("Nombre del cliente", text: $nombreCliente)
                }
                
                // La sección de cliente predeterminado ha sido eliminada según instrucciones
                
                // Una sección por cada palet, con layout tipo albarán
                ForEach(paletsUnicos, id: \.self) { palet in
                    Section(header: Text(palet)) {
                        HStack(alignment: .firstTextBaseline) {
                            // Precio unitario a la izquierda (texto fijo, no editable)
                            let precioFijo = tablaPrecios.first(where: { $0.cliente == cliente && $0.palet == palet })?.precio
                            Text("\(precioFijo ?? 0, specifier: "%.2f") €")
                                .frame(width: 70, alignment: .leading)
                            Spacer()
                            // Campo editable de texto para el precio
                            TextField("Precio", text: Binding(
                                get: { preciosPalets[palet] ?? "" },
                                set: { preciosPalets[palet] = $0 }
                            ))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.center)
                            .frame(width: 80)
                            Spacer()
                        }
                    }
                }
                // Botón en sección final
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
                debugLog("EditarClienteView onAppear — cliente=\(cliente)")
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
        debugLog("Guardando cambios de cliente — antiguo=\(cliente), nuevo=\(clienteTrimmed)")
        guard !clienteTrimmed.isEmpty else { return }
        
        // Eliminar precios antiguos del cliente
        tablaPrecios.removeAll(where: { $0.cliente == cliente })
        
        // Guardar precios nuevos
        for palet in paletsUnicos {
            let precioString = preciosPalets[palet]?.replacingOccurrences(of: ",", with: ".") ?? ""
            let precio = Double(precioString) ?? 0
            debugLog("Nuevo precio palet=\(palet) precio=\(precio)")
            let nuevoPrecio = Precio(cliente: clienteTrimmed, palet: palet, precio: precio)
            tablaPrecios.append(nuevoPrecio)
        }
        
        clienteSeleccionado = clienteTrimmed
        debugLog("Cliente actualizado y seleccionado: \(clienteSeleccionado)")
        presentationMode.wrappedValue.dismiss()
    }
}

// MARK: - INVENTARIO (REHECHO Y FUNCIONAL)

struct InventarioRegistro: Identifiable, Codable, Equatable {
    let id: UUID
    let tipoPalet: String
    var pilas: Int
    let paletsPorPila: Int

    var totalPalets: Int {
        pilas * paletsPorPila
    }

    init(tipoPalet: String, pilas: Int, paletsPorPila: Int) {
        self.id = UUID()
        self.tipoPalet = tipoPalet
        self.pilas = pilas
        self.paletsPorPila = paletsPorPila
    }
}

struct InventarioView: View {
    @State private var inventario: [InventarioRegistro] = []
    @State private var mostrarConfirmacionBorrar = false

    let tiposPalets: [(String, Int)] = [
        ("Blanco", 18),
        ("Semi", 18),
        ("Negro", 18),
        ("80 Fuerte", 18),
        ("Azul", 18),
        ("Rojo", 18),
        ("Marron", 18),
        ("Metro", 18),
        ("80 Fino", 19),
        ("Euro Roto", 21),
        ("80 Roto", 23),
        ("80 x 60", 50),
        ("80 x 60 Roto", 50)
    ]

    var body: some View {
        Form {
            ForEach(inventario.indices, id: \.self) { i in
                let registro = inventario[i]

                Section(header: Text(registro.tipoPalet)) {
                    HStack {
                        TextField("Pilas", value: bindingPilas(i), format: .number)
                            .keyboardType(.numberPad)
                            .frame(width: 80)

                        Spacer()

                        Text("Palets/pila: \(registro.paletsPorPila)")
                            .foregroundColor(.secondary)

                        Spacer()

                        Text("Total: \(registro.totalPalets)")
                            .bold()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("(\(registro.pilas) pilas) × (\(registro.paletsPorPila) por pila) = \(registro.totalPalets) palets")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 2)
                    .padding(6)
                    .background(
                        Capsule()
                            .stroke(bordeColor(pilas: registro.pilas), lineWidth: 2)
                    )

                    HStack {
                        Button("+1 pila") {
                            debugLog("+1 pila en tipo=\(inventario[i].tipoPalet)")
                            inventario[i].pilas += 1
                        }
                        .buttonStyle(.borderedProminent)

                        Button("-1 pila") {
                            debugLog("-1 pila en tipo=\(inventario[i].tipoPalet)")
                            if inventario[i].pilas > 0 {
                                inventario[i].pilas -= 1
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)

                        Spacer()
                    }
                }
            }

            Section {
                Button("Borrar todo") {
                    mostrarConfirmacionBorrar = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .alert("Confirmar borrado", isPresented: $mostrarConfirmacionBorrar) {
                    Button("Cancelar", role: .cancel) {}
                    Button("Borrar", role: .destructive) {
                        debugLog("Borrando todas las pilas del inventario")
                        for i in inventario.indices {
                            inventario[i].pilas = 0
                        }
                    }
                } message: {
                    Text("¿Estás seguro que quieres borrar todas las pilas?")
                }
            }
        }
        .navigationTitle("Inventario")
        .onAppear {
            debugLog("InventarioView onAppear")
            cargarInventario()
            inicializarSiHaceFalta()
        }
        .onChange(of: inventario) { _, _ in
            debugLog("Inventario modificado — registros=\(inventario.count)")
            guardarInventario()
        }
        .onDisappear {
            guardarInventario()
        }
    }

    // MARK: - Helpers
    func inicializarSiHaceFalta() {
        if !inventario.isEmpty { return }

        inventario = tiposPalets.map { tipo, paletsPorPila in
            InventarioRegistro(
                tipoPalet: tipo,
                pilas: 0,
                paletsPorPila: paletsPorPila
            )
        }
    }

    func bindingPilas(_ index: Int) -> Binding<Int> {
        Binding(
            get: { inventario[index].pilas },
            set: { inventario[index].pilas = $0 }
        )
    }

    // MARK: - Persistencia

    func inventarioURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("inventario.json")
    }

    func guardarInventario() {
        do {
            let data = try JSONEncoder().encode(inventario)
            try data.write(to: inventarioURL(), options: .atomic)
            debugLog("Inventario guardado en \(inventarioURL().lastPathComponent)")
        } catch {
            debugLog("Error guardando inventario: \(error)")
        }
    }

    func cargarInventario() {
        let url = inventarioURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        do {
            let data = try Data(contentsOf: url)
            inventario = try JSONDecoder().decode([InventarioRegistro].self, from: data)
            debugLog("Inventario cargado — registros=\(inventario.count)")
        } catch {
            debugLog("Error cargando inventario: \(error)")
        }
    }
}


// Borde de color según las pilas
func bordeColor(pilas: Int) -> Color {
    debugLog("Calculando color borde para pilas=\(pilas)")
    switch pilas {
    case 0...2:
        return Color.orange
    case 3...10:
        return Color.green
    default:
        return Color.red
    }
}


// MARK: - Calculadora de Bolso (Dinero)

struct Denominacion: Identifiable {
    let id = UUID()
    let nombre: String
    let valor: Double
    var cantidad: Int
    var subtotal: Double {
        Double(cantidad) * valor
    }
}

struct BolsoView: View {
    @State private var denominaciones: [Denominacion] = [
        Denominacion(nombre: "50€", valor: 50, cantidad: 0),
        Denominacion(nombre: "20€", valor: 20, cantidad: 0),
        Denominacion(nombre: "10€", valor: 10, cantidad: 0),
        Denominacion(nombre: "5€", valor: 5, cantidad: 0),
        Denominacion(nombre: "2€", valor: 2, cantidad: 0),
        Denominacion(nombre: "1€", valor: 1, cantidad: 0),
        Denominacion(nombre: "50 cent", valor: 0.5, cantidad: 0),
        Denominacion(nombre: "20 cent", valor: 0.2, cantidad: 0),
        Denominacion(nombre: "10 cent", valor: 0.1, cantidad: 0)
    ]

    @State private var mostrarConfirmacionBorrar = false

    var total: Double {
        denominaciones.map { $0.subtotal }.reduce(0, +)
    }

    var body: some View {
        Form {
            ForEach(denominaciones.indices, id: \.self) { i in
                let denom = denominaciones[i]
                Section(header: Text(denom.nombre)) {
                    HStack {
                        TextField("Cantidad", value: bindingCantidad(i), format: .number)
                            .keyboardType(.numberPad)
                            .frame(width: 80)
                        Spacer()
                        Text(String(format: "Subtotal: %.2f €", denom.subtotal))
                    }
                }
            }

            Section {
                HStack {
                    Text("Total general").bold()
                    Spacer()
                    Text(String(format: "%.2f €", total)).bold()
                }
            }

            Section {
                Button("Borrar todo") {
                    mostrarConfirmacionBorrar = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .navigationTitle("Bolso")
        .alert("Confirmar borrado", isPresented: $mostrarConfirmacionBorrar) {
            Button("Cancelar", role: .cancel) {}
            Button("Borrar", role: .destructive) {
                debugLog("Borrando todas las cantidades del bolso")
                for i in denominaciones.indices {
                    denominaciones[i].cantidad = 0
                }
            }
        } message: {
            Text("¿Estás seguro que quieres borrar todas las cantidades?")
        }
    }

    func bindingCantidad(_ index: Int) -> Binding<Int> {
        Binding(
            get: { denominaciones[index].cantidad },
            set: {
                debugLog("Cambio cantidad bolso index=\(index) denom=\(denominaciones[index].nombre) valor=\($0)")
                denominaciones[index].cantidad = $0
            }
        )
    }
}


// MARK: - Nueva CargarCamionView

// Modelo agrupado de palets para el camión
struct PaletCamion: Identifiable, Hashable, Codable {
    let id: UUID
    let tipo: String
    let paletsPorPila: Int
    var pilas: Int

    // Identificador único por tipo+paletsPorPila para agrupación lógica
    func agrupacionKey() -> String {
        "\(tipo)_\(paletsPorPila)"
    }

    init(tipo: String, paletsPorPila: Int, pilas: Int) {
        self.id = UUID()
        self.tipo = tipo
        self.paletsPorPila = paletsPorPila
        self.pilas = pilas
    }
}

struct CargarCamionView: View {
    // Tipos de palet sugeridos
    private let tiposPalet: [String] = [
        "Blanco", "Semi", "Negro", "80 Fuerte", "80 Fino", "Azul", "Rojo", "Marron", "Metro", "BA", "Botellero", "12 tacos", "Minis", "80x60", "Otro"
    ]

    @State private var tipoSeleccionado: String = "Blanco"
    @State private var paletsPorPila: String = ""
    @State private var lineasCamion: [PaletCamion] = []
    @State private var mostrarPrimerConfirmacion = false
    @State private var mostrarSegundaConfirmacion = false

    // Agrupa lineasCamion por tipo de palet, luego por paletsPorPila
    private var agrupadoPorTipo: [String: [PaletCamion]] {
        let agrupados = Dictionary(grouping: lineasCamion) { $0.tipo }
        // Ordena los arrays internos por paletsPorPila ascendente
        var resultado: [String: [PaletCamion]] = [:]
        for (tipo, lineas) in agrupados {
            resultado[tipo] = lineas.sorted(by: { $0.paletsPorPila < $1.paletsPorPila })
        }
        return resultado
    }

    var body: some View {
        Form {
            Section(header: Text("Añadir palets al camión")) {
                Picker("Tipo de palet", selection: $tipoSeleccionado) {
                    ForEach(tiposPalet, id: \.self) { tipo in
                        Text(tipo)
                    }
                }
                .pickerStyle(.menu)
                TextField("Palets por pila", text: $paletsPorPila)
                    .keyboardType(.numberPad)
                    .frame(width: 150)
                Button("Añadir") {
                    if let cantidad = Int(paletsPorPila), cantidad > 0 {
                        // Buscar si ya existe una línea con este tipo y paletsPorPila
                        if let idx = lineasCamion.firstIndex(where: { $0.tipo == tipoSeleccionado && $0.paletsPorPila == cantidad }) {
                            // Si existe, incrementar el número de pilas
                            lineasCamion[idx].pilas += 1
                        } else {
                            // Si no existe, añadir nueva línea con 1 pila
                            lineasCamion.append(PaletCamion(tipo: tipoSeleccionado, paletsPorPila: cantidad, pilas: 1))
                        }
                        // Guardar automáticamente
                        guardarCamion()
                        // paletsPorPila = ""  // Ya no se borra automáticamente tras añadir
                    }
                }
                .disabled(Int(paletsPorPila) == nil || paletsPorPila.isEmpty)
            }

            // Mostrar cada tipo de palet como sección/categoría
            if !lineasCamion.isEmpty {
                ForEach(tiposPalet.filter { agrupadoPorTipo[$0] != nil }, id: \.self) { tipo in
                    if let lineasTipo = agrupadoPorTipo[tipo] {
                        Section(header: Text(tipo)) {
                            ForEach(lineasTipo) { linea in
                                HStack {
                                    // Cantidad de palets por pila a la izquierda
                                    Text("\(linea.paletsPorPila) por pila")
                                    Spacer()
                                    // Número de pilas a la derecha
                                    Text("\(linea.pilas) pila\(linea.pilas != 1 ? "s" : "")")
                                }
                            }
                            // No hay swipe para borrar: .onDelete eliminado
                        }
                    }
                }
            }

            // Botón para borrar todo el camión con doble confirmación
            if !lineasCamion.isEmpty {
                Section {
                    Button("Borrar camión") {
                        mostrarPrimerConfirmacion = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
        }
        .navigationTitle("Cargar Camión")
        .onAppear {
            cargarCamion()
        }
        // Primer alert de confirmación
        .alert("¿Seguro que quieres borrar el camión?", isPresented: $mostrarPrimerConfirmacion) {
            Button("Cancelar", role: .cancel) {
                mostrarPrimerConfirmacion = false
            }
            Button("Borrar", role: .destructive) {
                mostrarPrimerConfirmacion = false
                mostrarSegundaConfirmacion = true
            }
        } message: {
            Text("Esta acción eliminará todos los palets del camión. ¿Continuar?")
        }
        // Segundo alert de confirmación definitiva
        .alert("¿Borrar definitivamente el camión?", isPresented: $mostrarSegundaConfirmacion) {
            Button("Cancelar", role: .cancel) {
                mostrarSegundaConfirmacion = false
            }
            Button("Borrar definitivamente", role: .destructive) {
                debugLog("Borrando todas las líneas del camión (doble confirmación)")
                lineasCamion.removeAll()
                guardarCamion()
                mostrarSegundaConfirmacion = false
            }
        } message: {
            Text("Esta acción no se puede deshacer. ¿Deseas borrar definitivamente el camión?")
        }
        .onChange(of: lineasCamion) { _, _ in
            guardarCamion()
        }
    }

    // MARK: - Persistencia
    func camionURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("lineasCamion.json")
    }

    func guardarCamion() {
        do {
            let data = try JSONEncoder().encode(lineasCamion)
            try data.write(to: camionURL(), options: Data.WritingOptions.atomic)
            debugLog("Camión guardado en \(camionURL().lastPathComponent)")
        } catch {
            debugLog("Error guardando camión: \(error)")
        }
    }

    func cargarCamion() {
        let url = camionURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            lineasCamion = try JSONDecoder().decode([PaletCamion].self, from: data)
            debugLog("Camión cargado — líneas=\(lineasCamion.count)")
        } catch {
            debugLog("Error cargando camión: \(error)")
        }
    }
}
