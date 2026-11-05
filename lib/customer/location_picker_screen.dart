import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../util.dart';

class PickedLocation {
  final String label;
  final String addressText;
  final String? details;
  final double lat;
  final double lng;

  /// دقة GPS بالمتر. null = العميل حرّك الدبوس يدوياً بعيد عن قراءة الـ GPS
  final double? accuracyM;

  const PickedLocation({
    required this.label,
    required this.addressText,
    required this.details,
    required this.lat,
    required this.lng,
    required this.accuracyM,
  });
}

/// تحديد موقع التوصيل:
///  1) قراءة GPS بأعلى دقة (بنجمع قراءات لحد ~12 ثانية ونختار الأدق).
///  2) خريطة OpenStreetMap مجانية والدبوس ثابت في النص: العميل يحرّك الخريطة تحته.
///  3) الإحداثيات بتتخزن زي ما هي (من غير تخمين عنوان) + العنوان والعلامة المميزة نصاً.
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key});

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  static const _cairo = LatLng(30.0444, 31.2357);

  final _map = MapController();
  final _label = TextEditingController(text: 'البيت');
  final _address = TextEditingController();
  final _details = TextEditingController();

  Position? _gps;
  bool _locating = false;
  String? _msg;

  @override
  void dispose() {
    _label.dispose();
    _address.dispose();
    _details.dispose();
    _map.dispose();
    super.dispose();
  }

  /// بنسمع على stream الموقع ونحتفظ بأدق قراءة
  Future<Position?> _bestFix() async {
    Position? best;
    final done = Completer<Position?>();
    final timer = Timer(const Duration(seconds: 12), () {
      if (!done.isCompleted) done.complete(best);
    });
    final sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
      ),
    ).listen(
      (p) {
        if (best == null || p.accuracy < best!.accuracy) best = p;
        if (mounted) setState(() => _gps = best);
        if (p.accuracy <= 8 && !done.isCompleted) done.complete(best);
      },
      onError: (_) {
        if (!done.isCompleted) done.complete(best);
      },
    );
    final result = await done.future;
    timer.cancel();
    await sub.cancel();
    return result;
  }

  Future<void> _locate() async {
    if (_locating) return;
    setState(() {
      _locating = true;
      _msg = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() => _msg = 'فعّل خدمة الموقع (GPS) من إعدادات الموبايل ثم حاول تاني');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        setState(() => _msg =
            'من فضلك اسمح للتطبيق بالوصول للموقع، أو حرّك الخريطة وحدد مكانك يدوياً');
        return;
      }
      final best = await _bestFix();
      if (best == null) {
        setState(() => _msg =
            'مقدرناش نحدد موقعك. اخرج لمكان مفتوح أو حرّك الخريطة يدوياً.');
        return;
      }
      _map.move(LatLng(best.latitude, best.longitude), 18);
    } catch (e) {
      if (mounted) setState(() => _msg = 'تعذّر تحديد الموقع: $e');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _confirm() {
    if (_address.text.trim().isEmpty) {
      showSnack(context, 'اكتب العنوان (الشارع والمنطقة)', error: true);
      return;
    }
    if (_details.text.trim().isEmpty) {
      showSnack(context, 'اكتب تفاصيل العنوان (عمارة / دور / شقة / علامة مميزة)',
          error: true);
      return;
    }
    final cam = _map.camera;
    if (cam.zoom < 16) {
      showSnack(context, 'قرّب الخريطة أكتر عشان تحدد باب العمارة بدقة', error: true);
      return;
    }
    final c = cam.center;
    double? acc;
    final gps = _gps;
    if (gps != null) {
      final d = Geolocator.distanceBetween(
          gps.latitude, gps.longitude, c.latitude, c.longitude);
      if (d <= 15) acc = gps.accuracy;
    }
    Navigator.of(context).pop(PickedLocation(
      label: _label.text.trim().isEmpty ? 'البيت' : _label.text.trim(),
      addressText: _address.text.trim(),
      details: _details.text.trim(),
      lat: c.latitude,
      lng: c.longitude,
      accuracyM: acc,
    ));
  }

  Widget _accuracyChip() {
    final gps = _gps;
    if (_locating && gps == null) {
      return const Text('جاري تحديد موقعك بدقة...');
    }
    if (gps == null) {
      return const Text('حرّك الخريطة وحدّد مكان التوصيل بالدبوس');
    }
    final a = gps.accuracy.round();
    final Color color;
    final String text;
    if (a <= 20) {
      color = Colors.green.shade800;
      text = 'دقة GPS ممتازة (±$a متر)';
    } else if (a <= 50) {
      color = Colors.orange.shade800;
      text = 'دقة GPS متوسطة (±$a متر) - تأكد إن الدبوس على باب العمارة';
    } else {
      color = Colors.red.shade700;
      text = 'دقة GPS ضعيفة (±$a متر) - اخرج لمكان مفتوح أو حرّك الدبوس يدوياً';
    }
    return Text(_locating ? '$text (بيتحسّن...)' : text,
        style: TextStyle(color: color));
  }

  @override
  Widget build(BuildContext context) {
    final gps = _gps;
    final mapHeight = MediaQuery.of(context).size.height * 0.42;
    return Scaffold(
      appBar: AppBar(title: const Text('حدد موقع التوصيل')),
      body: Column(
        children: [
          SizedBox(
            height: mapHeight,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: _cairo,
                    initialZoom: 14,
                    minZoom: 4,
                    maxZoom: 19,
                    onMapReady: _locate,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.supermarketpos.customer',
                    ),
                    if (gps != null)
                      CircleLayer(circles: [
                        CircleMarker(
                          point: LatLng(gps.latitude, gps.longitude),
                          radius: gps.accuracy,
                          useRadiusInMeter: true,
                          color: Colors.blue.withOpacity(0.15),
                          borderColor: Colors.blue,
                          borderStrokeWidth: 1,
                        ),
                      ]),
                    if (gps != null)
                      MarkerLayer(markers: [
                        Marker(
                          point: LatLng(gps.latitude, gps.longitude),
                          width: 16,
                          height: 16,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ),
                      ]),
                    const RichAttributionWidget(
                      attributions: [
                        TextSourceAttribution('© OpenStreetMap contributors'),
                      ],
                    ),
                  ],
                ),
                // الدبوس ثابت في نص الخريطة (طرفه السفلي هو الموقع المختار)
                IgnorePointer(
                  child: Center(
                    child: Transform.translate(
                      offset: const Offset(0, -22),
                      child: Icon(Icons.location_pin,
                          size: 44, color: Colors.red.shade700),
                    ),
                  ),
                ),
                PositionedDirectional(
                  end: 12,
                  top: 12,
                  child: FloatingActionButton.small(
                    heroTag: 'locate',
                    onPressed: _locating ? null : _locate,
                    child: _locating
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.my_location),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Align(
                alignment: AlignmentDirectional.centerStart, child: _accuracyChip()),
          ),
          if (_msg != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(_msg!, style: TextStyle(color: Colors.red.shade700)),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _label,
                  decoration: const InputDecoration(
                      labelText: 'اسم العنوان (البيت / الشغل)',
                      border: OutlineInputBorder(),
                      isDense: true),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _address,
                  decoration: const InputDecoration(
                      labelText: 'الشارع والمنطقة',
                      border: OutlineInputBorder(),
                      isDense: true),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _details,
                  decoration: const InputDecoration(
                      labelText: 'رقم العمارة / الدور / الشقة / علامة مميزة',
                      border: OutlineInputBorder(),
                      isDense: true),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _confirm,
                  icon: const Icon(Icons.check),
                  label: const Text('تأكيد الموقع'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
