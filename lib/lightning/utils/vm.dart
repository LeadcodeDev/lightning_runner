import 'dart:developer';

import 'package:vm_service/utils.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

Future<VmService> createVmService() async {
  final devServiceURL = (await Service.getInfo()).serverUri;

  if (devServiceURL == null) {
    throw StateError('VM service not available! You need to run dart with --enable-vm-service.');
  }

  final wsURL = convertToWebSocketUrl(serviceProtocolUrl: devServiceURL);
  return vmServiceConnectUri(wsURL.toString());
}