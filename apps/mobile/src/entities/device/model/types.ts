// The Gateway URL is stored separately (see shared/storage/gatewayURLStore) so that
// discarding an invalid device credential never discards the user's Gateway URL.
export interface DeviceCredential {
  deviceId: string;
  deviceName: string;
  credential: string;
}

export interface DeviceRegistration {
  device: { id: string; name: string };
  credential: string;
}
