library amqp_rpc_binder;

import 'dart:async';
import 'dart:mirrors';
import 'dart:convert';

import 'package:rpc/rpc.dart';
import 'package:rpc/common.dart';
import 'package:rpc/src/parser.dart';
import 'package:rpc/src/config.dart';

import 'package:uuid/uuid.dart';

import 'package:dart_amqp/dart_amqp.dart';
export 'package:dart_amqp/dart_amqp.dart';

part 'src/amqp_rpc_binder.dart';