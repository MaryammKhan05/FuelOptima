import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FuelOptima',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const MapScreen(),
    );
  }
}

class MapScreen extends StatelessWidget {
  const MapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FuelOptima - Pakistan Map'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: FlutterMap(
        options: const MapOptions(
          initialCenter: LatLng(30.3753, 69.3451), // Center of Pakistan
          initialZoom: 5.5, // Zoomed out to show whole country
          maxZoom: 18,
          minZoom: 4,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.fueloptima',
          ),
        ],
      ),
    );
  }
}