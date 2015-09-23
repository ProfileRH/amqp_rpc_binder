part of amqp_rpc_binder;

Map<Type, ApiConfigSchema> __convert_table__ = {};
var __parser__ = new ApiParser();

/// Transform a json object to a object of type t.
/// It use rpc package to do so : [rpc](https://pub.dartlang.org/packages/rpc)
fromJson(Type t, var json) {
  if (__convert_table__[t] == null) {
    __convert_table__[t] = __parser__.parseSchema(reflectClass(t), false);
  }
  return __convert_table__[t].fromRequest(json);
}

/// Transform a object of type t to a json object.
/// It use rpc package to do so : [rpc](https://pub.dartlang.org/packages/rpc)
toJson(var obj) {
  var t = obj.runtimeType;
  if (__convert_table__[t] == null) {
    __convert_table__[t] = __parser__.parseSchema(reflectClass(t), false);
  }
  return __convert_table__[t].toResponse(obj);
}

/// Register is a annotation use to tag the resources that will be available through rabbitMQ
///
/// ex:
///     class Auth {
///       @Register()
///       var resource;
///       // ...
///       @Register()
///       bool login() { /* .. */ }
///     }
///
class Register {
  const Register();
}

/// [AMQPBinder] will register the resources expose by a object to rabbitMQ
class AMQPBinder {
  /// Key use during serialization
  static const String NAMED_ARGUMENT_KEY = "__named_argument__";
  /// Key use during serialization
  static const String POSITIONAL_ARGUMENT_KEY = "__positional_argument__";

  /// [binderName] will be used as prefix of rabbitMQ queue
  String binderName;

  /// [client] is a RabbitMQ client
  Client client;

  /// instance of the class register inside the binder
  Map<String, InstanceMirror> registeredObject = {};

  /// method and attribute registered inside a class
  Map<String, dynamic> registeredCall = {};


  AMQPBinder(this.client, {this.binderName: "rpc.binder"});

  /// Create the channel and queue inside RabbitMQ
  init() async {
    Channel c = await client.channel();
    c = await c.qos(0, 1);
    Queue q = await c.queue('', exclusive: true);
  }

  /// Register a instance
  register(var obj, {String prefix}) {
    _register(obj, prefix);
  }

  _register(var obj, String prefix) {
    ClassMirror instClass = reflectClass(obj.runtimeType);

    registeredObject[prefix != null ? '.' + prefix : MirrorSystem.getName(instClass.qualifiedName)] = reflect(obj);
    instClass.declarations.forEach((var key, var value) {
      if (value.metadata.length > 0) {
        for (var metadata in value.metadata) {
          if (metadata.reflectee is Register) {
            var name = MirrorSystem.getName(value.qualifiedName);
            if (prefix != null) {
              name = prefix + '.' + name.split('.').last;
            }
            if (name[0] != '.')
              name = '.' + name;
            registeredCall["${binderName}${name}"] = value;
            _registerInWorkingQueue("${binderName}${name}");
          }
        }
      }
    });
  }

  _registerInWorkingQueue(String name) async {
    Channel c = await client.channel();
    c = await c.qos(0, 1);
    Queue q = await c.queue(name);
    Consumer con = await q.consume();
    con.listen((AmqpMessage mes) {
      var json = mes.payloadAsJson;
      var val = _getValue(name, json[AMQPBinder.POSITIONAL_ARGUMENT_KEY], json[AMQPBinder.NAMED_ARGUMENT_KEY]);
      if (val is Future)
        val.then((v) => _returnValue(mes, v));
      else
        _returnValue(mes, val);
    });
  }

  _returnValue(AmqpMessage mes, var val) {
    if (val is int)
      val = "${val}";
    else if (val is Map)
      val = val;
    else if (val is bool)
      val = val;
    else if (val is double)
      val = "${val}";
    else if (val is String)
      val = val;
    else if (val is List) {
      val = new List.generate(val.length, (i) {
        if (val[i] is! num && val[i] is! Iterable && val[i] is! String)
          return toJson(val[i]);
        return val[i];
      });
    }
    else
      val = toJson(val);
    mes.reply({"type": val.runtimeType.toString(), "value": val});
  }

  _getValue(String key, List positionalArguments, Map namedArguments) {
    String qualifiedName = key.substring(binderName.length);
    Symbol s = new Symbol(qualifiedName);
    InstanceMirror obj = registeredObject[qualifiedName.substring(0, qualifiedName.lastIndexOf('.'))];
    var m = registeredCall[key];
    Map<Symbol, dynamic> na = {};
    namedArguments.forEach((k, v) {
      na[new Symbol(k)] = v;
    });

    var val = null;
    if (m is! VariableMirror) {
      try {
        val = obj.invoke(m.simpleName, positionalArguments, na).reflectee;
      } catch (e, stackTrace) {
        print(stackTrace);
        val = null;
      }
    } else {
      val = obj.getField(m.simpleName).reflectee;
    }
    return val;
  }
}

/// [AMQPCaller] will be use as a 'functor' on a remote call
class AMQPCaller {
  /// Uuid generator for the name of the reply queue
  static Uuid uuid = new Uuid();
  /// RabbitMQ client
  Client client;
  /// Queue that will handle reply receiving
  Queue responseQueue;
  /// Queue to push request
  Queue callQueue;
  MessageProperties _p;
  /// RabbitMQ channel
  Channel chan;
  var _con;
  /// Name of the remote call
  String remoteName;
  StreamController _streamController = new StreamController.broadcast();

  /// [AMQPCall]
  /// the constructor require 2 parameter :
  /// - client : a RabbitMQ client
  /// - remoteName : the name of the remote call, by default 'rpc.binder.<ClassName>.<MethodName>'
  AMQPCaller(this.client, this.remoteName);

  /// Call a remote resources.
  /// The return type will be the return type of the remote resources for simple type (bool, int, String, ...) or a JSON representation of the object.
  /// You can get it back by calling :
  ///     fromJson(YouType, await caller.remoteCall());
  remoteCall([List positionalArgument , Map namedArgument]) async {
    if (_p == null) {
      _p = new MessageProperties();
      _p.corellationId = uuid.v4();
    }

    if (chan == null)
      chan = await client.channel();
    if (responseQueue == null)
      responseQueue = await chan.queue('reply-${_p.corellationId}', exclusive: true);
    if (callQueue == null)
      callQueue = await chan.queue(remoteName);
    _p.replyTo = responseQueue.name;
    if (positionalArgument == null)
      positionalArgument = [];
    if (namedArgument == null)
      namedArgument = {};
    callQueue.publish(JSON.encode({"${AMQPBinder.POSITIONAL_ARGUMENT_KEY}": new List.from(positionalArgument), "${AMQPBinder.NAMED_ARGUMENT_KEY}": new Map.from(namedArgument)}), properties: p);
    if (_con == null) {
      _con = await responseQueue.consume();
      _con.listen((AmqpMessage mes) {
        var json = mes.payloadAsJson;
        var type = json["type"];
        var value = json["value"];
        _streamController.add(value);
      });
    }
    return _streamController.stream.first;
  }

  noSuchMethod(Invocation invocation) =>
  invocation.memberName == #call ? this.remoteCall(invocation.positionalArguments, invocation.namedArguments)
  : super.noSuchMethod(invocation);
}