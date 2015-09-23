import 'package:amqp_rpc_binder/amqp_rpc_binder.dart';

class Auth {
  @Register()
  bool check(String username, String password) {
    if (username == "admin" && password == "admin")
      return true;
    return false;
  }
}

main() async {
  var client = new Client(settings: new ConnectionSettings(host: '192.168.99.100'));
  var binder = new AMQPBinder(client);

  await binder.init();
  binder.register(new Auth());

  var checkAuth = new AMQPCaller(client, 'rpc.binder.Auth.check');

  bool isAuth = await checkAuth.remoteCall(["admin", "admin"]);
  if (isAuth) {
    print("User is authentificate");
  } else {
    print("Wrong credentials");
  }
  client.close();
}