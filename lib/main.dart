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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID', null);

  // Ambil credentials dari --dart-define (lokal & Vercel)
  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseKey = String.fromEnvironment('SUPABASE_KEY');

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
    const HolidayManagementPage(),
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
                      final navigator = Navigator.of(context);
                      await Supabase.instance.client.auth.signOut();
                      if (mounted) {
                        navigator.pushReplacement(
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
              NavigationRailDestination(
                icon: Icon(
                  Icons.calendar_month_outlined,
                  color: Colors.redAccent,
                ),
                selectedIcon: Icon(
                  Icons.calendar_month,
                  color: Colors.redAccent,
                ),
                label: Text('Libur'),
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

// --- 1. HALAMAN MONITORING ABSENSI HARIAN ---
class MonitoringPage extends StatefulWidget {
  const MonitoringPage({super.key});
  @override
  State<MonitoringPage> createState() => _MonitoringPageState();
}

class _MonitoringPageState extends State<MonitoringPage> {
  DateTime _selectedDate = DateTime.now();
  List<Map<String, dynamic>> _employeeStatuses = [];
  bool _isLoading = true;
  TimeOfDay _officeStartTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _officeEndTime = const TimeOfDay(hour: 17, minute: 0);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // 1. Ambil jam masuk & pulang kantor
      final officeData = await Supabase.instance.client
          .from('offices')
          .select('start_time, end_time')
          .eq('id', 1)
          .maybeSingle();

      if (officeData != null && officeData['start_time'] != null) {
        final parts = officeData['start_time'].toString().split(':');
        if (parts.length >= 2) {
          _officeStartTime = TimeOfDay(
            hour: int.tryParse(parts[0]) ?? 9,
            minute: int.tryParse(parts[1]) ?? 0,
          );
        }
      }
      if (officeData != null && officeData['end_time'] != null) {
        final parts = officeData['end_time'].toString().split(':');
        if (parts.length >= 2) {
          _officeEndTime = TimeOfDay(
            hour: int.tryParse(parts[0]) ?? 17,
            minute: int.tryParse(parts[1]) ?? 0,
          );
        }
      }

      // 2. Ambil semua karyawan (non-admin)
      final List<dynamic> profiles = await Supabase.instance.client
          .from('profiles')
          .select()
          .neq('role', 'admin')
          .order('full_name', ascending: true);

      // 3. Ambil absensi pada tanggal terpilih
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final startOfDay = '${dateStr}T00:00:00';
      final endOfDay = '${dateStr}T23:59:59';

      final List<dynamic> attendances = await Supabase.instance.client
          .from('attendances')
          .select()
          .gte('check_in_time', startOfDay)
          .lte('check_in_time', endOfDay);

      // 4. Ambil data cuti pada tanggal terpilih
      final List<dynamic> leaves = await Supabase.instance.client
          .from('employee_leaves')
          .select()
          .eq('leave_date', dateStr);

      // 5. Gabungkan data: mapping per karyawan
      final Map<String, dynamic> attendanceMap = {};
      for (var att in attendances) {
        attendanceMap[att['user_id']] = att;
      }

      final Map<String, Map<String, dynamic>> leaveMap = {};
      for (var leave in leaves) {
        leaveMap[leave['user_id']] = leave;
      }

      // Helper: parse TIME string "HH:mm:ss" to minutes
      int timeToMinutes(String timeStr) {
        final parts = timeStr.split(':');
        return (int.tryParse(parts[0]) ?? 0) * 60 +
            (int.tryParse(parts[1]) ?? 0);
      }

      final officeStartMin =
          _officeStartTime.hour * 60 + _officeStartTime.minute;
      final officeEndMin = _officeEndTime.hour * 60 + _officeEndTime.minute;

      final List<Map<String, dynamic>> result = [];
      for (var profile in profiles) {
        final userId = profile['id'] as String;
        final attendance = attendanceMap[userId];
        final leaveEntry = leaveMap[userId];

        String status;
        Color statusColor;
        Color statusBgColor;
        String timeText = '-';

        String checkOutStatus;
        Color checkOutColor;
        Color checkOutBgColor;
        String checkOutTimeText = '-';

        // Tentukan apakah check-in / check-out di-skip
        bool skipCheckIn = false;
        bool skipCheckOut = false;
        String skipLabel = '';

        if (leaveEntry != null) {
          final type = leaveEntry['type'] ?? 'cuti';
          if (type == 'cuti') {
            skipCheckIn = true;
            skipCheckOut = true;
            skipLabel = 'Cuti';
          } else if (type == 'dinas') {
            skipLabel = 'Dinas';
            if (leaveEntry['trip_start_time'] != null &&
                leaveEntry['trip_end_time'] != null) {
              final tripStartMin = timeToMinutes(
                leaveEntry['trip_start_time'].toString(),
              );
              final tripEndMin = timeToMinutes(
                leaveEntry['trip_end_time'].toString(),
              );
              if (tripStartMin <= officeStartMin) skipCheckIn = true;
              if (tripEndMin >= officeEndMin) skipCheckOut = true;
            }
          }
        }

        // === Status Masuk ===
        if (skipCheckIn) {
          status = skipLabel;
          statusColor = skipLabel == 'Cuti'
              ? Colors.orange[800]!
              : Colors.blue[800]!;
          statusBgColor = skipLabel == 'Cuti'
              ? Colors.orange[50]!
              : Colors.blue[50]!;
        } else if (attendance != null) {
          final checkInTime = DateTime.parse(
            attendance['check_in_time'],
          ).toLocal();
          timeText = DateFormat('HH:mm:ss').format(checkInTime);
          final actualMinutes = checkInTime.hour * 60 + checkInTime.minute;

          if (actualMinutes > officeStartMin) {
            status = 'Terlambat';
            statusColor = Colors.red[800]!;
            statusBgColor = Colors.red[50]!;
          } else {
            status = 'Hadir';
            statusColor = Colors.green[800]!;
            statusBgColor = Colors.green[50]!;
          }
        } else {
          status = 'Belum Absen';
          statusColor = Colors.grey[700]!;
          statusBgColor = Colors.grey[100]!;
        }

        // === Status Pulang ===
        if (skipCheckOut) {
          checkOutStatus = skipLabel;
          checkOutColor = skipLabel == 'Cuti'
              ? Colors.orange[800]!
              : Colors.blue[800]!;
          checkOutBgColor = skipLabel == 'Cuti'
              ? Colors.orange[50]!
              : Colors.blue[50]!;
        } else if (attendance != null && attendance['check_out_time'] != null) {
          final checkOutTime = DateTime.parse(
            attendance['check_out_time'],
          ).toLocal();
          checkOutTimeText = DateFormat('HH:mm:ss').format(checkOutTime);
          final outMinutes = checkOutTime.hour * 60 + checkOutTime.minute;

          if (outMinutes >= officeEndMin) {
            checkOutStatus = 'Pulang';
            checkOutColor = Colors.green[800]!;
            checkOutBgColor = Colors.green[50]!;
          } else {
            checkOutStatus = 'Pulang Awal';
            checkOutColor = Colors.amber[800]!;
            checkOutBgColor = Colors.amber[50]!;
          }
        } else if (attendance != null) {
          checkOutStatus = 'Belum Pulang';
          checkOutColor = Colors.grey[700]!;
          checkOutBgColor = Colors.grey[100]!;
        } else {
          checkOutStatus = '-';
          checkOutColor = Colors.grey[700]!;
          checkOutBgColor = Colors.grey[100]!;
        }

        result.add({
          'profile': profile,
          'attendance': attendance,
          'status': status,
          'statusColor': statusColor,
          'statusBgColor': statusBgColor,
          'timeText': timeText,
          'checkOutStatus': checkOutStatus,
          'checkOutColor': checkOutColor,
          'checkOutBgColor': checkOutBgColor,
          'checkOutTimeText': checkOutTimeText,
        });
      }

      setState(() {
        _employeeStatuses = result;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Error loading monitoring: $e");
      setState(() => _isLoading = false);
    }
  }

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
    final isToday =
        DateFormat('yyyy-MM-dd').format(_selectedDate) ==
        DateFormat('yyyy-MM-dd').format(DateTime.now());

    // Hitung ringkasan
    int hadir = 0, terlambat = 0, cuti = 0, belumAbsen = 0;
    for (var emp in _employeeStatuses) {
      switch (emp['status']) {
        case 'Hadir':
          hadir++;
          break;
        case 'Terlambat':
          terlambat++;
          break;
        case 'Cuti':
          cuti++;
          break;
        default:
          belumAbsen++;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Text(
          "Monitoring Absensi",
          style: GoogleFonts.poppins(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.indigo[900],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          "Lihat status kehadiran seluruh karyawan per tanggal",
          style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[600]),
        ),
        const SizedBox(height: 16),

        // Date Picker + Summary
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Tombol Pilih Tanggal
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: Text(
                    isToday
                        ? 'Hari Ini — ${DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(_selectedDate)}'
                        : DateFormat(
                            'EEEE, dd MMMM yyyy',
                            'id_ID',
                          ).format(_selectedDate),
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate,
                      firstDate: DateTime(2023),
                      lastDate: DateTime.now(),
                      helpText: 'PILIH TANGGAL',
                    );
                    if (picked != null) {
                      _selectedDate = picked;
                      _loadData();
                    }
                  },
                ),
                const SizedBox(width: 12),
                // Tombol hari ini (shortcut)
                if (!isToday)
                  TextButton.icon(
                    icon: const Icon(Icons.today, size: 18),
                    label: const Text('Hari Ini'),
                    onPressed: () {
                      _selectedDate = DateTime.now();
                      _loadData();
                    },
                  ),
                const Spacer(),
                // Summary badges
                _buildSummaryBadge('Hadir', hadir, Colors.green),
                const SizedBox(width: 8),
                _buildSummaryBadge('Terlambat', terlambat, Colors.red),
                const SizedBox(width: 8),
                _buildSummaryBadge('Cuti', cuti, Colors.orange),
                const SizedBox(width: 8),
                _buildSummaryBadge('Belum', belumAbsen, Colors.grey),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Tabel Karyawan
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _employeeStatuses.isEmpty
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
                        "Tidak ada data karyawan.",
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
                          DataColumn(label: Text('Nama')),
                          DataColumn(label: Text('Jam Masuk')),
                          DataColumn(label: Text('Status Masuk')),
                          DataColumn(label: Text('Jam Pulang')),
                          DataColumn(label: Text('Status Pulang')),
                          DataColumn(label: Text('Lokasi')),
                        ],
                        rows: _employeeStatuses.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final emp = entry.value;
                          final profile = emp['profile'];
                          final attendance = emp['attendance'];

                          double? lat, long;
                          if (attendance != null &&
                              attendance['location'] != null) {
                            try {
                              final coords =
                                  attendance['location']['coordinates'];
                              long = coords[0];
                              lat = coords[1];
                            } catch (_) {}
                          }

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
                                      backgroundColor: Colors.blue[100],
                                      child: Text(
                                        (profile['full_name'] ?? '?')
                                            .toString()
                                            .substring(0, 1)
                                            .toUpperCase(),
                                        style: TextStyle(
                                          color: Colors.blue[800],
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      profile['full_name'] ?? '-',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              DataCell(
                                Text(
                                  emp['timeText'],
                                  style: GoogleFonts.robotoMono(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              DataCell(
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: emp['statusBgColor'],
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    emp['status'],
                                    style: TextStyle(
                                      color: emp['statusColor'],
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  emp['checkOutTimeText'],
                                  style: GoogleFonts.robotoMono(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              DataCell(
                                emp['checkOutStatus'] == '-'
                                    ? const Text('-')
                                    : Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: emp['checkOutBgColor'],
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                        child: Text(
                                          emp['checkOutStatus'],
                                          style: TextStyle(
                                            color: emp['checkOutColor'],
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
                                          size: 20,
                                        ),
                                        tooltip: "Lihat di Peta",
                                        onPressed: () => _showLocationDialog(
                                          lat!,
                                          long!,
                                          profile['full_name'] ?? 'User',
                                        ),
                                      )
                                    : const Icon(
                                        Icons.location_off,
                                        color: Colors.grey,
                                        size: 20,
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

  Widget _buildSummaryBadge(String label, int count, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color[50],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color[200]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.bold,
              color: color[800],
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.poppins(color: color[700], fontSize: 12),
          ),
        ],
      ),
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
  TimeOfDay _selectedEndTime = const TimeOfDay(hour: 17, minute: 0);

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

      // Load waktu pulang
      if (data['end_time'] != null) {
        final parts = data['end_time'].toString().split(':');
        if (parts.length >= 2) {
          _selectedEndTime = TimeOfDay(
            hour: int.tryParse(parts[0]) ?? 17,
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
      final endTime =
          '${_selectedEndTime.hour.toString().padLeft(2, '0')}:${_selectedEndTime.minute.toString().padLeft(2, '0')}:00';

      await Supabase.instance.client
          .from('offices')
          .update({
            'name': _nameCtrl.text,
            'radius_meters': radius,
            'start_time': startTime,
            'end_time': endTime,
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
                              const SizedBox(height: 15),
                              // Waktu Pulang (Time Picker)
                              InkWell(
                                onTap: () async {
                                  final picked = await showTimePicker(
                                    context: context,
                                    initialTime: _selectedEndTime,
                                    helpText: 'Pilih Waktu Pulang Kantor',
                                  );
                                  if (picked != null) {
                                    setState(() => _selectedEndTime = picked);
                                  }
                                },
                                child: InputDecorator(
                                  decoration: const InputDecoration(
                                    labelText: 'Waktu Pulang Kantor',
                                    border: OutlineInputBorder(),
                                    prefixIcon: Icon(Icons.logout),
                                  ),
                                  child: Text(
                                    '${_selectedEndTime.hour.toString().padLeft(2, '0')}:${_selectedEndTime.minute.toString().padLeft(2, '0')}',
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Setelah waktu ini, sistem akan mencatat absen pulang karyawan.',
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

  // --- FUNGSI MANAJEMEN CUTI & DINAS ---
  Future<void> _showLeaveDialog(Map<String, dynamic> employee) async {
    List<dynamic> leaves = [];
    bool isLoadingLeaves = true;

    Future<List<dynamic>> fetchLeaves() async {
      try {
        final data = await Supabase.instance.client
            .from('employee_leaves')
            .select()
            .eq('user_id', employee['id'])
            .order('leave_date', ascending: true);
        return data;
      } catch (e) {
        debugPrint('Error fetching leaves: $e');
        return [];
      }
    }

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            if (isLoadingLeaves) {
              fetchLeaves().then((data) {
                setDialogState(() {
                  leaves = data;
                  isLoadingLeaves = false;
                });
              });
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Icon(Icons.calendar_month, color: Colors.orange[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Cuti & Dinas - ${employee['full_name'] ?? 'Karyawan'}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 550,
                height: 450,
                child: Column(
                  children: [
                    // Tombol Tambah
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('Tambah Cuti / Dinas'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () async {
                          // 1. Pilih tanggal
                          final selectedDate = await showDatePicker(
                            context: ctx,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(2023),
                            lastDate: DateTime(2030),
                            helpText: 'PILIH TANGGAL',
                          );
                          if (selectedDate == null || !ctx.mounted) return;

                          // 2. Dialog detail: tipe + alasan + waktu dinas
                          String selectedType = 'cuti';
                          final reasonCtrl = TextEditingController();
                          TimeOfDay tripStart = const TimeOfDay(
                            hour: 7,
                            minute: 0,
                          );
                          TimeOfDay tripEnd = const TimeOfDay(
                            hour: 17,
                            minute: 0,
                          );

                          final confirmed = await showDialog<bool>(
                            context: ctx,
                            builder: (ctx2) {
                              return StatefulBuilder(
                                builder: (ctx2, setInnerState) {
                                  return AlertDialog(
                                    title: const Text('Detail Cuti / Dinas'),
                                    content: SingleChildScrollView(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // Dropdown tipe
                                          DropdownButtonFormField<String>(
                                            initialValue: selectedType,
                                            decoration: const InputDecoration(
                                              labelText: 'Tipe',
                                              border: OutlineInputBorder(),
                                              prefixIcon: Icon(Icons.category),
                                            ),
                                            items: const [
                                              DropdownMenuItem(
                                                value: 'cuti',
                                                child: Text(
                                                  '🟠 Cuti (Libur Penuh)',
                                                ),
                                              ),
                                              DropdownMenuItem(
                                                value: 'dinas',
                                                child: Text(
                                                  '🔵 Perjalanan Dinas',
                                                ),
                                              ),
                                            ],
                                            onChanged: (val) {
                                              setInnerState(
                                                () => selectedType = val!,
                                              );
                                            },
                                          ),
                                          const SizedBox(height: 16),
                                          // Alasan
                                          TextField(
                                            controller: reasonCtrl,
                                            decoration: InputDecoration(
                                              labelText: selectedType == 'cuti'
                                                  ? 'Keterangan (misal: Cuti Sakit)'
                                                  : 'Keterangan (misal: Meeting Jakarta)',
                                              border:
                                                  const OutlineInputBorder(),
                                              prefixIcon: const Icon(
                                                Icons.notes,
                                              ),
                                            ),
                                          ),
                                          // Time pickers untuk Dinas
                                          if (selectedType == 'dinas') ...[
                                            const SizedBox(height: 16),
                                            const Text(
                                              'Waktu Perjalanan Dinas:',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 14,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: InkWell(
                                                    onTap: () async {
                                                      final picked =
                                                          await showTimePicker(
                                                            context: ctx2,
                                                            initialTime:
                                                                tripStart,
                                                            helpText:
                                                                'Jam Mulai Dinas',
                                                          );
                                                      if (picked != null) {
                                                        setInnerState(
                                                          () => tripStart =
                                                              picked,
                                                        );
                                                      }
                                                    },
                                                    child: InputDecorator(
                                                      decoration:
                                                          const InputDecoration(
                                                            labelText:
                                                                'Jam Mulai',
                                                            border:
                                                                OutlineInputBorder(),
                                                            prefixIcon: Icon(
                                                              Icons.login,
                                                            ),
                                                          ),
                                                      child: Text(
                                                        '${tripStart.hour.toString().padLeft(2, '0')}:${tripStart.minute.toString().padLeft(2, '0')}',
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: InkWell(
                                                    onTap: () async {
                                                      final picked =
                                                          await showTimePicker(
                                                            context: ctx2,
                                                            initialTime:
                                                                tripEnd,
                                                            helpText:
                                                                'Jam Selesai Dinas',
                                                          );
                                                      if (picked != null) {
                                                        setInnerState(
                                                          () =>
                                                              tripEnd = picked,
                                                        );
                                                      }
                                                    },
                                                    child: InputDecorator(
                                                      decoration:
                                                          const InputDecoration(
                                                            labelText:
                                                                'Jam Selesai',
                                                            border:
                                                                OutlineInputBorder(),
                                                            prefixIcon: Icon(
                                                              Icons.logout,
                                                            ),
                                                          ),
                                                      child: Text(
                                                        '${tripEnd.hour.toString().padLeft(2, '0')}:${tripEnd.minute.toString().padLeft(2, '0')}',
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              'Jika dinas mencakup jam masuk → absen masuk di-skip.\n'
                                              'Jika dinas mencakup jam pulang → absen pulang di-skip.',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey[600],
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx2, false),
                                        child: const Text('Batal'),
                                      ),
                                      ElevatedButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx2, true),
                                        child: const Text('Simpan'),
                                      ),
                                    ],
                                  );
                                },
                              );
                            },
                          );

                          // 3. Simpan ke Supabase
                          if (confirmed == true && reasonCtrl.text.isNotEmpty) {
                            try {
                              final insertData = <String, dynamic>{
                                'user_id': employee['id'],
                                'leave_date': DateFormat(
                                  'yyyy-MM-dd',
                                ).format(selectedDate),
                                'reason': reasonCtrl.text.trim(),
                                'type': selectedType,
                              };
                              if (selectedType == 'dinas') {
                                insertData['trip_start_time'] =
                                    '${tripStart.hour.toString().padLeft(2, '0')}:${tripStart.minute.toString().padLeft(2, '0')}:00';
                                insertData['trip_end_time'] =
                                    '${tripEnd.hour.toString().padLeft(2, '0')}:${tripEnd.minute.toString().padLeft(2, '0')}:00';
                              }
                              await Supabase.instance.client
                                  .from('employee_leaves')
                                  .insert(insertData);
                              final updated = await fetchLeaves();
                              setDialogState(() {
                                leaves = updated;
                              });
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      selectedType == 'cuti'
                                          ? 'Cuti berhasil ditambahkan'
                                          : 'Dinas berhasil ditambahkan',
                                    ),
                                  ),
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Gagal: $e')),
                                );
                              }
                            }
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Divider(),
                    // List Cuti & Dinas
                    Expanded(
                      child: isLoadingLeaves
                          ? const Center(child: CircularProgressIndicator())
                          : leaves.isEmpty
                          ? const Center(
                              child: Text(
                                'Belum ada data cuti / dinas.',
                                style: TextStyle(color: Colors.grey),
                              ),
                            )
                          : ListView.builder(
                              itemCount: leaves.length,
                              itemBuilder: (context, index) {
                                final leave = leaves[index];
                                final date = DateTime.parse(
                                  leave['leave_date'],
                                );
                                final formattedDate = DateFormat(
                                  'EEEE, dd MMMM yyyy',
                                  'id_ID',
                                ).format(date);
                                final isPast = date.isBefore(
                                  DateTime.now().subtract(
                                    const Duration(days: 1),
                                  ),
                                );
                                final type = leave['type'] ?? 'cuti';
                                final isDinas = type == 'dinas';

                                // Build subtitle
                                String subtitle = leave['reason'] ?? '';
                                if (isDinas &&
                                    leave['trip_start_time'] != null &&
                                    leave['trip_end_time'] != null) {
                                  final start = leave['trip_start_time']
                                      .toString()
                                      .substring(0, 5);
                                  final end = leave['trip_end_time']
                                      .toString()
                                      .substring(0, 5);
                                  subtitle = '⏰ $start – $end  •  $subtitle';
                                }

                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: isPast
                                        ? Colors.grey[200]
                                        : isDinas
                                        ? Colors.blue[100]
                                        : Colors.orange[100],
                                    child: Icon(
                                      isDinas
                                          ? Icons.flight_takeoff
                                          : Icons.event_busy,
                                      color: isPast
                                          ? Colors.grey
                                          : isDinas
                                          ? Colors.blue[700]
                                          : Colors.orange[700],
                                      size: 20,
                                    ),
                                  ),
                                  title: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isPast
                                              ? Colors.grey[200]
                                              : isDinas
                                              ? Colors.blue[50]
                                              : Colors.orange[50],
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Text(
                                          isDinas ? 'DINAS' : 'CUTI',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: isPast
                                                ? Colors.grey
                                                : isDinas
                                                ? Colors.blue[700]
                                                : Colors.orange[700],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          formattedDate,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                            color: isPast
                                                ? Colors.grey
                                                : Colors.black,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  subtitle: Text(
                                    subtitle,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isPast
                                          ? Colors.grey
                                          : Colors.black87,
                                    ),
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(
                                      Icons.delete,
                                      color: Colors.redAccent,
                                      size: 20,
                                    ),
                                    tooltip: 'Hapus',
                                    onPressed: () async {
                                      final confirmDel = await showDialog<bool>(
                                        context: ctx,
                                        builder: (ctx3) => AlertDialog(
                                          title: Text(
                                            'Hapus ${isDinas ? 'Dinas' : 'Cuti'}?',
                                          ),
                                          content: Text(
                                            'Hapus ${isDinas ? 'dinas' : 'cuti'} tanggal $formattedDate?',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx3, false),
                                              child: const Text('Batal'),
                                            ),
                                            ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.red,
                                                foregroundColor: Colors.white,
                                              ),
                                              onPressed: () =>
                                                  Navigator.pop(ctx3, true),
                                              child: const Text('Hapus'),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirmDel == true) {
                                        try {
                                          await Supabase.instance.client
                                              .from('employee_leaves')
                                              .delete()
                                              .eq('id', leave['id']);
                                          final updated = await fetchLeaves();
                                          setDialogState(() {
                                            leaves = updated;
                                          });
                                        } catch (e) {
                                          if (ctx.mounted) {
                                            ScaffoldMessenger.of(
                                              ctx,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'Gagal menghapus: $e',
                                                ),
                                              ),
                                            );
                                          }
                                        }
                                      }
                                    },
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Tutup'),
                ),
              ],
            );
          },
        );
      },
    );
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
                          DataColumn(label: Text('Cuti')),
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
                                    ? const SizedBox.shrink()
                                    : IconButton(
                                        icon: Icon(
                                          Icons.calendar_month,
                                          color: Colors.orange[700],
                                          size: 20,
                                        ),
                                        tooltip: 'Atur Cuti',
                                        onPressed: () => _showLeaveDialog(emp),
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

// --- 6. HALAMAN MANAJEMEN HARI LIBUR ---
class HolidayManagementPage extends StatefulWidget {
  const HolidayManagementPage({super.key});

  @override
  State<HolidayManagementPage> createState() => _HolidayManagementPageState();
}

class _HolidayManagementPageState extends State<HolidayManagementPage> {
  List<dynamic> _holidays = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchHolidays();
  }

  Future<void> _fetchHolidays() async {
    setState(() => _isLoading = true);
    try {
      final data = await Supabase.instance.client
          .from('holidays')
          .select()
          .order('holiday_date', ascending: true);
      setState(() => _holidays = data);
    } catch (e) {
      debugPrint("Error fetching holidays: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _addHoliday() async {
    // 1. Pilih Tanggal
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2023),
      lastDate: DateTime(2030),
      helpText: "PILIH TANGGAL LIBUR",
    );

    if (selectedDate == null || !mounted) return;

    // 2. Isi Keterangan
    final descCtrl = TextEditingController();
    final isConfirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Keterangan Libur"),
        content: TextField(
          controller: descCtrl,
          decoration: const InputDecoration(
            labelText: "Contoh: Idul Fitri / Libur Nasional",
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Batal"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Simpan"),
          ),
        ],
      ),
    );

    // 3. Simpan ke Supabase
    if (isConfirmed == true && descCtrl.text.isNotEmpty) {
      try {
        await Supabase.instance.client.from('holidays').insert({
          'holiday_date': DateFormat('yyyy-MM-dd').format(selectedDate),
          'description': descCtrl.text.trim(),
        });
        _fetchHolidays();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Hari Libur Berhasil Ditambahkan")),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Gagal (Mungkin tanggal sudah ada): $e")),
          );
        }
      }
    }
  }

  Future<void> _deleteHoliday(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Hapus Hari Libur?"),
        content: const Text(
          "Apakah Anda yakin ingin menghapus jadwal libur ini?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Batal"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Hapus"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await Supabase.instance.client.from('holidays').delete().eq('id', id);
        _fetchHolidays();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text("Gagal menghapus: $e")));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Pengaturan Hari Libur",
                style: GoogleFonts.poppins(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo[900],
                ),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text("Tambah Hari Libur"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 15,
                  ),
                ),
                onPressed: _addHoliday,
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            "Pada tanggal yang terdaftar di bawah ini, karyawan tidak perlu melakukan absensi.",
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _holidays.isEmpty
                ? const Center(
                    child: Text(
                      "Belum ada jadwal hari libur yang ditambahkan.",
                    ),
                  )
                : Card(
                    child: ListView.builder(
                      itemCount: _holidays.length,
                      itemBuilder: (context, index) {
                        final item = _holidays[index];
                        // Format Tanggal
                        final date = DateTime.parse(item['holiday_date']);
                        final formattedDate = DateFormat(
                          'EEEE, dd MMMM yyyy',
                          'id_ID',
                        ).format(date);

                        // Beri indikator jika tanggal libur sudah lewat
                        final isPast = date.isBefore(
                          DateTime.now().subtract(const Duration(days: 1)),
                        );

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isPast
                                ? Colors.grey[300]
                                : Colors.red[100],
                            child: Icon(
                              Icons.event_busy,
                              color: isPast ? Colors.grey : Colors.red,
                            ),
                          ),
                          title: Text(
                            formattedDate,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isPast ? Colors.grey : Colors.black,
                            ),
                          ),
                          subtitle: Text(
                            item['description'],
                            style: TextStyle(
                              color: isPast ? Colors.grey : Colors.black87,
                            ),
                          ),
                          trailing: IconButton(
                            icon: const Icon(
                              Icons.delete,
                              color: Colors.redAccent,
                            ),
                            onPressed: () => _deleteHoliday(item['id']),
                            tooltip: "Hapus Libur",
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
