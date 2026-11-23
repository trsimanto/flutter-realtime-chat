/// Lets the demo mode pretend the device lost its network.
abstract interface class NetworkSimulator {
  bool get isNetworkAvailable;

  void setNetworkAvailable({required bool available});
}
