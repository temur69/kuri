import 'dart:math';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'services/system_engine.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemEngine.initNotificationService();
  runApp(const MaterialApp(home: DeliveryMasterApp(), debugShowCheckedModeBanner: false));
}

class DeliveryMasterApp extends StatefulWidget {
  const DeliveryMasterApp({Key? key}) : super(key: key);

  @override
  State<DeliveryMasterApp> createState() => _DeliveryMasterAppState();
}

class _DeliveryMasterAppState extends State<DeliveryMasterApp> {
  int _tab = 0;
  final List<OrderModel> _orderPool = [];
  double _courierWallet = 240.0;
  bool _isCourierOnline = true;

  final _customerNameCtrl = TextEditingController();
  final _customerPhoneCtrl = TextEditingController();
  final _pickupCtrl = TextEditingController();
  final _dropoffCtrl = TextEditingController();
  double _calcKm = 0.0;
  double _calcPrice = 0.0;

  bool _isAdminUnlocked = false;
  final _adminPinCtrl = TextEditingController();
  final _baseFeeCtrl = TextEditingController(text: SystemConfig.baseFee.toString());
  final _kmFeeCtrl = TextEditingController(text: SystemConfig.perKmFee.toString());
  final _commCtrl = TextEditingController(text: SystemConfig.commissionRate.toString());

  void _calculateDeliveryCost() async {
    if (_pickupCtrl.text.isEmpty || _dropoffCtrl.text.isEmpty) return;
    final p = await SystemEngine.resolveLocation(_pickupCtrl.text);
    final d = await SystemEngine.resolveLocation(_dropoffCtrl.text);
    double km = SystemEngine.calculateDistance(p['lat'], p['lng'], d['lat'], d['lng']);
    double price = SystemEngine.computePrice(km);

    setState(() {
      _calcKm = km;
      _calcPrice = price;
    });
  }

  void _submitNewOrder() {
    if (_customerNameCtrl.text.isEmpty || _customerPhoneCtrl.text.isEmpty) return;
    final pin = (1000 + Random().nextInt(9000)).toString();
    final earnings = SystemEngine.computeCourierShare(_calcPrice);

    final order = OrderModel(
      id: 'PKT-${Random().nextInt(9000) + 1000}',
      customerName: _customerNameCtrl.text,
      customerPhone: _customerPhoneCtrl.text,
      pickupAddress: _pickupCtrl.text,
      dropoffAddress: _dropoffCtrl.text,
      distanceKm: _calcKm,
      totalPrice: _calcPrice,
      courierEarnings: earnings,
      pinCode: pin,
    );

    setState(() {
      _orderPool.add(order);
      _calcKm = 0.0;
      _calcPrice = 0.0;
      _pickupCtrl.clear();
      _dropoffCtrl.clear();
    });

    SystemEngine.startOrderAlarm(order.id, order.courierEarnings);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sipariş Alındı!'),
        content: Text('Kurye havuzuna iletildi.\nTeslimat Güvenlik Kodunuz: $pin\n(Paketi teslim alırken kuryeye iletiniz)'),
        actions: [ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tamam'))],
      ),
    );
  }

  void _openMapRoute(String address) async {
    final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(address)}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _callPhone(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  void _verifyDeliveryPin(OrderModel ord) {
    final pinTextCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Teslimat Teyit Kodu'),
        content: TextField(
          controller: pinTextCtrl,
          keyboardType: TextInputType.number,
          maxLength: 4,
          decoration: const InputDecoration(hintText: 'Müşterinin 4 haneli PIN kodu', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
          ElevatedButton(
            onPressed: () {
              if (pinTextCtrl.text == ord.pinCode) {
                setState(() {
                  ord.state = OrderState.delivered;
                  _courierWallet += ord.courierEarnings;
                });
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Teslimat kapandı! +${ord.courierEarnings} ₺ eklendi.')),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Hatalı Kod!'), backgroundColor: Colors.red),
                );
              }
            },
            child: const Text('Doğrula'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_tab == 0 ? 'Müşteri Paneli' : _tab == 1 ? 'Kurye Konsolu' : 'Yönetim Merkezi'),
        backgroundColor: _tab == 2 ? Colors.indigo[900] : Colors.amber[800],
        foregroundColor: Colors.white,
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          _buildCustomerView(),
          _buildCourierView(),
          _buildAdminView(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
        onTap: (i) => setState(() => _tab = i),
        selectedItemColor: _tab == 2 ? Colors.indigo[900] : Colors.amber[900],
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Müşteri'),
          BottomNavigationBarItem(icon: Icon(Icons.two_wheeler), label: 'Kurye'),
          BottomNavigationBarItem(icon: Icon(Icons.admin_panel_settings), label: 'Yönetici'),
        ],
      ),
    );
  }

  Widget _buildCustomerView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(controller: _customerNameCtrl, decoration: const InputDecoration(labelText: 'Adınız Soyadınız', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: _customerPhoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Telefon Numaranız', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(
            controller: _pickupCtrl,
            decoration: const InputDecoration(labelText: 'Alış Noktası (Link veya Adres)', prefixIcon: Icon(Icons.store), border: OutlineInputBorder()),
            onChanged: (_) => _calculateDeliveryCost(),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _dropoffCtrl,
            decoration: const InputDecoration(labelText: 'Teslim Noktası (Link veya Adres)', prefixIcon: Icon(Icons.location_on, color: Colors.red), border: OutlineInputBorder()),
            onChanged: (_) => _calculateDeliveryCost(),
          ),
          const SizedBox(height: 14),
          if (_calcKm > 0)
            Card(
              color: Colors.amber[50],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Text('Mesafe: $_calcKm KM', style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text('Tutar: $_calcPrice ₺', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green)),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 14),
          ElevatedButton(
            onPressed: _calcPrice > 0 ? _submitNewOrder : null,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber[800], padding: const EdgeInsets.all(16)),
            child: const Text('Kurye Çağır', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          const Divider(height: 30),
          const Text('Sipariş Geçmişim', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ..._orderPool.map((o) => ListTile(
            leading: Icon(o.state == OrderState.delivered ? Icons.check_circle : Icons.timer, color: Colors.amber[800]),
            title: Text('${o.id} • ${o.dropoffAddress}'),
            subtitle: Text('Güvenlik Kodu: ${o.pinCode} • Durum: ${o.state.name}'),
            trailing: Text('${o.totalPrice} ₺', style: const TextStyle(fontWeight: FontWeight.bold)),
          )),
        ],
      ),
    );
  }

  Widget _buildCourierView() {
    final activeOrders = _orderPool.where((o) => o.state != OrderState.delivered).toList();

    return Column(
      children: [
        Container(
          color: Colors.grey[200],
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  CircleAvatar(radius: 6, backgroundColor: _isCourierOnline ? Colors.green : Colors.red),
                  const SizedBox(width: 8),
                  Text(_isCourierOnline ? 'Müsait' : 'Molada', style: const TextStyle(fontWeight: FontWeight.bold)),
                  Switch(value: _isCourierOnline, activeColor: Colors.green, onChanged: (v) => setState(() => _isCourierOnline = v)),
                ],
              ),
              Text('Cüzdan: ${_courierWallet.toStringAsFixed(1)} ₺', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green)),
            ],
          ),
        ),
        if (SystemEngine.isAlarmPlaying)
          Container(
            color: Colors.red,
            padding: const EdgeInsets.all(10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('🚨 ÇALAN ÇAĞRI VAR!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ElevatedButton(
                  onPressed: () => setState(() => SystemEngine.stopOrderAlarm()),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.white),
                  child: const Text('Alarmı Sustur', style: TextStyle(color: Colors.black)),
                ),
              ],
            ),
          ),
        Expanded(
          child: !_isCourierOnline
              ? const Center(child: Text('Moladasınız. Çağrı almak için çevrimiçi olun.'))
              : activeOrders.isEmpty
                  ? const Center(child: Text('Şu an bekleyen çağrı yok.'))
                  : ListView.builder(
                      itemCount: activeOrders.length,
                      itemBuilder: (ctx, idx) {
                        final ord = activeOrders[idx];
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Hakediş: ${ord.courierEarnings} ₺', style: const TextStyle(fontSize: 18, color: Colors.green, fontWeight: FontWeight.bold)),
                                    Text('${ord.distanceKm} KM', style: const TextStyle(fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                const Divider(),
                                Text('Alış: ${ord.pickupAddress}'),
                                Text('Teslim: ${ord.dropoffAddress}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    IconButton(icon: const Icon(Icons.phone, color: Colors.green), onPressed: () => _callPhone(ord.customerPhone)),
                                    IconButton(icon: const Icon(Icons.navigation, color: Colors.blue), onPressed: () => _openMapRoute(ord.dropoffAddress)),
                                    const Spacer(),
                                    if (ord.state == OrderState.pending)
                                      ElevatedButton(
                                        onPressed: () {
                                          setState(() => ord.state = OrderState.accepted);
                                          SystemEngine.stopOrderAlarm();
                                        },
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.amber[800]),
                                        child: const Text('Kabul Et', style: TextStyle(color: Colors.white)),
                                      )
                                    else if (ord.state == OrderState.accepted)
                                      ElevatedButton(
                                        onPressed: () => setState(() => ord.state = OrderState.onWay),
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                                        child: const Text('Yoldayım', style: TextStyle(color: Colors.white)),
                                      )
                                    else if (ord.state == OrderState.onWay)
                                      ElevatedButton(
                                        onPressed: () => _verifyDeliveryPin(ord),
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                                        child: const Text('Kodu Gir & Bitir', style: TextStyle(color: Colors.white)),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildAdminView() {
    if (!_isAdminUnlocked) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.security, size: 64, color: Colors.indigo),
              const SizedBox(height: 16),
              const Text('Yönetici PIN Girişi (Varsayılan: 1923)', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              TextField(
                controller: _adminPinCtrl,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 4,
                decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'PIN'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (_adminPinCtrl.text == SystemConfig.adminPin) {
                    setState(() => _isAdminUnlocked = true);
                  }
                },
                style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48), backgroundColor: Colors.indigo),
                child: const Text('Giriş Yap', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    double totalRevenue = _orderPool.fold(0.0, (sum, o) => sum + o.totalPrice);
    double companyCut = totalRevenue * (SystemConfig.commissionRate / 100);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            color: Colors.indigo[900],
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Text('Ciro: ${totalRevenue.toStringAsFixed(1)} ₺', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  Text('Kasa: ${companyCut.toStringAsFixed(1)} ₺', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                  Text('Paket: ${_orderPool.length}', style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(controller: _baseFeeCtrl, decoration: const InputDecoration(labelText: 'Açılış Baz Ücret (₺)', border: OutlineInputBorder()), keyboardType: TextInputType.number),
          const SizedBox(height: 8),
          TextField(controller: _kmFeeCtrl, decoration: const InputDecoration(labelText: 'KM Başı Ücret (₺)', border: OutlineInputBorder()), keyboardType: TextInputType.number),
          const SizedBox(height: 8),
          TextField(controller: _commCtrl, decoration: const InputDecoration(labelText: 'Komisyon Kesintisi (%)', border: OutlineInputBorder()), keyboardType: TextInputType.number),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Gece Tarifesi (+%25)'),
            value: SystemConfig.nightMode,
            onChanged: (v) => setState(() => SystemConfig.nightMode = v),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                SystemConfig.baseFee = double.tryParse(_baseFeeCtrl.text) ?? SystemConfig.baseFee;
                SystemConfig.perKmFee = double.tryParse(_kmFeeCtrl.text) ?? SystemConfig.perKmFee;
                SystemConfig.commissionRate = double.tryParse(_commCtrl.text) ?? SystemConfig.commissionRate;
              });
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ayarlar güncellendi!')));
            },
            style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(44), backgroundColor: Colors.indigo),
            child: const Text('Tarifeleri Kaydet', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
