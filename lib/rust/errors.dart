/// One exception type per engine status, each carrying the engine's message.
///
/// The engine's errors are already written for humans ("this file isn't an
/// image we can read"), so these types add classification without rewording.
sealed class EngineException implements Exception {
  EngineException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The image could not be processed: corrupt file, unsupported format,
/// dimensions out of budget. The message says what actually happened.
final class EngineProcessingException extends EngineException {
  EngineProcessingException(super.message);
}

/// The boundary was used incorrectly. This is a bug in the caller, not in the
/// user's file, and it should be impossible to hit through the public API.
final class EngineContractException extends EngineException {
  EngineContractException(super.message);
}

/// The engine deliberately failed, for the contract test.
final class EngineSelfTestException extends EngineException {
  EngineSelfTestException(super.message);
}
