abstract class Build123dTransport {
  Stream<Map<String, dynamic>> generate(Map<String, dynamic> job);
  void cancel();
}
