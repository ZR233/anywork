/// Identifies one resource across its actual owner and its proxies.
///
/// The identity contains no user data and is meaningful within the root scope
/// that allocated it. Both fields participate in equality and hashing.
final class ClientResourceId {
  /// Creates an identity for a resource already allocated by a root scope.
  const ClientResourceId(this.scopeId, this.sequence);

  /// The opaque namespace of the allocating root scope.
  final String scopeId;

  /// The resource sequence within that namespace.
  final int sequence;

  @override
  bool operator ==(Object other) =>
      other is ClientResourceId &&
      scopeId == other.scopeId &&
      sequence == other.sequence;

  @override
  int get hashCode => Object.hash(scopeId, sequence);

  @override
  String toString() => '$scopeId:$sequence';
}

/// A resource whose owner can request and confirm asynchronous cleanup.
///
/// A proxy delegates to the actual owner; it does not create another native
/// close operation. The resource remains owned if cleanup fails.
abstract interface class ClientResource {
  /// The identity shared by this resource and its proxies.
  ClientResourceId get resourceId;

  /// Seals the resource and requests that pending consumers wake and stop.
  void requestClose();

  /// Joins the current close attempt and its real cleanup acknowledgement.
  ///
  /// Repeated calls join the same result, including a failure, rather than
  /// silently retrying or replacing the underlying resource.
  Future<void> close();

  /// Retries a failed cleanup on the original resource for management callers.
  ///
  /// Concurrent retries join one attempt; an already closed resource is a
  /// no-op. Business consumers should not initiate cleanup retries.
  Future<void> retryClose();
}

/// A consumer's demand for a resource that may be shared with other consumers.
abstract interface class ClientLease {
  /// The exact old resources retired by the first synchronous release step.
  ///
  /// A release that is not the last demand has no retirement identities.
  List<ClientResourceId> get retirementResourceIds;

  /// Revokes this demand once and joins any retirement it caused.
  ///
  /// Concurrent calls share the in-flight release. After failure, a management
  /// retry may rejoin cleanup of the captured old resources without revoking a
  /// second demand or looking up a replacement resource.
  Future<void> release();
}

/// Whether an entry owns a resource or delegates to its actual owner.
enum ClientOwnership { owned, proxy }

/// The identity and synchronous stop state of one registered operation.
abstract interface class ClientOperation {
  /// The identity to pass through the adapter to the actual owner.
  ClientResourceId get resourceId;

  /// Whether the owning scope has requested this operation to stop.
  bool get closeRequested;
}

/// A registered creation attempt that retains its eventual resource.
///
/// Closing while creation is pending keeps the attempt owned and cleans up a
/// late resource instead of delivering it to the consumer.
abstract interface class ClientAcquisition<R extends ClientResource>
    implements ClientResource {
  /// The created resource, or a creation or [ClientResourceClosed] failure.
  Future<R> get ready;

  /// Whether creation has settled and all cleanup has completed successfully.
  ///
  /// A failed or still-running cleanup is not closed. A lease can omit an
  /// already closed acquisition from its retirement identities.
  bool get isClosed;
}

/// Indicates that an operation cannot be delivered because its scope closed.
final class ClientResourceClosed implements Exception {
  /// Creates the fixed closed-resource failure.
  const ClientResourceClosed();

  @override
  String toString() => 'ClientResourceClosed: the resource scope is closed';
}
