# amqp_rpc_binder

## Features

amqp_rpc_binder is a package that allow to create simple remote and distributed task through RabbitMQ.

it use the pattern of Working queues and RPC describe [here](https://www.rabbitmq.com/tutorials/tutorial-two-python.html) and [here](https://www.rabbitmq.com/tutorials/tutorial-six-python.html)

## Example
binding and calling can be done really simple :
```dart
class Auth {
  @Register()
  bool check(String username, String password) => return true;
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
```

## Authors
- Kevin PLATEL <platel.kevin@gmail.com>

