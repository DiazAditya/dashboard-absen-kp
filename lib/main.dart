import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:csv/csv.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as latlong;
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';

// --- KONFIGURASI SUPABASE ---
const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const String supabaseKey = String.fromEnvironment('SUPABASE_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID', null);

  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseKey);

  runApp(const AdminApp());
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Admin Absensi',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        textTheme: GoogleFonts.poppinsTextTheme(),
        primarySwatch: Colors.indigo,
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.grey[50],
      ),
      home: const AuthGate(),
    );
  }
}

// --- GERBANG OTENTIKASI ---
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _isLoading = true;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
      try {
        final profile = await Supabase.instance.client
            .from('profiles')
            .select()
            .eq('id', session.user.id)
            .single();

        if (profile['role'] == 'admin') {
          setState(() {
            _isAdmin = true;
            _isLoading = false;
          });
        } else {
          await Supabase.instance.client.auth.signOut();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Akses Ditolak! Anda bukan Admin.")),
            );
            setState(() {
              _isAdmin = false;
              _isLoading = false;
            });
          }
        }
      } catch (e) {
        setState(() => _isLoading = false);
      }
    } else {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return _isAdmin ? const DashboardLayout() : const AdminLoginPage();
  }
}

// --- HALAMAN LOGIN ADMIN ---
class AdminLoginPage extends StatefulWidget {
  const AdminLoginPage({super.key});
  @override
  State<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends State<AdminLoginPage> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _isLoading = false;

  Future<void> _login() async {
    setState(() => _isLoading = true);
    try {
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text.trim(),
      );

      if (response.user != null) {
        final profile = await Supabase.instance.client
            .from('profiles')
            .select()
            .eq('id', response.user!.id)
            .single();
        if (profile['role'] == 'admin') {
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const DashboardLayout()),
            );
          }
        } else {
          await Supabase.instance.client.auth.signOut();
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text("Bukan akun Admin.")));
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Login Gagal")));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Center(
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(30),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.admin_panel_settings,
                size: 60,
                color: Colors.indigo,
              ),
              const SizedBox(height: 20),
              Text(
                "Admin Portal",
                style: GoogleFonts.poppins(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 30),
              TextField(
                controller: _emailCtrl,
                decoration: const InputDecoration(
                  labelText: "Email Admin",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: _passCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: "Password",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text("MASUK"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- LAYOUT UTAMA DASHBOARD ---
class DashboardLayout extends StatefulWidget {
  const DashboardLayout({super.key});
  @override
  State<DashboardLayout> createState() => _DashboardLayoutState();
}

class _DashboardLayoutState extends State<DashboardLayout> {
  int _selectedIndex = 0;

  final List<Widget> _pages = [
    const OverviewPage(),
    const MonitoringPage(),
    const HistoryPage(),
    const EmployeePage(),
    const OfficeSettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (int index) =>
                setState(() => _selectedIndex = index),
            labelType: NavigationRailLabelType.all,
            backgroundColor: Colors.indigo[900],
            indicatorColor: Colors.white24,
            unselectedIconTheme: const IconThemeData(color: Colors.white70),
            unselectedLabelTextStyle: const TextStyle(color: Colors.white70),
            selectedIconTheme: const IconThemeData(color: Colors.white),
            selectedLabelTextStyle: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
            leading: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  const Icon(Icons.shield, color: Colors.white, size: 32),
                  const SizedBox(height: 4),
                  Text(
                    'ADMIN',
                    style: GoogleFonts.poppins(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
            trailing: Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Divider(
                    color: Colors.white24,
                    indent: 10,
                    endIndent: 10,
                  ),
                  IconButton(
                    icon: const Icon(Icons.logout, color: Colors.redAccent),
                    tooltip: 'Logout',
                    onPressed: () async {
                      await Supabase.instance.client.auth.signOut();
                      if (mounted) {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => const AdminLoginPage(),
                          ),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: Text('Overview'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.monitor_heart_outlined),
                selectedIcon: Icon(Icons.monitor_heart),
                label: Text('Monitoring'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.history_outlined),
                selectedIcon: Icon(Icons.history),
                label: Text('Riwayat'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.people_outline),
                selectedIcon: Icon(Icons.people),
                label: Text('Karyawan'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: Text('Kantor'),
              ),
            ],
          ),
          Expanded(
            child: Container(
              color: Colors.grey[50],
              padding: const EdgeInsets.all(20),
              child: _pages[_selectedIndex],
            ),
          ),
        ],
      ),
    );
  }
}

// --- 1. HALAMAN MONITORING (REALTIME + MAPS VIEW) ---
class MonitoringPage extends StatefulWidget {
  const MonitoringPage({super.key});
  @override
  State<MonitoringPage> createState() => _MonitoringPageState();
}

class _MonitoringPageState extends State<MonitoringPage> {
  final Map<String, dynamic> _profilesMap = {};

  final _attendanceStream = Supabase.instance.client
      .from('attendances')
      .stream(primaryKey: ['id'])
      .order('check_in_time', ascending: false)
      .limit(50);

  @override
  void initState() {
    super.initState();
    _fetchProfiles();
  }

  Future<void> _fetchProfiles() async {
    try {
      final List<dynamic> data = await Supabase.instance.client
          .from('profiles')
          .select();
      setState(() {
        for (var item in data) {
          _profilesMap[item['id']] = item;
        }
      });
    } catch (e) {
      debugPrint("Error profiles: $e");
    }
  }

  // Fungsi untuk Membuka Popup Peta Lokasi User
  void _showLocationDialog(double lat, double long, String userName) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: SizedBox(
          width: 600,
          height: 400,
          child: Column(
            children: [
              AppBar(
                title: Text("Lokasi: $userName"),
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                leading: const CloseButton(),
              ),
              Expanded(
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: latlong.LatLng(lat, long),
                    initialZoom: 16.0,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.app',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: latlong.LatLng(lat, long),
                          width: 80,
                          height: 80,
                          child: const Icon(
                            Icons.person_pin_circle,
                            color: Colors.red,
                            size: 40,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Monitoring Absensi Live",
          style: GoogleFonts.poppins(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.indigo[900],
          ),
        ),
        Text(
          "Pantau kehadiran karyawan secara realtime (50 Data Terakhir)",
          style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[600]),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: StreamBuilder(
                stream: _attendanceStream,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final data = snapshot.data!;
                  if (data.isEmpty) {
                    return const Center(
                      child: Text("Belum ada data absensi hari ini."),
                    );
                  }

                  return SizedBox(
                    width: double.infinity,
                    child: SingleChildScrollView(
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(
                          Colors.indigo[50],
                        ),
                        columnSpacing: 20,
                        columns: const [
                          DataColumn(label: Text("Waktu")),
                          DataColumn(label: Text("Nama")),
                          DataColumn(label: Text("Koordinat")),
                          DataColumn(label: Text("Status")),
                          DataColumn(
                            label: Text("Aksi"),
                          ), // Kolom Baru: Tombol Peta
                        ],
                        rows: data.map((item) {
                          final profile = _profilesMap[item['user_id']] ?? {};
                          final date = DateTime.parse(
                            item['check_in_time'],
                          ).toLocal();
                          final formattedDate = DateFormat(
                            'dd MMM HH:mm:ss',
                            'id_ID',
                          ).format(date);

                          double? lat, long;
                          String lokasiText = "-";

                          if (item['location'] != null) {
                            try {
                              final coords = item['location']['coordinates'];
                              long = coords[0];
                              lat = coords[1];
                              lokasiText =
                                  "${lat!.toStringAsFixed(5)}, ${long!.toStringAsFixed(5)}";
                            } catch (_) {}
                          }

                          return DataRow(
                            cells: [
                              DataCell(Text(formattedDate)),
                              DataCell(
                                Text(
                                  profile['full_name'] ??
                                      'User ID: ${item['user_id'].toString().substring(0, 4)}...',
                                ),
                              ),
                              DataCell(
                                Text(
                                  lokasiText,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              DataCell(
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.green[100],
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    "Hadir",
                                    style: TextStyle(
                                      color: Colors.green[800],
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              DataCell(
                                lat != null && long != null
                                    ? IconButton(
                                        icon: const Icon(
                                          Icons.map,
                                          color: Colors.indigo,
                                        ),
                                        tooltip: "Lihat di Peta",
                                        onPressed: () => _showLocationDialog(
                                          lat!,
                                          long!,
                                          profile['full_name'] ?? 'User',
                                        ),
                                      )
                                    : const Icon(Icons.map, color: Colors.grey),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// --- 2. HALAMAN RIWAYAT & EXPORT ---
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  DateTimeRange? _selectedDateRange;
  List<dynamic> _data = [];
  bool _isLoading = false;
  final Map<String, dynamic> _profilesMap = {};

  @override
  void initState() {
    super.initState();
    _fetchProfiles();
  }

  Future<void> _fetchProfiles() async {
    final List<dynamic> data = await Supabase.instance.client
        .from('profiles')
        .select();
    setState(() {
      for (var item in data) {
        _profilesMap[item['id']] = item;
      }
    });
  }

  Future<void> _fetchData() async {
    if (_selectedDateRange == null) return;
    setState(() => _isLoading = true);

    try {
      final start = _selectedDateRange!.start.toIso8601String();
      final end = _selectedDateRange!.end
          .add(const Duration(hours: 23, minutes: 59))
          .toIso8601String();

      final response = await Supabase.instance.client
          .from('attendances')
          .select()
          .gte('check_in_time', start)
          .lte('check_in_time', end)
          .order('check_in_time', ascending: false);

      setState(() => _data = response);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _exportCsv() async {
    if (_data.isEmpty) return;

    List<List<dynamic>> rows = [];
    rows.add([
      "Waktu Absen",
      "Nama Karyawan",
      "Email",
      "Latitude",
      "Longitude",
      "Status",
    ]);

    for (var item in _data) {
      final profile = _profilesMap[item['user_id']] ?? {};
      final date = DateTime.parse(item['check_in_time']).toLocal();

      String lat = "", long = "";
      if (item['location'] != null) {
        try {
          final coords = item['location']['coordinates'];
          long = coords[0].toString();
          lat = coords[1].toString();
        } catch (_) {}
      }

      rows.add([
        DateFormat('yyyy-MM-dd HH:mm:ss').format(date),
        profile['full_name'] ?? 'Unknown',
        profile['email'] ?? '-',
        lat,
        long,
        "Hadir",
      ]);
    }

    String csv = const CsvEncoder().convert(rows);
    try {
      await FileSaver.instance.saveFile(
        name:
            'Laporan_Absensi_${DateFormat('yyyyMMdd').format(DateTime.now())}',
        bytes: Uint8List.fromList(utf8.encode(csv)),
        fileExtension: 'csv',
        mimeType: MimeType.csv,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("File berhasil didownload!")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Gagal download file")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Laporan Riwayat",
          style: GoogleFonts.poppins(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.indigo[900],
          ),
        ),
        const SizedBox(height: 20),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today),
                    label: Text(
                      _selectedDateRange == null
                          ? "Pilih Rentang Tanggal"
                          : "${DateFormat('dd MMM').format(_selectedDateRange!.start)} - ${DateFormat('dd MMM yyyy').format(_selectedDateRange!.end)}",
                    ),
                    onPressed: () async {
                      final picked = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(2023),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setState(() => _selectedDateRange = picked);
                        _fetchData();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 20),
                ElevatedButton.icon(
                  icon: const Icon(Icons.download),
                  label: const Text("Export CSV (Excel)"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _data.isEmpty ? null : _exportCsv,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),

        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _data.isEmpty
              ? Center(
                  child: Text(
                    _selectedDateRange == null
                        ? "Silakan pilih tanggal dulu."
                        : "Tidak ada data pada tanggal tersebut.",
                    style: const TextStyle(color: Colors.grey),
                  ),
                )
              : Card(
                  child: SizedBox(
                    width: double.infinity,
                    child: SingleChildScrollView(
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(
                          Colors.grey[100],
                        ),
                        columns: const [
                          DataColumn(label: Text("Waktu")),
                          DataColumn(label: Text("Nama")),
                          DataColumn(label: Text("Koordinat")),
                        ],
                        rows: _data.map((item) {
                          final profile = _profilesMap[item['user_id']] ?? {};
                          final date = DateTime.parse(
                            item['check_in_time'],
                          ).toLocal();
                          String lokasi = "-";
                          if (item['location'] != null) {
                            try {
                              final coords = item['location']['coordinates'];
                              lokasi =
                                  "${coords[1].toStringAsFixed(5)}, ${coords[0].toStringAsFixed(5)}";
                            } catch (_) {}
                          }
                          return DataRow(
                            cells: [
                              DataCell(
                                Text(
                                  DateFormat('dd MMM yyyy HH:mm').format(date),
                                ),
                              ),
                              DataCell(
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      profile['full_name'] ?? '-',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      profile['email'] ?? '-',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              DataCell(
                                Text(
                                  lokasi,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

// --- 3. HALAMAN PENGATURAN KANTOR (DENGAN SEARCH ALAMAT) ---
class OfficeSettingsPage extends StatefulWidget {
  const OfficeSettingsPage({super.key});
  @override
  State<OfficeSettingsPage> createState() => _OfficeSettingsPageState();
}

class _OfficeSettingsPageState extends State<OfficeSettingsPage> {
  final _latCtrl = TextEditingController();
  final _longCtrl = TextEditingController();
  final _radiusCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  final MapController _mapController = MapController();
  bool _isLoading = true;
  TimeOfDay _selectedStartTime = const TimeOfDay(hour: 9, minute: 0);

  // Posisi Marker di Peta
  latlong.LatLng _markerPosition = const latlong.LatLng(
    -6.175392,
    106.827153,
  ); // Default Monas

  @override
  void initState() {
    super.initState();
    _fetchOfficeData();
  }

  Future<void> _fetchOfficeData() async {
    try {
      final data = await Supabase.instance.client
          .from('offices')
          .select()
          .eq('id', 1)
          .single();
      _nameCtrl.text = data['name'] ?? '';
      _radiusCtrl.text = (data['radius_meters'] ?? 50).toString();

      // Load waktu masuk
      if (data['start_time'] != null) {
        final parts = data['start_time'].toString().split(':');
        if (parts.length >= 2) {
          _selectedStartTime = TimeOfDay(
            hour: int.tryParse(parts[0]) ?? 9,
            minute: int.tryParse(parts[1]) ?? 0,
          );
        }
      }

      if (data['location'] != null) {
        final coords = data['location']['coordinates'];
        _longCtrl.text = coords[0].toString();
        _latCtrl.text = coords[1].toString();

        setState(() {
          _markerPosition = latlong.LatLng(coords[1], coords[0]);
        });
      }
    } catch (e) {
      debugPrint("Error office: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // LOGIKA PENCARIAN ALAMAT (NOMINATIM API)
  Future<void> _searchAddress() async {
    final query = _searchCtrl.text.trim();
    if (query.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      // Gunakan Uri.https agar query ter-encode otomatis (spasi, dll)
      final url = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': query,
        'format': 'json',
        'limit': '1',
      });

      debugPrint('Searching: $url');

      // Penting: Nominatim mewajibkan User-Agent yang valid
      final response = await http.get(
        url,
        headers: {
          'User-Agent': 'AdminDashboard/1.0 (contact@example.com)',
          'Accept': 'application/json',
        },
      );

      debugPrint('Status: ${response.statusCode}');
      debugPrint('Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is List && data.isNotEmpty) {
          final lat = double.parse(data[0]['lat']);
          final lon = double.parse(data[0]['lon']);
          final newPos = latlong.LatLng(lat, lon);

          setState(() {
            _markerPosition = newPos;
            _latCtrl.text = lat.toString();
            _longCtrl.text = lon.toString();
          });
          // Pindahkan kamera peta ke lokasi hasil pencarian
          _mapController.move(newPos, 16.0);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Ditemukan: ${data[0]['display_name']}')),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Alamat tidak ditemukan')),
            );
          }
        }
      } else {
        debugPrint('Nominatim error: ${response.statusCode}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Server error: ${response.statusCode}')),
          );
        }
      }
    } catch (e) {
      debugPrint('Search error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gagal mencari alamat: $e')));
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isLoading = true);
    try {
      final lat = double.parse(_latCtrl.text);
      final long = double.parse(_longCtrl.text);
      final radius = int.parse(_radiusCtrl.text);
      final startTime =
          '${_selectedStartTime.hour.toString().padLeft(2, '0')}:${_selectedStartTime.minute.toString().padLeft(2, '0')}:00';

      await Supabase.instance.client
          .from('offices')
          .update({
            'name': _nameCtrl.text,
            'radius_meters': radius,
            'start_time': startTime,
          })
          .eq('id', 1);

      await Supabase.instance.client.rpc(
        'update_office_location',
        params: {'office_id': 1, 'new_lat': lat, 'new_long': long},
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Pengaturan Kantor Berhasil Disimpan!")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Gagal simpan: $e")));
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // KOLOM KIRI: FORM INPUT
        Expanded(
          flex: 2,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Pengaturan Kantor",
                  style: GoogleFonts.poppins(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo[900],
                  ),
                ),
                const SizedBox(height: 20),
                _isLoading
                    ? const CircularProgressIndicator()
                    : Card(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Lokasi Pusat & Radius",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 20),
                              TextField(
                                controller: _nameCtrl,
                                decoration: const InputDecoration(
                                  labelText: "Nama Kantor",
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.business),
                                ),
                              ),
                              const SizedBox(height: 15),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _latCtrl,
                                      readOnly: true,
                                      decoration: const InputDecoration(
                                        labelText: "Latitude",
                                        border: OutlineInputBorder(),
                                        filled: true,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: TextField(
                                      controller: _longCtrl,
                                      readOnly: true,
                                      decoration: const InputDecoration(
                                        labelText: "Longitude",
                                        border: OutlineInputBorder(),
                                        filled: true,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                "Gunakan fitur Search di peta atau klik manual untuk update lokasi.",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.blue,
                                ),
                              ),
                              const SizedBox(height: 15),
                              TextField(
                                controller: _radiusCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: "Radius Toleransi (Meter)",
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.radar),
                                  suffixText: "Meter",
                                ),
                              ),
                              const SizedBox(height: 15),
                              // Waktu Masuk (Time Picker)
                              InkWell(
                                onTap: () async {
                                  final picked = await showTimePicker(
                                    context: context,
                                    initialTime: _selectedStartTime,
                                    helpText: 'Pilih Waktu Masuk Kantor',
                                  );
                                  if (picked != null) {
                                    setState(() => _selectedStartTime = picked);
                                  }
                                },
                                child: InputDecorator(
                                  decoration: const InputDecoration(
                                    labelText: 'Waktu Masuk Kantor',
                                    border: OutlineInputBorder(),
                                    prefixIcon: Icon(Icons.schedule),
                                  ),
                                  child: Text(
                                    '${_selectedStartTime.hour.toString().padLeft(2, '0')}:${_selectedStartTime.minute.toString().padLeft(2, '0')}',
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Karyawan yang check-in setelah waktu ini dihitung terlambat.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 30),
                              SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: ElevatedButton.icon(
                                  icon: const Icon(Icons.save),
                                  label: const Text("SIMPAN PERUBAHAN"),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.indigo,
                                    foregroundColor: Colors.white,
                                  ),
                                  onPressed: _saveSettings,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
              ],
            ),
          ),
        ),

        const SizedBox(width: 20),

        // KOLOM KANAN: PETA INTERAKTIF + SEARCH BAR
        Expanded(
          flex: 3,
          child: Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController, // Wajib pasang controller ini
                  options: MapOptions(
                    initialCenter: _markerPosition,
                    initialZoom: 15.0,
                    onTap: (tapPosition, point) {
                      setState(() {
                        _markerPosition = point;
                        _latCtrl.text = point.latitude.toString();
                        _longCtrl.text = point.longitude.toString();
                      });
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.admin_dashboard',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _markerPosition,
                          width: 80,
                          height: 80,
                          child: const Icon(
                            Icons.location_on,
                            color: Colors.red,
                            size: 50,
                          ),
                        ),
                      ],
                    ),
                    CircleLayer(
                      circles: [
                        CircleMarker(
                          point: _markerPosition,
                          color: Colors.blue.withValues(alpha: 0.3),
                          borderStrokeWidth: 2,
                          borderColor: Colors.blue,
                          useRadiusInMeter: true,
                          radius:
                              double.tryParse(_radiusCtrl.text) ??
                              50, // Visualisasi Radius
                        ),
                      ],
                    ),
                  ],
                ),

                // WIDGET SEARCH BAR (Mengambang di atas peta)
                Positioned(
                  top: 10,
                  left: 10,
                  right: 10,
                  child: Card(
                    elevation: 4,
                    child: ListTile(
                      leading: const Icon(Icons.search, color: Colors.grey),
                      title: TextField(
                        controller: _searchCtrl,
                        decoration: const InputDecoration(
                          hintText: "Cari alamat (Contoh: Monas Jakarta)",
                          border: InputBorder.none,
                        ),
                        onSubmitted: (_) => _searchAddress(),
                      ),
                      trailing: IconButton(
                        icon: const Icon(
                          Icons.arrow_forward,
                          color: Colors.indigo,
                        ),
                        onPressed: _searchAddress,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// --- 4. HALAMAN OVERVIEW (STATISTIK KEHADIRAN) ---
class OverviewPage extends StatefulWidget {
  const OverviewPage({super.key});
  @override
  State<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends State<OverviewPage> {
  bool _isLoading = true;
  int _totalEmployees = 0;
  int _todayPresent = 0;
  int _todayLate = 0;
  int _todayAbsent = 0;
  List<Map<String, dynamic>> _weeklyData = [];

  @override
  void initState() {
    super.initState();
    _fetchStats();
  }

  Future<void> _fetchStats() async {
    setState(() => _isLoading = true);
    try {
      final supabase = Supabase.instance.client;

      // Total karyawan (non-admin)
      final profiles = await supabase.from('profiles').select('id, role');
      final employees = profiles.where((p) => p['role'] != 'admin').toList();
      _totalEmployees = employees.length;

      // Absensi hari ini
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final todayAttendances = await supabase
          .from('attendances')
          .select()
          .gte('check_in_time', '${today}T00:00:00')
          .lte('check_in_time', '${today}T23:59:59');

      _todayPresent = todayAttendances.length;

      // Hitung yang telat (check_in setelah jam 09:00)
      _todayLate = 0;
      for (final att in todayAttendances) {
        final checkIn = DateTime.parse(att['check_in_time']).toLocal();
        if (checkIn.hour >= 9) {
          _todayLate++;
        }
      }

      _todayAbsent = _totalEmployees - _todayPresent;
      if (_todayAbsent < 0) _todayAbsent = 0;

      debugPrint(
        'Stats: employees=$_totalEmployees, present=$_todayPresent, late=$_todayLate, absent=$_todayAbsent',
      );

      // Data 7 hari terakhir untuk grafik
      _weeklyData = [];
      for (int i = 6; i >= 0; i--) {
        final date = DateTime.now().subtract(Duration(days: i));
        final dateStr = DateFormat('yyyy-MM-dd').format(date);
        final dayAttendances = await supabase
            .from('attendances')
            .select()
            .gte('check_in_time', '${dateStr}T00:00:00')
            .lte('check_in_time', '${dateStr}T23:59:59');

        _weeklyData.add({
          'date': date,
          'count': dayAttendances.length,
          'label': DateFormat('E', 'id').format(date),
        });
      }

      setState(() {});
    } catch (e) {
      debugPrint('Error stats: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: [color.withValues(alpha: 0.1), Colors.white],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color, size: 28),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                value,
                style: GoogleFonts.poppins(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _fetchStats,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Dashboard Overview',
                  style: GoogleFonts.poppins(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo[900],
                  ),
                ),
                Text(
                  DateFormat('EEEE, dd MMMM yyyy', 'id').format(DateTime.now()),
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Stat Cards
            Row(
              children: [
                _buildStatCard(
                  'Total Karyawan',
                  '$_totalEmployees',
                  Icons.people,
                  Colors.indigo,
                ),
                const SizedBox(width: 16),
                _buildStatCard(
                  'Hadir Hari Ini',
                  '$_todayPresent',
                  Icons.check_circle,
                  Colors.green,
                ),
                const SizedBox(width: 16),
                _buildStatCard(
                  'Terlambat',
                  '$_todayLate',
                  Icons.schedule,
                  Colors.orange,
                ),
                const SizedBox(width: 16),
                _buildStatCard(
                  'Belum Hadir',
                  '$_todayAbsent',
                  Icons.cancel,
                  Colors.red,
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Charts Row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Bar Chart - Kehadiran 7 hari
                Expanded(
                  flex: 3,
                  child: Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Kehadiran 7 Hari Terakhir',
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[800],
                            ),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            height: 250,
                            child: BarChart(
                              BarChartData(
                                alignment: BarChartAlignment.spaceAround,
                                maxY:
                                    (_totalEmployees > 0
                                        ? _totalEmployees.toDouble()
                                        : 10) *
                                    1.2,
                                barTouchData: BarTouchData(
                                  enabled: true,
                                  touchTooltipData: BarTouchTooltipData(
                                    getTooltipItem:
                                        (group, groupIndex, rod, rodIndex) {
                                          return BarTooltipItem(
                                            '${rod.toY.toInt()} hadir',
                                            GoogleFonts.poppins(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          );
                                        },
                                  ),
                                ),
                                titlesData: FlTitlesData(
                                  show: true,
                                  bottomTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      getTitlesWidget: (value, meta) {
                                        final idx = value.toInt();
                                        if (idx < 0 ||
                                            idx >= _weeklyData.length) {
                                          return const Text('');
                                        }
                                        return Text(
                                          _weeklyData[idx]['label'],
                                          style: GoogleFonts.poppins(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  leftTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      reservedSize: 30,
                                      getTitlesWidget: (value, meta) {
                                        return Text(
                                          value.toInt().toString(),
                                          style: TextStyle(
                                            color: Colors.grey[500],
                                            fontSize: 11,
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  topTitles: const AxisTitles(
                                    sideTitles: SideTitles(showTitles: false),
                                  ),
                                  rightTitles: const AxisTitles(
                                    sideTitles: SideTitles(showTitles: false),
                                  ),
                                ),
                                gridData: FlGridData(
                                  show: true,
                                  drawVerticalLine: false,
                                  getDrawingHorizontalLine: (value) => FlLine(
                                    color: Colors.grey[200]!,
                                    strokeWidth: 1,
                                  ),
                                ),
                                borderData: FlBorderData(show: false),
                                barGroups: _weeklyData.asMap().entries.map((
                                  entry,
                                ) {
                                  return BarChartGroupData(
                                    x: entry.key,
                                    barRods: [
                                      BarChartRodData(
                                        toY: entry.value['count'].toDouble(),
                                        color: Colors.indigo,
                                        width: 22,
                                        borderRadius:
                                            const BorderRadius.vertical(
                                              top: Radius.circular(6),
                                            ),
                                        backDrawRodData:
                                            BackgroundBarChartRodData(
                                              show: true,
                                              toY: _totalEmployees > 0
                                                  ? _totalEmployees.toDouble()
                                                  : 10,
                                              color: Colors.indigo.withValues(
                                                alpha: 0.08,
                                              ),
                                            ),
                                      ),
                                    ],
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // Pie Chart - Distribusi hari ini
                Expanded(
                  flex: 2,
                  child: Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Distribusi Hari Ini',
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[800],
                            ),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            height: 200,
                            child: PieChart(
                              PieChartData(
                                centerSpaceRadius: 40,
                                sectionsSpace: 3,
                                sections: [
                                  PieChartSectionData(
                                    color: Colors.green,
                                    value: (_todayPresent - _todayLate)
                                        .toDouble()
                                        .clamp(0, double.infinity),
                                    title: '${_todayPresent - _todayLate}',
                                    titleStyle: GoogleFonts.poppins(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                    radius: 50,
                                  ),
                                  PieChartSectionData(
                                    color: Colors.orange,
                                    value: _todayLate.toDouble(),
                                    title: '$_todayLate',
                                    titleStyle: GoogleFonts.poppins(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                    radius: 50,
                                  ),
                                  PieChartSectionData(
                                    color: Colors.red[300]!,
                                    value: _todayAbsent.toDouble(),
                                    title: '$_todayAbsent',
                                    titleStyle: GoogleFonts.poppins(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                    radius: 50,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Legend
                          _buildLegendItem('Tepat Waktu', Colors.green),
                          const SizedBox(height: 8),
                          _buildLegendItem('Terlambat', Colors.orange),
                          const SizedBox(height: 8),
                          _buildLegendItem('Belum Hadir', Colors.red[300]!),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[700]),
        ),
      ],
    );
  }
}

// --- 5. HALAMAN MANAJEMEN KARYAWAN ---
class EmployeePage extends StatefulWidget {
  const EmployeePage({super.key});
  @override
  State<EmployeePage> createState() => _EmployeePageState();
}

class _EmployeePageState extends State<EmployeePage> {
  List<dynamic> _employees = [];
  List<dynamic> _filtered = [];
  bool _isLoading = true;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchEmployees();
  }

  Future<void> _fetchEmployees() async {
    setState(() => _isLoading = true);
    try {
      final data = await Supabase.instance.client
          .from('profiles')
          .select()
          .order('full_name', ascending: true);
      setState(() {
        _employees = data;
        _filtered = data;
      });
    } catch (e) {
      debugPrint('Error employees: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _filterEmployees(String query) {
    setState(() {
      if (query.isEmpty) {
        _filtered = _employees;
      } else {
        _filtered = _employees.where((e) {
          final name = (e['full_name'] ?? '').toString().toLowerCase();
          final email = (e['email'] ?? '').toString().toLowerCase();
          return name.contains(query.toLowerCase()) ||
              email.contains(query.toLowerCase());
        }).toList();
      }
    });
  }

  Future<void> _deleteEmployee(Map<String, dynamic> employee) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red[400], size: 28),
            const SizedBox(width: 8),
            const Text('Konfirmasi Hapus'),
          ],
        ),
        content: RichText(
          text: TextSpan(
            style: const TextStyle(color: Colors.black87, fontSize: 15),
            children: [
              const TextSpan(text: 'Apakah Anda yakin ingin menghapus '),
              TextSpan(
                text: employee['full_name'] ?? employee['email'] ?? 'user ini',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const TextSpan(
                text: '?\n\nData profil akan dihapus secara permanen.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await Supabase.instance.client
          .from('profiles')
          .delete()
          .eq('id', employee['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${employee['full_name'] ?? 'User'} berhasil dihapus',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }

      _fetchEmployees();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menghapus: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Manajemen Karyawan',
              style: GoogleFonts.poppins(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.indigo[900],
              ),
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.indigo[50],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_employees.length} total karyawan',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: Colors.indigo[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh',
                  onPressed: _fetchEmployees,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Search Bar
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                hintText: 'Cari berdasarkan nama atau email...',
                icon: Icon(Icons.search),
                border: InputBorder.none,
              ),
              onChanged: _filterEmployees,
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Table
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.people_outline,
                        size: 64,
                        color: Colors.grey[300],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Tidak ada karyawan ditemukan',
                        style: GoogleFonts.poppins(
                          color: Colors.grey[500],
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                )
              : Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: SingleChildScrollView(
                    child: SizedBox(
                      width: double.infinity,
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(
                          Colors.indigo[50],
                        ),
                        headingTextStyle: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          color: Colors.indigo[900],
                          fontSize: 13,
                        ),
                        columnSpacing: 24,
                        columns: const [
                          DataColumn(label: Text('No')),
                          DataColumn(label: Text('Nama Lengkap')),
                          DataColumn(label: Text('Email')),
                          DataColumn(label: Text('Role')),
                          DataColumn(label: Text('Aksi')),
                        ],
                        rows: _filtered.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final emp = entry.value;
                          final isAdmin = emp['role'] == 'admin';
                          return DataRow(
                            color: WidgetStateProperty.resolveWith<Color?>(
                              (states) => idx.isOdd ? Colors.grey[50] : null,
                            ),
                            cells: [
                              DataCell(Text('${idx + 1}')),
                              DataCell(
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 16,
                                      backgroundColor: isAdmin
                                          ? Colors.indigo[100]
                                          : Colors.blue[100],
                                      child: Text(
                                        (emp['full_name'] ?? '?')
                                            .toString()
                                            .substring(0, 1)
                                            .toUpperCase(),
                                        style: TextStyle(
                                          color: isAdmin
                                              ? Colors.indigo[800]
                                              : Colors.blue[800],
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      emp['full_name'] ?? '-',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              DataCell(Text(emp['email'] ?? '-')),
                              DataCell(
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isAdmin
                                        ? Colors.indigo[50]
                                        : Colors.green[50],
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    emp['role'] ?? 'user',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: isAdmin
                                          ? Colors.indigo[700]
                                          : Colors.green[700],
                                    ),
                                  ),
                                ),
                              ),
                              DataCell(
                                isAdmin
                                    ? const Tooltip(
                                        message: 'Admin tidak bisa dihapus',
                                        child: Icon(
                                          Icons.lock,
                                          color: Colors.grey,
                                          size: 20,
                                        ),
                                      )
                                    : IconButton(
                                        icon: const Icon(
                                          Icons.delete,
                                          color: Colors.red,
                                          size: 20,
                                        ),
                                        tooltip: 'Hapus karyawan',
                                        onPressed: () => _deleteEmployee(emp),
                                      ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
