import 'dart:convert';
import 'dart:io';

import 'package:git/git.dart';
import 'package:io/ansi.dart';
import 'package:io/io.dart';
import 'package:path/path.dart' as p;

Future<void> main() async {
  try {
    print(await defaultBranch());
  } on UserException catch (e) {
    print(red.wrap(e.message));
    exitCode = ExitCode.config.code;
  }
}

/// Returns the name of the current default branch – if possible.
///
/// Otherwise, throws a [UserException].
Future<String> defaultBranch() async {
  GitDir dir;
  try {
    dir = await GitDir.fromExisting(p.current, allowSubdirectory: true);
  } on ProcessException {
    throw UserException("We don't appear to be within a Git directory.");
  }

  final result = await dir.runCommand([
    'branch',
    '-a',
    '--format',
    '%(refname);%(upstream);%(push);%(symref)',
  ]);

  assert(result.exitCode == 0);

  final outputs = LineSplitter.split(result.stdout as String)
      .map((e) => _Output.parse(e))
      .toList();

  final remoteHead = outputs.singleWhere(
    (element) => element.refname == 'refs/remotes/origin/HEAD',
    orElse: () => null,
  );

  if (remoteHead == null) {
    throw UserException('Could not find a remote HEAD.');
  }

  final likelyDefaultBranches = outputs
      .where(
        (element) =>
            element.push == remoteHead.symref ||
            element.upstream == remoteHead.symref,
      )
      .toList();

  if (likelyDefaultBranches.isEmpty) {
    throw UserException('Could not find a matching local branch.');
  }
  if (likelyDefaultBranches.length > 1) {
    throw UserException('Found too many matching local branches.');
  }

  final likelyDefaultBranch = likelyDefaultBranches.single;

  const localBranchPrefix = 'refs/heads/';

  if (likelyDefaultBranch.refname.startsWith(localBranchPrefix)) {
    return likelyDefaultBranch.refname.substring(localBranchPrefix.length);
  }
  throw UserException(
    'The local branch did not have the expected prefix: '
    '"$localBranchPrefix".',
  );
}

class _Output {
  final String refname, upstream, push, symref;

  _Output(this.refname, this.upstream, this.push, this.symref);

  factory _Output.parse(String line) {
    final split = line.split(';');
    assert(split.length == 4);
    return _Output(split[0], split[1], split[2], split[3]);
  }

  @override
  String toString() => [refname, upstream, push, symref].join(',');
}

class UserException implements Exception {
  final String message;

  UserException(this.message);

  @override
  String toString() => 'UserException: $message';
}
