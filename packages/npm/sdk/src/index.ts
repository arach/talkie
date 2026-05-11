// @talkie/client — SDK for connecting to Talkie services

export { TalkieClient } from "./client";
export type { ClientEvents } from "./client";

export { DictationSession } from "./dictation";
export { WebSocketTransport } from "./transport";
export { ServiceDiscovery } from "./discovery";
export { authenticate } from "./auth";
export type { AuthOptions } from "./auth";

export { Emitter } from "./events";

export {
  TalkieError,
  ConnectionError,
  CallError,
  TimeoutError,
  AuthError,
  MicBusyError,
} from "./errors";

export {
  SERVICE_PORTS,
  SERVICES_JSON_PATH,
  DEFAULT_CALL_TIMEOUT,
  STREAMING_CALL_TIMEOUT,
} from "./constants";

export type { ServiceName } from "./constants";

export type {
  RpcRequest,
  RpcResponse,
  RpcEvent,
  WireMessage,
  ServiceEntry,
  ServicesFile,
  Capability,
  RegisterParams,
  RegisterResult,
  AuthState,
  TalkieClientOptions,
  DictationState,
  DictationOptions,
  DictationEvents,
  TransportEvents,
} from "./types";
